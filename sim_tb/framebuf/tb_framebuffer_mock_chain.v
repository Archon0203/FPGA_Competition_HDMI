`timescale 1ns/1ps

// ================================================================
// Testbench : tb_framebuffer_mock_chain
// P0-08 [C-sub] integration regression:
//   frame_buffer_manager
//      -> framebuffer_writer --write--\
//                                sdram_arbiter -> mock_sdram
//      -> line_prefetcher ----read-/
//              -> line_buffer_pingpong -> display-order RGB stream
//
// The test intentionally runs writer and prefetcher concurrently to verify
// read-priority arbitration and frame isolation.
// ================================================================
module tb_framebuffer_mock_chain;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    integer errors = 0;
    integer checks = 0;

    // ---------------- Manager load controls ----------------
    reg load_start = 1'b0;
    reg [15:0] load_width = 16'd0;
    reg [15:0] load_height = 16'd0;
    reg [15:0] load_stride_words = 16'd0;
    wire load_ready;
    wire load_accept;
    wire manager_writer_start;
    wire [20:0] write_base;
    wire [15:0] write_width;
    wire [15:0] write_height;
    wire [15:0] write_stride_words;
    reg display_frame_boundary = 1'b0;
    wire [20:0] read_base;
    wire [15:0] read_width;
    wire [15:0] read_height;
    wire [15:0] read_stride_words;
    wire read_frame_valid;
    wire write_in_progress;
    wire pending_swap;
    wire swap_pulse;
    wire load_fail_pulse;
    wire read_buffer_sel;
    wire write_buffer_sel;
    wire manager_config_error;

    // ---------------- Writer source ----------------
    reg pixel_valid = 1'b0;
    reg [7:0] pixel_r = 8'd0;
    reg [7:0] pixel_g = 8'd0;
    reg [7:0] pixel_b = 8'd0;
    reg [15:0] pixel_x = 16'd0;
    reg [15:0] pixel_y = 16'd0;
    wire pixel_ready;
    reg source_done = 1'b0;
    reg source_ok = 1'b0;
    wire writer_mem_valid;
    wire [20:0] writer_mem_addr;
    wire [31:0] writer_mem_data;
    wire writer_mem_ready;
    wire writer_busy;
    wire writer_done;
    wire writer_ok;
    wire writer_overflow;

    // ---------------- Prefetcher ----------------
    reg prefetch_start = 1'b0;
    reg [15:0] prefetch_line_index = 16'd0;
    wire prefetch_mem_valid;
    wire [20:0] prefetch_mem_addr;
    wire prefetch_mem_ready;
    wire prefetch_rvalid;
    wire [31:0] prefetch_rdata;
    wire prefetch_busy;
    wire prefetch_done;
    wire prefetch_ok;
    wire prefetch_timeout_error;
    wire prefetch_protocol_error;
    wire prefetch_recovery_required;
    wire [15:0] prefetch_issued_debug;
    wire [15:0] prefetch_received_debug;

    // ---------------- Line buffer ----------------
    wire lb_fill_ready;
    wire lb_fill_start;
    wire [15:0] lb_fill_line_index;
    wire [15:0] lb_fill_width;
    wire lb_fill_valid;
    wire [23:0] lb_fill_data;
    wire lb_fill_done;
    wire lb_fill_ok;
    reg lb_read_start = 1'b0;
    reg [15:0] lb_read_line_index = 16'd0;
    reg [15:0] lb_read_width = 16'd0;
    wire lb_pixel_valid;
    wire [23:0] lb_pixel_data;
    wire lb_line_done;
    wire lb_underflow_pulse;
    wire lb_underflow_sticky;
    wire lb_protocol_error;
    wire lb_fill_active;
    wire lb_read_active;
    wire lb_bank0_ready;
    wire lb_bank1_ready;
    wire lb_fill_accept;
    wire lb_fill_commit_pulse;
    wire lb_fill_fail_pulse;

    // ---------------- Arbiter / mock memory ----------------
    wire mem_wr_valid;
    wire [20:0] mem_wr_addr;
    wire [31:0] mem_wr_data;
    wire mem_wr_ready;
    wire mem_rd_valid;
    wire [20:0] mem_rd_addr;
    wire mem_rd_ready;
    wire mem_rvalid;
    wire [31:0] mem_rdata;
    wire arb_protocol_error;
    wire arb_contention_seen;
    wire [15:0] arb_outstanding;
    wire [31:0] arb_read_count;
    wire [31:0] arb_write_count;

    reg random_stalls_enable = 1'b1;
    reg force_wr_stall = 1'b0;
    reg force_rd_stall = 1'b0;
    reg force_resp_stall = 1'b0;
    wire mock_range_error;
    wire mock_queue_error;
    wire mock_write_commit_pulse;
    wire [20:0] mock_write_commit_addr;
    wire [31:0] mock_write_commit_data;
    wire mock_read_response_pulse;
    wire [20:0] mock_read_response_addr;
    wire [15:0] mock_pending_reads;

    integer contention_cycles = 0;
    integer read_priority_accepts = 0;

    frame_buffer_manager u_manager (
        .clk(clk), .rst_n(rst_n),
        .load_start(load_start), .load_width(load_width), .load_height(load_height),
        .load_stride_words(load_stride_words), .load_ready(load_ready),
        .load_accept(load_accept), .writer_start(manager_writer_start),
        .write_base(write_base), .write_width(write_width), .write_height(write_height),
        .write_stride_words(write_stride_words), .writer_done(writer_done), .writer_ok(writer_ok),
        .display_frame_boundary(display_frame_boundary),
        .read_base(read_base), .read_width(read_width), .read_height(read_height),
        .read_stride_words(read_stride_words), .read_frame_valid(read_frame_valid),
        .write_in_progress(write_in_progress), .pending_swap(pending_swap),
        .swap_pulse(swap_pulse), .load_fail_pulse(load_fail_pulse),
        .read_buffer_sel(read_buffer_sel), .write_buffer_sel(write_buffer_sel),
        .config_error(manager_config_error)
    );

    framebuffer_writer #(.PIXEL_FIFO_DEPTH(8)) u_writer (
        .clk(clk), .rst_n(rst_n), .start(manager_writer_start),
        .frame_base(write_base), .frame_width(write_width), .frame_height(write_height),
        .frame_stride_words(write_stride_words),
        .pixel_valid(pixel_valid), .pixel_r(pixel_r), .pixel_g(pixel_g), .pixel_b(pixel_b),
        .pixel_x(pixel_x), .pixel_y(pixel_y), .pixel_ready(pixel_ready),
        .source_done(source_done), .source_ok(source_ok),
        .mem_wr_valid(writer_mem_valid), .mem_wr_addr(writer_mem_addr),
        .mem_wr_data(writer_mem_data), .mem_wr_ready(writer_mem_ready),
        .busy(writer_busy), .done(writer_done), .ok(writer_ok), .overflow(writer_overflow)
    );

    sdram_arbiter #(.MAX_READ_OUTSTANDING(16)) u_arbiter (
        .clk(clk), .rst_n(rst_n),
        .wr_valid(writer_mem_valid), .wr_addr(writer_mem_addr), .wr_data(writer_mem_data),
        .wr_ready(writer_mem_ready),
        .rd_valid(prefetch_mem_valid), .rd_addr(prefetch_mem_addr), .rd_ready(prefetch_mem_ready),
        .rd_rvalid(prefetch_rvalid), .rd_rdata(prefetch_rdata),
        .mem_wr_valid(mem_wr_valid), .mem_wr_addr(mem_wr_addr), .mem_wr_data(mem_wr_data),
        .mem_wr_ready(mem_wr_ready),
        .mem_rd_valid(mem_rd_valid), .mem_rd_addr(mem_rd_addr), .mem_rd_ready(mem_rd_ready),
        .mem_rvalid(mem_rvalid), .mem_rdata(mem_rdata),
        .protocol_error(arb_protocol_error), .contention_seen(arb_contention_seen),
        .rd_outstanding_debug(arb_outstanding),
        .read_accept_count_debug(arb_read_count), .write_accept_count_debug(arb_write_count)
    );

    mock_sdram #(
        .DEPTH_WORDS(400000), .MAX_PENDING_READS(32),
        .MIN_READ_LATENCY(1), .MAX_READ_LATENCY(7)
    ) u_mock (
        .clk(clk), .rst_n(rst_n),
        .wr_valid(mem_wr_valid), .wr_addr(mem_wr_addr), .wr_data(mem_wr_data), .wr_ready(mem_wr_ready),
        .rd_valid(mem_rd_valid), .rd_addr(mem_rd_addr), .rd_ready(mem_rd_ready),
        .rvalid(mem_rvalid), .rdata(mem_rdata),
        .random_stalls_enable(random_stalls_enable),
        .force_wr_stall(force_wr_stall), .force_rd_stall(force_rd_stall),
        .force_resp_stall(force_resp_stall),
        .range_error(mock_range_error), .queue_error(mock_queue_error),
        .write_commit_pulse(mock_write_commit_pulse), .write_commit_addr(mock_write_commit_addr),
        .write_commit_data(mock_write_commit_data),
        .read_response_pulse(mock_read_response_pulse), .read_response_addr(mock_read_response_addr),
        .pending_reads_debug(mock_pending_reads)
    );

    line_prefetcher #(.MAX_OUTSTANDING(8), .STALL_TIMEOUT_CYCLES(5000)) u_prefetch (
        .clk(clk), .rst_n(rst_n), .start(prefetch_start),
        .frame_base(read_base), .frame_width(read_width), .frame_height(read_height),
        .frame_stride_words(read_stride_words), .line_index(prefetch_line_index),
        .mem_rd_valid(prefetch_mem_valid), .mem_rd_addr(prefetch_mem_addr),
        .mem_rd_ready(prefetch_mem_ready), .mem_rvalid(prefetch_rvalid), .mem_rdata(prefetch_rdata),
        .lb_fill_ready(lb_fill_ready), .lb_fill_start(lb_fill_start),
        .lb_fill_line_index(lb_fill_line_index), .lb_fill_width(lb_fill_width),
        .lb_fill_valid(lb_fill_valid), .lb_fill_data(lb_fill_data),
        .lb_fill_done(lb_fill_done), .lb_fill_ok(lb_fill_ok),
        .busy(prefetch_busy), .done(prefetch_done), .ok(prefetch_ok),
        .timeout_error(prefetch_timeout_error), .protocol_error(prefetch_protocol_error),
        .recovery_required(prefetch_recovery_required),
        .issued_count_debug(prefetch_issued_debug), .received_count_debug(prefetch_received_debug)
    );

    line_buffer_pingpong #(.MAX_LINE_PIXELS(640)) u_linebuf (
        .clk(clk), .rst_n(rst_n),
        .fill_ready(lb_fill_ready), .fill_start(lb_fill_start),
        .fill_line_index(lb_fill_line_index), .fill_width(lb_fill_width), .fill_accept(lb_fill_accept),
        .fill_valid(lb_fill_valid), .fill_data(lb_fill_data),
        .fill_done(lb_fill_done), .fill_ok(lb_fill_ok),
        .fill_commit_pulse(lb_fill_commit_pulse), .fill_fail_pulse(lb_fill_fail_pulse),
        .read_start(lb_read_start), .read_line_index(lb_read_line_index), .read_width(lb_read_width),
        .pixel_valid(lb_pixel_valid), .pixel_data(lb_pixel_data), .line_done(lb_line_done),
        .underflow_pulse(lb_underflow_pulse), .underflow_sticky(lb_underflow_sticky),
        .protocol_error(lb_protocol_error), .fill_active(lb_fill_active), .read_active(lb_read_active),
        .bank0_ready(lb_bank0_ready), .bank1_ready(lb_bank1_ready)
    );

    always @(posedge clk) begin
        if (rst_n && writer_mem_valid && prefetch_mem_valid) begin
            contention_cycles = contention_cycles + 1;
            if (prefetch_mem_ready && !writer_mem_ready)
                read_priority_accepts = read_priority_accepts + 1;
            if (writer_mem_ready) begin
                $display("ERROR: writer accepted while read request also valid");
                errors = errors + 1;
            end
        end
    end

    function [7:0] source_r;
        input [7:0] seed;
        input integer x;
        input integer y;
        integer v;
        begin v = seed + x*3 + y*5; source_r = v[7:0]; end
    endfunction
    function [7:0] source_g;
        input [7:0] seed;
        input integer x;
        input integer y;
        integer v;
        begin v = 8'h40 + seed + x*7 + y*2; source_g = v[7:0]; end
    endfunction
    function [7:0] source_b;
        input [7:0] seed;
        input integer x;
        input integer y;
        integer v;
        begin v = 8'h80 + seed*3 + x + y*11; source_b = v[7:0]; end
    endfunction

    // Scoreboard implementation is kept separate from source channel functions.
    function [23:0] expected_rgb;
        input [7:0] seed;
        input integer x;
        input integer y;
        reg [7:0] er;
        reg [7:0] eg;
        reg [7:0] eb;
        integer vr, vg, vb;
        begin
            vr = seed + (3*x) + (5*y);
            vg = 64 + seed + (7*x) + (2*y);
            vb = 128 + (3*seed) + x + (11*y);
            er = vr[7:0];
            eg = vg[7:0];
            eb = vb[7:0];
            expected_rgb = {er,eg,eb};
        end
    endfunction

    task check_int;
        input integer got;
        input integer exp;
        input [8*120-1:0] msg;
        begin
            checks = checks + 1;
            if (got !== exp) begin
                $display("ERROR: %s got=%0d exp=%0d", msg, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    task check_rgb;
        input [23:0] got;
        input [23:0] exp;
        input [8*120-1:0] msg;
        begin
            checks = checks + 1;
            if (got !== exp) begin
                $display("ERROR: %s got=%06x exp=%06x", msg, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    task pulse_load;
        input integer w;
        input integer h;
        begin
            while (!load_ready) @(negedge clk);
            @(negedge clk);
            load_width = w;
            load_height = h;
            load_stride_words = w;
            load_start = 1'b1;
            @(negedge clk);
            load_start = 1'b0;
            while (!writer_busy) @(negedge clk);
        end
    endtask

    task send_one_pixel;
        input integer x;
        input integer y;
        input [7:0] seed;
        begin
            while (!pixel_ready) @(negedge clk);
            pixel_x = x;
            pixel_y = y;
            pixel_r = source_r(seed,x,y);
            pixel_g = source_g(seed,x,y);
            pixel_b = source_b(seed,x,y);
            pixel_valid = 1'b1;
            @(negedge clk);
            pixel_valid = 1'b0;
        end
    endtask

    task produce_frame_pixels;
        input [7:0] seed;
        input integer w;
        input integer h;
        integer x, y;
        begin
            // Match baseline BMP pixel stream order: bottom row first.
            for (y = h-1; y >= 0; y = y-1)
                for (x = 0; x < w; x = x+1)
                    send_one_pixel(x,y,seed);

            @(negedge clk);
            source_ok = 1'b1;
            source_done = 1'b1;
            @(negedge clk);
            source_done = 1'b0;
            source_ok = 1'b0;

            while (!writer_done) @(negedge clk);
            check_int(writer_ok, 1, "writer transaction success");
            check_int(writer_overflow, 0, "writer no overflow");
        end
    endtask

    task wait_pending_and_swap;
        begin
            while (!pending_swap) @(negedge clk);
            @(negedge clk); display_frame_boundary = 1'b1;
            @(negedge clk); display_frame_boundary = 1'b0;
            // Manager emits swap_pulse for one cycle around the boundary.
            repeat (2) @(negedge clk);
            check_int(read_frame_valid, 1, "front frame valid after swap");
            check_int(pending_swap, 0, "pending swap cleared");
        end
    endtask

    task load_frame_and_swap;
        input [7:0] seed;
        input integer w;
        input integer h;
        begin
            pulse_load(w,h);
            produce_frame_pixels(seed,w,h);
            wait_pending_and_swap;
        end
    endtask

    task prefetch_and_check_line;
        input [7:0] seed;
        input integer line_no;
        integer count;
        integer gap_after_start;
        reg started;
        reg [23:0] exp;
        begin
            if (!read_frame_valid) begin
                $display("ERROR: attempted prefetch with invalid front frame");
                errors = errors + 1;
            end
            while (prefetch_busy) @(negedge clk);
            @(negedge clk);
            prefetch_line_index = line_no;
            prefetch_start = 1'b1;
            @(negedge clk);
            prefetch_start = 1'b0;

            while (!prefetch_done) @(negedge clk);
            check_int(prefetch_ok, 1, "prefetch success");
            check_int(prefetch_timeout_error, 0, "prefetch no timeout");
            check_int(prefetch_protocol_error, 0, "prefetch no protocol error");
            check_int(prefetch_recovery_required, 0, "prefetch no quarantine");

            @(negedge clk);
            lb_read_line_index = line_no;
            lb_read_width = read_width;
            lb_read_start = 1'b1;
            @(negedge clk);
            lb_read_start = 1'b0;

            count = 0;
            started = 1'b0;
            gap_after_start = 0;
            while (count < read_width) begin
                @(negedge clk);
                if (lb_pixel_valid) begin
                    if (started && gap_after_start != 0) begin
                        $display("ERROR: active line pixel_valid gap after start");
                        errors = errors + 1;
                    end
                    started = 1'b1;
                    gap_after_start = 0;
                    exp = expected_rgb(seed, count, line_no);
                    check_rgb(lb_pixel_data, exp, "display-order RGB");
                    count = count + 1;
                end else if (started && (count < read_width)) begin
                    gap_after_start = gap_after_start + 1;
                end
            end
            check_int(lb_line_done, 1, "line_done with final pixel");
            check_int(lb_underflow_pulse, 0, "no line underflow");
        end
    endtask

    initial begin
        // Global reset.
        load_start = 0; pixel_valid = 0; source_done = 0; source_ok = 0;
        prefetch_start = 0; lb_read_start = 0; display_frame_boundary = 0;
        random_stalls_enable = 1;
        @(negedge clk); rst_n = 1'b0;
        repeat (5) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        repeat (3) @(posedge clk);

        $display("CASE-GOLDEN fixed RGB sanity");
        check_rgb(expected_rgb(8'h10,0,0), 24'h1050B0, "golden seed10 x0 y0");
        check_rgb(expected_rgb(8'h10,1,2), 24'h1D5BC7, "golden seed10 x1 y2");
        check_int(manager_config_error, 0, "manager map valid");

        $display("CASE0 first frame 17x5 -> B -> swap -> all lines");
        load_frame_and_swap(8'h10,17,5);
        check_int(read_buffer_sel, 1, "first complete frame is Image B");
        check_int(read_width, 17, "front width 17");
        check_int(read_height, 5, "front height 5");
        prefetch_and_check_line(8'h10,0);
        prefetch_and_check_line(8'h10,1);
        prefetch_and_check_line(8'h10,2);
        prefetch_and_check_line(8'h10,3);
        prefetch_and_check_line(8'h10,4);

        $display("CASE1 concurrent load to A + display read from B, then 640x2 baseline");
        contention_cycles = 0;
        read_priority_accepts = 0;
        pulse_load(640,2);
        fork
            begin
                produce_frame_pixels(8'h20,640,2);
            end
            begin
                // Wait until the writer actually has queued traffic, then issue a
                // display line read against the still-visible Image B.
                while (!writer_mem_valid) @(negedge clk);
                prefetch_and_check_line(8'h10,3);
            end
        join
        check_int((contention_cycles > 0), 1, "writer/read contention observed");
        check_int((read_priority_accepts > 0), 1, "read priority accepted during contention");
        wait_pending_and_swap;
        check_int(read_buffer_sel, 0, "second frame swaps to Image A");
        check_int(read_width, 640, "640 baseline width");
        check_int(read_height, 2, "640 baseline height 2");
        prefetch_and_check_line(8'h20,0);
        prefetch_and_check_line(8'h20,1);

        $display("CASE2 third frame 9x3 reuses Image B without reset");
        random_stalls_enable = 1'b0;
        load_frame_and_swap(8'h33,9,3);
        check_int(read_buffer_sel, 1, "third frame returns to Image B");
        prefetch_and_check_line(8'h33,0);
        prefetch_and_check_line(8'h33,2);

        $display("CASE3 sticky integration status");
        check_int(arb_protocol_error, 0, "arbiter no protocol error");
        check_int(arb_contention_seen, 1, "arbiter recorded contention");
        check_int(arb_outstanding, 0, "arbiter no outstanding at end");
        check_int(mock_pending_reads, 0, "mock no pending reads at end");
        check_int(mock_range_error, 0, "mock no range error");
        check_int(mock_queue_error, 0, "mock no queue error");
        check_int(lb_protocol_error, 0, "line buffer no protocol error");
        check_int(lb_underflow_sticky, 0, "line buffer no underflow");
        check_int(load_fail_pulse, 0, "manager no load failure pulse at end");
        check_int((arb_write_count > 1300), 1, "many writes traversed arbiter");
        check_int((arb_read_count > 1300), 1, "many reads traversed arbiter");

        if (errors == 0)
            $display("PASS: framebuffer mock chain all integration cases passed (checks=%0d)", checks);
        else
            $display("FAIL: framebuffer mock chain errors=%0d checks=%0d", errors, checks);
        $finish;
    end
endmodule
