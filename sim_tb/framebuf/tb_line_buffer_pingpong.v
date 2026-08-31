`timescale 1ns/1ps

// ================================================================
// Testbench : tb_line_buffer_pingpong
// P0-05 adversarial unit verification.
// ================================================================
module tb_line_buffer_pingpong;
    reg clk = 1'b0;
    reg rst_n = 1'b0;

    reg fill_start = 1'b0;
    reg [15:0] fill_line_index = 16'd0;
    reg [15:0] fill_width = 16'd0;
    wire fill_ready;
    wire fill_accept;
    reg fill_valid = 1'b0;
    reg [23:0] fill_data = 24'd0;
    reg fill_done = 1'b0;
    reg fill_ok = 1'b0;
    wire fill_commit_pulse;
    wire fill_fail_pulse;

    reg read_start = 1'b0;
    reg [15:0] read_line_index = 16'd0;
    reg [15:0] read_width = 16'd0;
    wire pixel_valid;
    wire [23:0] pixel_data;
    wire line_done;
    wire underflow_pulse;
    wire underflow_sticky;
    wire protocol_error;
    wire fill_active;
    wire read_active;
    wire bank0_ready;
    wire bank1_ready;

    line_buffer_pingpong #(.MAX_LINE_PIXELS(640)) u_dut (
        .clk(clk), .rst_n(rst_n),
        .fill_start(fill_start), .fill_line_index(fill_line_index),
        .fill_width(fill_width), .fill_ready(fill_ready), .fill_accept(fill_accept),
        .fill_valid(fill_valid), .fill_data(fill_data),
        .fill_done(fill_done), .fill_ok(fill_ok),
        .fill_commit_pulse(fill_commit_pulse), .fill_fail_pulse(fill_fail_pulse),
        .read_start(read_start), .read_line_index(read_line_index), .read_width(read_width),
        .pixel_valid(pixel_valid), .pixel_data(pixel_data), .line_done(line_done),
        .underflow_pulse(underflow_pulse), .underflow_sticky(underflow_sticky),
        .protocol_error(protocol_error), .fill_active(fill_active), .read_active(read_active),
        .bank0_ready(bank0_ready), .bank1_ready(bank1_ready)
    );

    always #5 clk = ~clk;

    integer errors = 0;
    integer checks = 0;
    integer commit_count = 0;
    integer fail_count = 0;
    integer underflow_count = 0;

    function [23:0] pattern;
        input integer line_no;
        input integer x;
        reg [7:0] r;
        reg [7:0] g;
        reg [7:0] b;
        begin
            // IMPORTANT: each channel is explicitly narrowed to 8 bits before
            // concatenation. Using unsized/integer arithmetic directly inside {}
            // creates 32-bit elements in Verilog and can silently truncate R/G.
            r = (line_no + x) & 8'hff;
            g = (8'h40 + x*3) & 8'hff;
            b = (8'h80 + line_no*5 + x) & 8'hff;
            pattern = {r, g, b};
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

    task check_pixel;
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

    task pulse_fill_start;
        input [15:0] line_v;
        input [15:0] width_v;
        begin
            @(negedge clk);
            fill_line_index = line_v;
            fill_width = width_v;
            fill_start = 1'b1;
            @(negedge clk);
            fill_start = 1'b0;
        end
    endtask

    task send_fill_word;
        input [23:0] d;
        begin
            @(negedge clk);
            fill_data = d;
            fill_valid = 1'b1;
            @(negedge clk);
            fill_valid = 1'b0;
        end
    endtask

    task pulse_fill_done;
        input integer success;
        begin
            @(negedge clk);
            fill_ok = success ? 1'b1 : 1'b0;
            fill_done = 1'b1;
            @(negedge clk);
            fill_done = 1'b0;
            fill_ok = 1'b0;
        end
    endtask

    task fill_line;
        input integer line_no;
        input integer width_v;
        integer k;
        begin
            if (!fill_ready) begin
                $display("ERROR: fill_line called while fill_ready=0 line=%0d", line_no);
                errors = errors + 1;
            end
            pulse_fill_start(line_no[15:0], width_v[15:0]);
            for (k = 0; k < width_v; k = k + 1)
                send_fill_word(pattern(line_no, k));
            pulse_fill_done(1);
            @(posedge clk); @(negedge clk);
        end
    endtask

    task pulse_read_start;
        input [15:0] line_v;
        input [15:0] width_v;
        begin
            @(negedge clk);
            read_line_index = line_v;
            read_width = width_v;
            read_start = 1'b1;
            @(negedge clk);
            read_start = 1'b0;
        end
    endtask

    task read_expect_line;
        input integer line_no;
        input integer width_v;
        input integer expect_black;
        integer k;
        integer guard;
        reg [23:0] exp;
        begin
            pulse_read_start(line_no[15:0], width_v[15:0]);
            // First output is defined to arrive one clock after request acceptance.
            guard = 0;
            while (!pixel_valid && guard < 20) begin
                @(negedge clk);
                guard = guard + 1;
            end
            if (!pixel_valid) begin
                $display("ERROR: timeout waiting first line pixel");
                errors = errors + 1;
            end
            for (k = 0; k < width_v; k = k + 1) begin
                if (k != 0)
                    @(negedge clk);
                checks = checks + 1;
                if (!pixel_valid) begin
                    $display("ERROR: pixel_valid gap at k=%0d line=%0d", k, line_no);
                    errors = errors + 1;
                end
                if (expect_black)
                    exp = 24'h000000;
                else
                    exp = pattern(line_no, k);
                check_pixel(pixel_data, exp, "line pixel");
                if (k == width_v-1) begin
                    checks = checks + 1;
                    if (!line_done) begin
                        $display("ERROR: line_done missing on last pixel");
                        errors = errors + 1;
                    end
                end else begin
                    checks = checks + 1;
                    if (line_done) begin
                        $display("ERROR: early line_done at k=%0d", k);
                        errors = errors + 1;
                    end
                end
            end
            @(negedge clk);
            check_int(pixel_valid, 0, "pixel_valid clears after line");
        end
    endtask

    always @(posedge clk) begin
        if (rst_n) begin
            if (fill_commit_pulse) commit_count = commit_count + 1;
            if (fill_fail_pulse) fail_count = fail_count + 1;
            if (underflow_pulse) underflow_count = underflow_count + 1;
        end
    end

    initial begin
        $display("tb_line_buffer_pingpong start");
        repeat (5) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        repeat (2) @(posedge clk); @(negedge clk);

        // CASE0: basic fill/read and exact RGB preservation.
        // ------------------------------------------------------------
        // CASE-GOLDEN: literal fixed-vector sanity for TB pattern().
        // This is intentionally NOT computed from the same expression as DUT
        // stimulus/scoreboard. It catches Verilog width/truncation mistakes in
        // the golden generator itself.
        // ------------------------------------------------------------
        $display("CASE-GOLDEN fixed RGB sanity");
        check_int(pattern(10, 0), 24'h0A40B2, "golden pattern line10 x0");
        check_int(pattern(10, 1), 24'h0B43B3, "golden pattern line10 x1");

        $display("CASE0 basic line fill/read");
        fill_line(10, 4);
        check_int(commit_count, 1, "case0 commit");
        check_int(bank0_ready + bank1_ready, 1, "case0 one ready bank");
        read_expect_line(10, 4, 0);
        check_int(bank0_ready + bank1_ready, 0, "case0 bank released after read");

        // CASE1: both banks ready blocks a third fill until one line is consumed.
        $display("CASE1 two-bank ownership/full behavior");
        fill_line(20, 3);
        fill_line(21, 3);
        check_int(bank0_ready + bank1_ready, 2, "case1 both banks ready");
        check_int(fill_ready, 0, "case1 no free bank");
        read_expect_line(20, 3, 0);
        check_int(fill_ready, 1, "case1 bank free after display line");
        fill_line(22, 3);
        read_expect_line(21, 3, 0);
        read_expect_line(22, 3, 0);

        // CASE2: requested line absent -> continuous black line, not a valid gap.
        $display("CASE2 missing line -> black underflow line");
        read_expect_line(99, 5, 1);
        check_int(underflow_count, 1, "case2 underflow pulse");
        check_int(underflow_sticky, 1, "case2 underflow sticky");

        // CASE3: width mismatch is treated as underflow rather than stale data.
        $display("CASE3 line width mismatch -> underflow");
        fill_line(30, 4);
        read_expect_line(30, 5, 1);
        check_int(underflow_count, 2, "case3 second underflow");
        // The stored 4-wide line is still ready and can be consumed correctly.
        read_expect_line(30, 4, 0);

        // CASE4: incomplete fill must never become ready.
        $display("CASE4 incomplete fill fails and bank is reusable");
        pulse_fill_start(16'd40, 16'd4);
        send_fill_word(pattern(40,0));
        send_fill_word(pattern(40,1));
        pulse_fill_done(1);
        @(posedge clk); @(negedge clk);
        check_int(fail_count, 1, "case4 fill failure event");
        check_int(fill_ready, 1, "case4 failed bank reusable");
        read_expect_line(40, 4, 1);
        check_int(underflow_count, 3, "case4 failed line not visible");

        // CASE5: too many fill words is a loud failure, not silent overwrite.
        $display("CASE5 fill overflow fails loudly");
        pulse_fill_start(16'd50, 16'd2);
        send_fill_word(pattern(50,0));
        send_fill_word(pattern(50,1));
        send_fill_word(24'habcdef);
        pulse_fill_done(1);
        @(posedge clk); @(negedge clk);
        check_int(fail_count, 2, "case5 overflow fail event");
        check_int(protocol_error, 1, "case5 protocol_error sticky");
        read_expect_line(50, 2, 1);

        // CASE6: full baseline width=640, proves continuous active line.
        $display("CASE6 width=640 continuous output");
        fill_line(60, 640);
        read_expect_line(60, 640, 0);

        // CASE7: back-to-back reuse without reset after earlier failures.
        $display("CASE7 back-to-back bank reuse without reset");
        fill_line(70, 17);
        fill_line(71, 17);
        read_expect_line(70, 17, 0);
        fill_line(72, 17);
        read_expect_line(71, 17, 0);
        read_expect_line(72, 17, 0);

        // CASE8: illegal width > MAX must be rejected immediately.
        $display("CASE8 invalid fill/read width");
        pulse_fill_start(16'd80, 16'd641);
        @(posedge clk); @(negedge clk);
        check_int(fill_active, 0, "case8 invalid fill not active");
        pulse_read_start(16'd80, 16'd641);
        @(posedge clk); @(negedge clk);
        check_int(read_active, 0, "case8 invalid read not active");
        check_int(line_done, 0, "case8 line_done pulse already elapsed by sample");

        if (errors == 0)
            $display("PASS: line_buffer_pingpong all adversarial cases passed (checks=%0d)", checks);
        else
            $display("FAIL: line_buffer_pingpong errors=%0d checks=%0d", errors, checks);
        $finish;
    end
endmodule
