`timescale 1ns/1ps

// ================================================================
// Testbench : tb_line_prefetcher
// P0-06 adversarial unit verification.
// Memory model preserves response ordering but injects random request stalls
// and random response latency, exercising multiple outstanding reads.
// ================================================================
module tb_line_prefetcher;
    reg clk = 1'b0;
    reg rst_n = 1'b0;

    reg start = 1'b0;
    reg [20:0] frame_base = 21'd0;
    reg [15:0] frame_width = 16'd0;
    reg [15:0] frame_height = 16'd0;
    reg [15:0] frame_stride_words = 16'd0;
    reg [15:0] line_index = 16'd0;

    wire mem_rd_valid;
    wire [20:0] mem_rd_addr;
    reg mem_rd_ready = 1'b0;
    reg mem_rvalid = 1'b0;
    reg [31:0] mem_rdata = 32'd0;

    reg lb_fill_ready = 1'b1;
    wire lb_fill_start;
    wire [15:0] lb_fill_line_index;
    wire [15:0] lb_fill_width;
    wire lb_fill_valid;
    wire [23:0] lb_fill_data;
    wire lb_fill_done;
    wire lb_fill_ok;

    wire busy;
    wire done;
    wire ok;
    wire timeout_error;
    wire protocol_error;
    wire recovery_required;
    wire [15:0] issued_count_debug;
    wire [15:0] received_count_debug;

    line_prefetcher #(
        .MAX_OUTSTANDING(8),
        .STALL_TIMEOUT_CYCLES(50)
    ) u_dut (
        .clk(clk), .rst_n(rst_n),
        .start(start), .frame_base(frame_base), .frame_width(frame_width),
        .frame_height(frame_height), .frame_stride_words(frame_stride_words),
        .line_index(line_index),
        .mem_rd_valid(mem_rd_valid), .mem_rd_addr(mem_rd_addr),
        .mem_rd_ready(mem_rd_ready), .mem_rvalid(mem_rvalid), .mem_rdata(mem_rdata),
        .lb_fill_ready(lb_fill_ready), .lb_fill_start(lb_fill_start),
        .lb_fill_line_index(lb_fill_line_index), .lb_fill_width(lb_fill_width),
        .lb_fill_valid(lb_fill_valid), .lb_fill_data(lb_fill_data),
        .lb_fill_done(lb_fill_done), .lb_fill_ok(lb_fill_ok),
        .busy(busy), .done(done), .ok(ok), .timeout_error(timeout_error),
        .protocol_error(protocol_error), .recovery_required(recovery_required),
        .issued_count_debug(issued_count_debug),
        .received_count_debug(received_count_debug)
    );

    always #5 clk = ~clk;

    localparam integer QMAX = 4096;
    reg [20:0] req_q [0:QMAX-1];
    integer delay_q [0:QMAX-1];
    integer q_head = 0;
    integer q_tail = 0;
    integer q_count = 0;

    reg [20:0] got_req [0:QMAX-1];
    reg [23:0] got_fill [0:QMAX-1];
    integer got_req_count = 0;
    integer got_fill_count = 0;
    integer fill_start_count = 0;
    integer fill_done_count = 0;
    integer fill_done_ok_count = 0;
    integer max_q_count = 0;

    integer ready_mode = 0; // 0=always, 1=random stalls, 2=never
    integer response_mode = 0; // 0=normal ordered response, 1=never, 2=inject one illegal response
    integer errors = 0;
    integer checks = 0;
    integer i;
    reg done_seen = 1'b0;
    reg last_ok = 1'b0;

    function [31:0] mem_word;
        input [20:0] a;
        begin
            mem_word = {8'hd5,
                        (a[7:0] ^ 8'h5a),
                        (a[15:8] + 8'h33),
                        (a[7:0] + a[15:8] + 8'h11)};
        end
    endfunction

    function [23:0] mem_rgb;
        input [20:0] a;
        begin
            mem_rgb = {(a[7:0] ^ 8'h5a),
                       (a[15:8] + 8'h33),
                       (a[7:0] + a[15:8] + 8'h11)};
        end
    endfunction

    task check_int;
        input integer got;
        input integer exp;
        input [8*100-1:0] msg;
        begin
            checks = checks + 1;
            if (got !== exp) begin
                $display("ERROR: %s got=%0d exp=%0d", msg, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    task check_addr;
        input [20:0] got;
        input [20:0] exp;
        input [8*100-1:0] msg;
        begin
            checks = checks + 1;
            if (got !== exp) begin
                $display("ERROR: %s got=%0d exp=%0d", msg, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    task check_data;
        input [23:0] got;
        input [23:0] exp;
        input [8*100-1:0] msg;
        begin
            checks = checks + 1;
            if (got !== exp) begin
                $display("ERROR: %s got=%06x exp=%06x", msg, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    task clear_case;
        begin
            q_head = 0;
            q_tail = 0;
            q_count = 0;
            got_req_count = 0;
            got_fill_count = 0;
            fill_start_count = 0;
            fill_done_count = 0;
            fill_done_ok_count = 0;
            max_q_count = 0;
            ready_mode = 0;
            response_mode = 0;
            lb_fill_ready = 1'b1;
            mem_rvalid = 1'b0;
            mem_rdata = 32'd0;
            done_seen = 1'b0;
            last_ok = 1'b0;
            start = 1'b0;
        end
    endtask

    task pulse_start;
        input [20:0] base_v;
        input [15:0] width_v;
        input [15:0] height_v;
        input [15:0] stride_v;
        input [15:0] line_v;
        begin
            @(negedge clk);
            frame_base = base_v;
            frame_width = width_v;
            frame_height = height_v;
            frame_stride_words = stride_v;
            line_index = line_v;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
        end
    endtask

    task wait_done_event;
        input integer max_cycles;
        integer c;
        begin
            c = 0;
            while (!done_seen && c < max_cycles) begin
                @(negedge clk);
                c = c + 1;
            end
            if (!done_seen) begin
                $display("ERROR: timeout waiting line_prefetcher done");
                errors = errors + 1;
            end
        end
    endtask

    task verify_success_line;
        input integer base_addr;
        input integer width_v;
        integer k;
        reg [20:0] a;
        begin
            check_int(last_ok, 1, "prefetch success");
            check_int(fill_start_count, 1, "one fill_start");
            check_int(fill_done_count, 1, "one fill_done");
            check_int(fill_done_ok_count, 1, "fill_done ok");
            check_int(got_req_count, width_v, "request count");
            check_int(got_fill_count, width_v, "fill data count");
            for (k = 0; k < width_v; k = k + 1) begin
                a = base_addr + k;
                check_addr(got_req[k], a, "sequential memory address");
                check_data(got_fill[k], mem_rgb(a), "RGB payload from ordered response");
            end
            checks = checks + 1;
            if (max_q_count > 8) begin
                $display("ERROR: outstanding queue exceeded 8: %0d", max_q_count);
                errors = errors + 1;
            end
        end
    endtask

    // Request acceptance is sampled on the same edge as the DUT.
    always @(posedge clk) begin
        if (rst_n) begin
            if (mem_rd_valid && mem_rd_ready) begin
                if (q_count >= QMAX) begin
                    $display("ERROR: request queue overflow");
                    errors = errors + 1;
                end else begin
                    req_q[q_tail] = mem_rd_addr;
                    delay_q[q_tail] = ($random & 32'h7); // 0..7 cycles at queue head
                    q_tail = (q_tail + 1) % QMAX;
                    q_count = q_count + 1;
                    if (q_count > max_q_count) max_q_count = q_count;
                    got_req[got_req_count] = mem_rd_addr;
                    got_req_count = got_req_count + 1;
                end
            end

            if (mem_rvalid) begin
                if (q_count <= 0) begin
                    // Some tests intentionally inject an illegal response.
                end else begin
                    q_head = (q_head + 1) % QMAX;
                    q_count = q_count - 1;
                end
            end

            if (lb_fill_start)
                fill_start_count = fill_start_count + 1;
            if (lb_fill_valid) begin
                got_fill[got_fill_count] = lb_fill_data;
                got_fill_count = got_fill_count + 1;
            end
            if (lb_fill_done) begin
                fill_done_count = fill_done_count + 1;
                if (lb_fill_ok) fill_done_ok_count = fill_done_ok_count + 1;
            end
            if (done) begin
                done_seen = 1'b1;
                last_ok = ok;
            end
        end
    end

    // Downstream readiness and ordered response source are driven on negedge.
    always @(negedge clk) begin
        if (!rst_n) begin
            mem_rd_ready = 1'b0;
            mem_rvalid = 1'b0;
            mem_rdata = 32'd0;
        end else begin
            case (ready_mode)
                0: mem_rd_ready = 1'b1;
                1: mem_rd_ready = (($random & 32'h3) != 0); // ~75% ready
                default: mem_rd_ready = 1'b0;
            endcase

            mem_rvalid = 1'b0;
            if (response_mode == 2) begin
                mem_rvalid = 1'b1;
                mem_rdata = 32'h00112233;
                response_mode = 1; // one-shot illegal response, then stop
            end else if ((response_mode == 0) && (q_count > 0)) begin
                if (delay_q[q_head] > 0) begin
                    delay_q[q_head] = delay_q[q_head] - 1;
                end else if (($random & 32'h3) != 0) begin
                    mem_rvalid = 1'b1;
                    mem_rdata = mem_word(req_q[q_head]);
                end
            end
        end
    end

    initial begin
        $display("tb_line_prefetcher start");
        repeat (5) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        repeat (2) @(posedge clk); @(negedge clk);

        // CASE0: small baseline line, exact addresses and data.
        $display("CASE0 width=4 base=100 line=0");
        clear_case;
        pulse_start(21'd100, 16'd4, 16'd2, 16'd640, 16'd0);
        wait_done_event(500);
        verify_success_line(100, 4);
        check_int(lb_fill_line_index, 0, "case0 fill line index");
        check_int(lb_fill_width, 4, "case0 fill width");

        // CASE1: no memory request may escape before a line-buffer bank exists.
        $display("CASE1 wait for lb_fill_ready before memory reads");
        clear_case;
        lb_fill_ready = 1'b0;
        pulse_start(21'd200, 16'd17, 16'd10, 16'd32, 16'd3);
        repeat (12) @(negedge clk);
        check_int(got_req_count, 0, "case1 no requests while line buffer blocked");
        check_int(fill_start_count, 0, "case1 no fill_start before ready");
        lb_fill_ready = 1'b1;
        wait_done_event(1000);
        verify_success_line(200 + 3*32, 17);

        // CASE2: 640-wide line with random request stalls/response latency.
        $display("CASE2 width=640 random memory stalls, multiple outstanding");
        clear_case;
        ready_mode = 1;
        pulse_start(21'd0, 16'd640, 16'd480, 16'd640, 16'd123);
        wait_done_event(20000);
        verify_success_line(123*640, 640);
        checks = checks + 1;
        if (max_q_count <= 1) begin
            $display("ERROR: case2 never exercised multiple outstanding requests, max=%0d", max_q_count);
            errors = errors + 1;
        end

        // CASE3: last baseline row checks line-base arithmetic near frame end.
        $display("CASE3 baseline last row line=479");
        clear_case;
        ready_mode = 1;
        pulse_start(21'd0, 16'd640, 16'd480, 16'd640, 16'd479);
        wait_done_event(20000);
        verify_success_line(479*640, 640);
        check_addr(got_req[639], 21'd307199, "case3 last address of 640x480 frame");

        // CASE4: invalid line index must fail without allocating line buffer.
        $display("CASE4 line_index >= frame_height rejected");
        clear_case;
        pulse_start(21'd0, 16'd640, 16'd480, 16'd640, 16'd480);
        wait_done_event(100);
        check_int(last_ok, 0, "case4 fail");
        check_int(got_req_count, 0, "case4 no memory request");
        check_int(fill_start_count, 0, "case4 no line bank allocation");

        // CASE5: stride and base constraints.
        $display("CASE5 invalid stride/base rejected");
        clear_case;
        pulse_start(21'd0, 16'd100, 16'd2, 16'd99, 16'd0);
        wait_done_event(100);
        check_int(last_ok, 0, "case5 stride fail");
        clear_case;
        pulse_start(21'd2, 16'd100, 16'd2, 16'd100, 16'd0);
        wait_done_event(100);
        check_int(last_ok, 0, "case5 unaligned base fail");

        // CASE6: waiting forever for free line buffer times out cleanly.
        $display("CASE6 line-buffer allocation timeout");
        clear_case;
        lb_fill_ready = 1'b0;
        pulse_start(21'd0, 16'd17, 16'd2, 16'd20, 16'd0);
        wait_done_event(200);
        check_int(last_ok, 0, "case6 timeout fail");
        check_int(timeout_error, 1, "case6 timeout flag");
        check_int(fill_start_count, 0, "case6 no allocated bank");
        check_int(fill_done_count, 0, "case6 no release needed");

        // CASE7: allocated bank + memory request channel permanently blocked.
        $display("CASE7 memory request timeout releases allocated bank");
        clear_case;
        ready_mode = 2;
        pulse_start(21'd0, 16'd17, 16'd2, 16'd20, 16'd0);
        wait_done_event(300);
        check_int(last_ok, 0, "case7 timeout fail");
        check_int(timeout_error, 1, "case7 timeout flag");
        check_int(fill_start_count, 1, "case7 allocated bank");
        check_int(fill_done_count, 1, "case7 releases bank");
        check_int(fill_done_ok_count, 0, "case7 release is failed fill");

        // CASE8: requests accepted but responses never return -> timeout/release.
        $display("CASE8 memory response timeout with outstanding requests");
        clear_case;
        response_mode = 1;
        pulse_start(21'd0, 16'd17, 16'd2, 16'd20, 16'd0);
        wait_done_event(300);
        check_int(last_ok, 0, "case8 timeout fail");
        check_int(timeout_error, 1, "case8 timeout flag");
        check_int(fill_done_count, 1, "case8 failed fill released");
        checks = checks + 1;
        if (got_req_count <= 0) begin
            $display("ERROR: case8 expected accepted requests before response timeout");
            errors = errors + 1;
        end

        check_int(recovery_required, 1, "case8 recovery required");

        // CASE9: stale-response quarantine. A new transaction must not be allowed
        // to reinterpret late responses from the aborted line.
        $display("CASE9 stale-response quarantine blocks restart until reset");
        clear_case;
        pulse_start(21'd400, 16'd4, 16'd2, 16'd4, 16'd0);
        wait_done_event(100);
        check_int(last_ok, 0, "case9 restart blocked");
        check_int(recovery_required, 1, "case9 recovery still required");
        check_int(got_req_count, 0, "case9 no new memory request");

        // Reset both DUT state and the abstract memory queue before continuing.
        @(negedge clk); rst_n = 1'b0;
        clear_case;
        repeat (3) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        repeat (2) @(posedge clk); @(negedge clk);
        check_int(recovery_required, 0, "case9 reset clears quarantine");

        // CASE10: illegal response when no request is outstanding.
        $display("CASE10 unexpected mem_rvalid fails loudly");
        clear_case;
        ready_mode = 2; // prevent first request acceptance
        pulse_start(21'd0, 16'd4, 16'd2, 16'd4, 16'd0);
        // Wait until fill bank has been allocated and FETCH entered,
        // then ask the memory model to inject one response with zero outstanding.
        repeat (3) @(negedge clk);
        response_mode = 2;
        wait_done_event(100);
        check_int(last_ok, 0, "case12 fail");
        check_int(protocol_error, 1, "case10 protocol_error");
        check_int(fill_done_count, 1, "case11 releases allocated bank");
        check_int(got_fill_count, 0, "case10 illegal response not forwarded");

        // CASE11: start while busy is a protocol failure and releases bank.
        $display("CASE11 second start while busy rejected");
        clear_case;
        ready_mode = 2;
        pulse_start(21'd0, 16'd4, 16'd2, 16'd4, 16'd0);
        repeat (3) @(negedge clk);
        // Direct one-cycle start while current transaction is stuck in FETCH.
        @(negedge clk); start = 1'b1;
        @(negedge clk); start = 1'b0;
        wait_done_event(100);
        check_int(last_ok, 0, "case12 fail");
        check_int(protocol_error, 1, "case11 protocol error");
        check_int(fill_done_count, 1, "case11 releases allocated bank");

        // CASE12: address range overflow must be rejected before requests.
        $display("CASE12 21-bit SDRAM address overflow rejected");
        clear_case;
        pulse_start(21'd2097148, 16'd8, 16'd1, 16'd8, 16'd0);
        wait_done_event(100);
        check_int(last_ok, 0, "case12 fail");
        check_int(got_req_count, 0, "case12 no memory request");
        check_int(fill_start_count, 0, "case12 no buffer allocation");

        // CASE13: clean transaction after recoverable protocol failures, no reset.
        $display("CASE13 recovery after recoverable failure without global reset");
        clear_case;
        ready_mode = 1;
        pulse_start(21'd400, 16'd17, 16'd20, 16'd32, 16'd7);
        wait_done_event(1000);
        verify_success_line(400 + 7*32, 17);
        check_int(timeout_error, 0, "case13 timeout cleared on new start");
        check_int(protocol_error, 0, "case13 protocol_error cleared on new start");
        check_int(recovery_required, 0, "case13 no quarantine for recoverable path");

        if (errors == 0)
            $display("PASS: line_prefetcher all adversarial cases passed (checks=%0d)", checks);
        else
            $display("FAIL: line_prefetcher errors=%0d checks=%0d", errors, checks);
        $finish;
    end
endmodule
