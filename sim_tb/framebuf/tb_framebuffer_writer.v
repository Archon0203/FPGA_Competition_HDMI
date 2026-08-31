`timescale 1ns/1ps

// ================================================================
// Testbench : tb_framebuffer_writer
// P0-03 adversarial unit verification.
//
// Covers:
//   - 0x00RRGGBB packing
//   - bottom-up coordinate stream -> display-order framebuffer addresses
//   - 640-word stride baseline
//   - bounded random mem_wr_ready stalls
//   - source_done while writes still pending
//   - invalid coordinate / source error / invalid configuration
//   - FIFO overflow must fail loudly, never overwrite silently
//   - back-to-back transactions without global reset
// ================================================================

module tb_framebuffer_writer;
    reg clk = 1'b0;
    reg rst_n = 1'b0;

    reg start = 1'b0;
    reg [20:0] frame_base = 21'd0;
    reg [15:0] frame_width = 16'd0;
    reg [15:0] frame_height = 16'd0;
    reg [15:0] frame_stride_words = 16'd0;

    reg pixel_valid = 1'b0;
    reg [7:0] pixel_r = 8'd0;
    reg [7:0] pixel_g = 8'd0;
    reg [7:0] pixel_b = 8'd0;
    reg [15:0] pixel_x = 16'd0;
    reg [15:0] pixel_y = 16'd0;
    wire pixel_ready;

    reg source_done = 1'b0;
    reg source_ok = 1'b0;

    wire mem_wr_valid;
    wire [20:0] mem_wr_addr;
    wire [31:0] mem_wr_data;
    reg mem_wr_ready = 1'b0;

    wire busy;
    wire done;
    wire ok;
    wire overflow;

    framebuffer_writer #(
        .PIXEL_FIFO_DEPTH(8)
    ) u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .frame_base(frame_base),
        .frame_width(frame_width),
        .frame_height(frame_height),
        .frame_stride_words(frame_stride_words),
        .pixel_valid(pixel_valid),
        .pixel_r(pixel_r),
        .pixel_g(pixel_g),
        .pixel_b(pixel_b),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .pixel_ready(pixel_ready),
        .source_done(source_done),
        .source_ok(source_ok),
        .mem_wr_valid(mem_wr_valid),
        .mem_wr_addr(mem_wr_addr),
        .mem_wr_data(mem_wr_data),
        .mem_wr_ready(mem_wr_ready),
        .busy(busy),
        .done(done),
        .ok(ok),
        .overflow(overflow)
    );

    always #5 clk = ~clk;

    localparam integer MAX_WRITES = 4096;
    reg [20:0] exp_addr [0:MAX_WRITES-1];
    reg [31:0] exp_data [0:MAX_WRITES-1];
    reg [20:0] got_addr [0:MAX_WRITES-1];
    reg [31:0] got_data [0:MAX_WRITES-1];

    integer exp_count = 0;
    integer got_count = 0;
    integer errors = 0;
    integer checks = 0;
    integer i;

    integer ready_mode = 0; // 0=always ready, 1=bounded random stall, 2=force stall
    integer stall_left = 0;

    reg done_seen = 1'b0;
    reg last_ok = 1'b0;

    function [7:0] pat_r;
        input integer x;
        begin pat_r = (8'h20 + (x & 8'h7F)); end
    endfunction

    function [7:0] pat_g;
        input integer x;
        begin pat_g = (8'h40 + ((x * 3) & 8'h7F)); end
    endfunction

    function [7:0] pat_b;
        input integer x;
        begin pat_b = (8'h60 + ((x * 5) & 8'h7F)); end
    endfunction

    task check_int;
        input integer got;
        input integer exp;
        input [8*96-1:0] msg;
        begin
            checks = checks + 1;
            if (got !== exp) begin
                $display("ERROR: %s got=%0d exp=%0d", msg, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    task check_word;
        input [31:0] got;
        input [31:0] exp;
        input [8*96-1:0] msg;
        begin
            checks = checks + 1;
            if (got !== exp) begin
                $display("ERROR: %s got=%08x exp=%08x", msg, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    task check_addr;
        input [20:0] got;
        input [20:0] exp;
        input [8*96-1:0] msg;
        begin
            checks = checks + 1;
            if (got !== exp) begin
                $display("ERROR: %s got=%0d exp=%0d", msg, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    task clear_case;
        begin
            exp_count = 0;
            got_count = 0;
            done_seen = 1'b0;
            last_ok = 1'b0;
            ready_mode = 0;
            stall_left = 0;
            pixel_valid = 1'b0;
            source_done = 1'b0;
            source_ok = 1'b0;
            start = 1'b0;
        end
    endtask

    task add_expected;
        input [20:0] a;
        input [31:0] d;
        begin
            if (exp_count >= MAX_WRITES) begin
                $display("ERROR: expected-write array overflow");
                errors = errors + 1;
            end else begin
                exp_addr[exp_count] = a;
                exp_data[exp_count] = d;
                exp_count = exp_count + 1;
            end
        end
    endtask

    task pulse_start;
        input [20:0] base_v;
        input [15:0] width_v;
        input [15:0] height_v;
        input [15:0] stride_v;
        begin
            @(negedge clk);
            frame_base = base_v;
            frame_width = width_v;
            frame_height = height_v;
            frame_stride_words = stride_v;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
        end
    endtask

    // Normal producer: one-cycle pixel_valid and optional idle gap afterwards.
    // It checks pixel_ready before transmission but otherwise does not hold valid.
    task send_pixel;
        input [15:0] x_v;
        input [15:0] y_v;
        input [7:0] r_v;
        input [7:0] g_v;
        input [7:0] b_v;
        input integer gap_cycles;
        integer g;
        begin
            @(negedge clk);
            if (!pixel_ready) begin
                $display("ERROR: normal producer saw pixel_ready=0 at x=%0d y=%0d", x_v, y_v);
                errors = errors + 1;
            end
            pixel_x = x_v;
            pixel_y = y_v;
            pixel_r = r_v;
            pixel_g = g_v;
            pixel_b = b_v;
            pixel_valid = 1'b1;
            @(negedge clk);
            pixel_valid = 1'b0;
            for (g = 0; g < gap_cycles; g = g + 1)
                @(negedge clk);
        end
    endtask

    // Adversarial producer intentionally ignores pixel_ready, used only to prove
    // FIFO overflow is reported instead of silently corrupting pending writes.
    task force_pixel;
        input [15:0] x_v;
        input [15:0] y_v;
        input [7:0] r_v;
        input [7:0] g_v;
        input [7:0] b_v;
        begin
            @(negedge clk);
            pixel_x = x_v;
            pixel_y = y_v;
            pixel_r = r_v;
            pixel_g = g_v;
            pixel_b = b_v;
            pixel_valid = 1'b1;
            @(negedge clk);
            pixel_valid = 1'b0;
        end
    endtask

    task pulse_source_done;
        input integer success;
        begin
            @(negedge clk);
            source_ok = success ? 1'b1 : 1'b0;
            source_done = 1'b1;
            @(negedge clk);
            source_done = 1'b0;
            source_ok = 1'b0;
        end
    endtask

    task wait_done_event;
        input integer max_cycles;
        integer c;
        begin
            c = 0;
            // Sample at negedge so DUT/monitor nonblocking updates from the
            // previous posedge are already stable and race-free.
            while (!done_seen && c < max_cycles) begin
                @(negedge clk);
                c = c + 1;
            end
            if (!done_seen) begin
                $display("ERROR: timeout waiting framebuffer_writer done");
                errors = errors + 1;
            end
        end
    endtask

    task compare_writes;
        integer k;
        begin
            check_int(got_count, exp_count, "write count");
            for (k = 0; k < exp_count && k < got_count; k = k + 1) begin
                check_addr(got_addr[k], exp_addr[k], "write address");
                check_word(got_data[k], exp_data[k], "write data");
            end
        end
    endtask

    // Bounded-stall downstream. At most two deliberate low cycles are injected
    // per stall burst, so normal SD-like pixel cadence cannot overflow depth=8.
    always @(negedge clk) begin
        if (!rst_n) begin
            mem_wr_ready = 1'b0;
            stall_left = 0;
        end else begin
            case (ready_mode)
                0: begin
                    mem_wr_ready = 1'b1;
                    stall_left = 0;
                end
                1: begin
                    if (stall_left > 0) begin
                        mem_wr_ready = 1'b0;
                        stall_left = stall_left - 1;
                    end else if (($random & 32'h7) == 0) begin
                        mem_wr_ready = 1'b0;
                        stall_left = ($random & 32'h1) + 1;
                    end else begin
                        mem_wr_ready = 1'b1;
                    end
                end
                default: begin
                    mem_wr_ready = 1'b0;
                    stall_left = 0;
                end
            endcase
        end
    end

    always @(posedge clk) begin
        if (rst_n && mem_wr_valid && mem_wr_ready) begin
            if (got_count >= MAX_WRITES) begin
                $display("ERROR: captured-write array overflow");
                errors = errors + 1;
            end else begin
                got_addr[got_count] = mem_wr_addr;
                got_data[got_count] = mem_wr_data;
                got_count = got_count + 1;
            end
        end

        if (rst_n && done) begin
            done_seen <= 1'b1;
            last_ok <= ok;
        end
    end

    initial begin
        $display("tb_framebuffer_writer start");
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);
        @(negedge clk);

        // ------------------------------------------------------------
        // CASE0: explicit 2x2 bottom-up coordinate order.
        // frame_base=100, stride=640 => y=1 row starts at 740.
        // ------------------------------------------------------------
        $display("CASE0 2x2 bottom-up coordinates + RGB packing");
        clear_case;
        ready_mode = 1;
        add_expected(21'd740, 32'h00112131);
        add_expected(21'd741, 32'h00122232);
        add_expected(21'd100, 32'h00132333);
        add_expected(21'd101, 32'h00142434);
        pulse_start(21'd100, 16'd2, 16'd2, 16'd640);
        send_pixel(0,1,8'h11,8'h21,8'h31,2);
        send_pixel(1,1,8'h12,8'h22,8'h32,2);
        send_pixel(0,0,8'h13,8'h23,8'h33,2);
        send_pixel(1,0,8'h14,8'h24,8'h34,2);
        pulse_source_done(1);
        wait_done_event(500);
        check_int(last_ok, 1, "case0 ok");
        check_int(overflow, 0, "case0 no overflow");
        compare_writes;

        // ------------------------------------------------------------
        // CASE1: formal 640-pixel row, bounded random downstream stalls.
        // ------------------------------------------------------------
        $display("CASE1 width=640 baseline row + bounded random stalls");
        clear_case;
        ready_mode = 1;
        pulse_start(21'd1024, 16'd640, 16'd1, 16'd640);
        for (i = 0; i < 640; i = i + 1) begin
            add_expected(21'd1024 + i,
                         {8'h00, pat_r(i), pat_g(i), pat_b(i)});
            send_pixel(i[15:0], 16'd0, pat_r(i), pat_g(i), pat_b(i), 2);
        end
        pulse_source_done(1);
        wait_done_event(5000);
        check_int(last_ok, 1, "case1 ok");
        check_int(overflow, 0, "case1 no overflow");
        compare_writes;

        // ------------------------------------------------------------
        // CASE2: source_done while all writes are still pending.
        // done must wait for mem_wr_ready to resume and FIFO to drain.
        // ------------------------------------------------------------
        $display("CASE2 source_done waits for pending writes to drain");
        clear_case;
        ready_mode = 2;
        add_expected(21'd2048, 32'h00314151);
        add_expected(21'd2049, 32'h00324252);
        add_expected(21'd2050, 32'h00334353);
        add_expected(21'd2051, 32'h00344454);
        pulse_start(21'd2048, 16'd4, 16'd1, 16'd640);
        send_pixel(0,0,8'h31,8'h41,8'h51,0);
        send_pixel(1,0,8'h32,8'h42,8'h52,0);
        send_pixel(2,0,8'h33,8'h43,8'h53,0);
        send_pixel(3,0,8'h34,8'h44,8'h54,0);
        pulse_source_done(1);
        repeat (20) @(posedge clk);
        @(negedge clk);
        check_int(done_seen, 0, "case2 must not finish before pending writes drain");
        ready_mode = 0;
        wait_done_event(200);
        check_int(last_ok, 1, "case2 ok after drain");
        compare_writes;

        // ------------------------------------------------------------
        // CASE3: out-of-range coordinate is rejected and frame fails.
        // ------------------------------------------------------------
        $display("CASE3 invalid pixel coordinate");
        clear_case;
        ready_mode = 0;
        add_expected(21'd4096, 32'h00506070);
        add_expected(21'd4097, 32'h00516171);
        add_expected(21'd4736, 32'h00526272);
        pulse_start(21'd4096, 16'd2, 16'd2, 16'd640);
        send_pixel(0,0,8'h50,8'h60,8'h70,0);
        send_pixel(1,0,8'h51,8'h61,8'h71,0);
        send_pixel(0,1,8'h52,8'h62,8'h72,0);
        // x=2 is illegal for width=2; no write expected.
        send_pixel(2,1,8'h53,8'h63,8'h73,0);
        pulse_source_done(1);
        wait_done_event(200);
        check_int(last_ok, 0, "case3 must fail");
        compare_writes;

        // ------------------------------------------------------------
        // CASE4: upstream source failure propagates after draining writes.
        // ------------------------------------------------------------
        $display("CASE4 upstream source_ok=0");
        clear_case;
        ready_mode = 0;
        add_expected(21'd8192, 32'h00708090);
        pulse_start(21'd8192, 16'd1, 16'd1, 16'd640);
        send_pixel(0,0,8'h70,8'h80,8'h90,0);
        pulse_source_done(0);
        wait_done_event(100);
        check_int(last_ok, 0, "case4 must fail");
        compare_writes;

        // ------------------------------------------------------------
        // CASE5: stride smaller than width is illegal.
        // ------------------------------------------------------------
        $display("CASE5 invalid stride<width");
        clear_case;
        pulse_start(21'd12288, 16'd5, 16'd1, 16'd4);
        wait_done_event(50);
        check_int(last_ok, 0, "case5 must fail");
        check_int(got_count, 0, "case5 no writes");

        // ------------------------------------------------------------
        // CASE6: Architecture Contract requires 4-word-aligned base.
        // ------------------------------------------------------------
        $display("CASE6 misaligned frame_base");
        clear_case;
        pulse_start(21'd3, 16'd1, 16'd1, 16'd640);
        wait_done_event(50);
        check_int(last_ok, 0, "case6 must fail");
        check_int(got_count, 0, "case6 no writes");

        // ------------------------------------------------------------
        // CASE7: adversarial source ignores pixel_ready while memory stalls.
        // Depth=8: first 8 retained, later bytes must set overflow/fail.
        // ------------------------------------------------------------
        $display("CASE7 FIFO overflow is reported, never silent");
        clear_case;
        ready_mode = 2;
        pulse_start(21'd16384, 16'd10, 16'd1, 16'd640);
        for (i = 0; i < 10; i = i + 1) begin
            if (i < 8)
                add_expected(21'd16384 + i,
                             {8'h00, pat_r(i), pat_g(i), pat_b(i)});
            force_pixel(i[15:0], 0, pat_r(i), pat_g(i), pat_b(i));
        end
        pulse_source_done(1);
        ready_mode = 0;
        wait_done_event(500);
        check_int(last_ok, 0, "case7 overflow frame must fail");
        check_int(overflow, 1, "case7 overflow flag");
        compare_writes;

        // ------------------------------------------------------------
        // CASE8: next transaction succeeds without global reset.
        // ------------------------------------------------------------
        $display("CASE8 back-to-back restart after failure");
        clear_case;
        ready_mode = 0;
        add_expected(21'd20000, 32'h00A1B2C3);
        pulse_start(21'd20000, 16'd1, 16'd1, 16'd640);
        send_pixel(0,0,8'hA1,8'hB2,8'hC3,0);
        pulse_source_done(1);
        wait_done_event(100);
        check_int(last_ok, 1, "case8 ok");
        check_int(overflow, 0, "case8 overflow cleared by start");
        compare_writes;

        if (errors == 0)
            $display("PASS: framebuffer_writer all adversarial cases passed (checks=%0d)", checks);
        else
            $display("FAIL: framebuffer_writer errors=%0d checks=%0d", errors, checks);

        $finish;
    end

endmodule
