`timescale 1ns/1ps

// ================================================================
// Testbench : tb_bmp_pixel_stream
// P0-02 adversarial verification.
//
// 联合例化 bmp_parser + bmp_pixel_stream，共享同一 BMP byte stream，验证：
//   - header_done 与首 pixel byte 紧邻时不丢首字节
//   - BGR888 -> RGB888
//   - bottom-up y 映射
//   - row padding = 0/1/2/3
//   - width=17 / width=641
//   - 非 54-byte data_offset
//   - 随机 din_valid stall
//   - bad BMP / top-down / zero width
//   - premature file_done / upstream error
// ================================================================

module tb_bmp_pixel_stream;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg start = 1'b0;

    reg [7:0] din = 8'd0;
    reg din_valid = 1'b0;
    reg file_done = 1'b0;
    reg file_ok = 1'b0;

    wire parser_done;
    wire bmp_ok;
    wire [15:0] width;
    wire [15:0] height;
    wire [5:0] bpp;
    wire [23:0] data_offset;

    wire pixel_valid;
    wire [7:0] pixel_r, pixel_g, pixel_b;
    wire [15:0] pixel_x, pixel_y;
    wire done, ok;

    bmp_parser u_parser (
        .clk(clk), .rst_n(rst_n), .start(start),
        .din(din), .din_valid(din_valid),
        .done(parser_done), .bmp_ok(bmp_ok),
        .width(width), .height(height), .bpp(bpp),
        .data_offset(data_offset)
    );

    bmp_pixel_stream u_dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .din(din), .din_valid(din_valid),
        .header_done(parser_done), .bmp_ok(bmp_ok),
        .width(width), .height(height),
        .file_done(file_done), .file_ok(file_ok),
        .pixel_valid(pixel_valid),
        .pixel_r(pixel_r), .pixel_g(pixel_g), .pixel_b(pixel_b),
        .pixel_x(pixel_x), .pixel_y(pixel_y),
        .done(done), .ok(ok)
    );

    always #5 clk = ~clk;

    localparam integer MAX_FILE = 20000;
    reg [7:0] file_mem [0:MAX_FILE-1];
    integer file_len;
    integer errors = 0;
    integer checks = 0;
    integer pixel_count = 0;
    integer case_width = 0;
    integer case_height = 0;
    integer case_compare_pixels = 0;
    integer i;

    function [7:0] pat_r;
        input integer x;
        input integer y;
        integer v;
        begin
            v = 8'h20 + ((x * 3 + y) & 8'h7F);
            pat_r = v[7:0];
        end
    endfunction

    function [7:0] pat_g;
        input integer x;
        input integer y;
        integer v;
        begin
            v = 8'h40 + ((x + y * 5) & 8'h7F);
            pat_g = v[7:0];
        end
    endfunction

    function [7:0] pat_b;
        input integer x;
        input integer y;
        integer v;
        begin
            v = 8'h60 + ((x * 7 + y * 2) & 8'h7F);
            pat_b = v[7:0];
        end
    endfunction

    task check_int;
        input integer got;
        input integer exp;
        input [8*80-1:0] msg;
        begin
            checks = checks + 1;
            if (got !== exp) begin
                $display("ERROR: %s got=%0d exp=%0d", msg, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    task check_byte;
        input [7:0] got;
        input [7:0] exp;
        input [8*80-1:0] msg;
        begin
            checks = checks + 1;
            if (got !== exp) begin
                $display("ERROR: %s got=%02x exp=%02x", msg, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    // Build a 24-bit BI_RGB BMP into file_mem.
    // height_mag is the positive magnitude. If top_down!=0, the header height
    // is written as negative and the DUT is expected to reject it by baseline.
    task build_bmp;
        input integer w;
        input integer height_mag;
        input integer data_off;
        input integer bad_magic;
        input integer top_down;
        input integer trailing_bytes;
        integer idx;
        integer row;
        integer x;
        integer y_disp;
        integer row_bytes;
        integer pad;
        integer fsize;
        integer henc;
        begin
            for (idx = 0; idx < MAX_FILE; idx = idx + 1)
                file_mem[idx] = 8'h00;

            row_bytes = w * 3;
            pad = (4 - (row_bytes & 3)) & 3;
            fsize = data_off + (row_bytes + pad) * height_mag + trailing_bytes;
            henc = top_down ? -height_mag : height_mag;

            file_mem[0] = bad_magic ? 8'h58 : 8'h42;
            file_mem[1] = bad_magic ? 8'h59 : 8'h4D;
            file_mem[2] = fsize[7:0];
            file_mem[3] = (fsize >> 8) & 8'hFF;
            file_mem[4] = (fsize >> 16) & 8'hFF;
            file_mem[5] = (fsize >> 24) & 8'hFF;
            file_mem[6] = 8'h00; file_mem[7] = 8'h00;
            file_mem[8] = 8'h00; file_mem[9] = 8'h00;
            file_mem[10] = data_off[7:0];
            file_mem[11] = (data_off >> 8) & 8'hFF;
            file_mem[12] = (data_off >> 16) & 8'hFF;
            file_mem[13] = (data_off >> 24) & 8'hFF;
            file_mem[14] = 8'h28; file_mem[15] = 8'h00;
            file_mem[16] = 8'h00; file_mem[17] = 8'h00;
            file_mem[18] = w[7:0];
            file_mem[19] = (w >> 8) & 8'hFF;
            file_mem[20] = (w >> 16) & 8'hFF;
            file_mem[21] = (w >> 24) & 8'hFF;
            file_mem[22] = henc[7:0];
            file_mem[23] = (henc >> 8) & 8'hFF;
            file_mem[24] = (henc >> 16) & 8'hFF;
            file_mem[25] = (henc >> 24) & 8'hFF;
            file_mem[26] = 8'h01; file_mem[27] = 8'h00;
            file_mem[28] = 8'h18; file_mem[29] = 8'h00;
            file_mem[30] = 8'h00; file_mem[31] = 8'h00;
            file_mem[32] = 8'h00; file_mem[33] = 8'h00;

            // Any bytes between BITMAPINFOHEADER end and data_offset are not pixels.
            for (idx = 34; idx < data_off; idx = idx + 1)
                file_mem[idx] = 8'hEE;

            idx = data_off;
            for (row = 0; row < height_mag; row = row + 1) begin
                y_disp = top_down ? row : (height_mag - 1 - row);
                for (x = 0; x < w; x = x + 1) begin
                    file_mem[idx] = pat_b(x, y_disp); idx = idx + 1;
                    file_mem[idx] = pat_g(x, y_disp); idx = idx + 1;
                    file_mem[idx] = pat_r(x, y_disp); idx = idx + 1;
                end
                // Distinct padding bytes: if DUT accidentally emits them as pixels,
                // coordinate/count/RGB checks fail immediately.
                if (pad > 0) begin file_mem[idx] = 8'hA5; idx = idx + 1; end
                if (pad > 1) begin file_mem[idx] = 8'h5A; idx = idx + 1; end
                if (pad > 2) begin file_mem[idx] = 8'hC3; idx = idx + 1; end
            end

            for (row = 0; row < trailing_bytes; row = row + 1) begin
                file_mem[idx] = 8'hD0 + row[3:0];
                idx = idx + 1;
            end
            file_len = idx;
        end
    endtask

    task pulse_start;
        begin
            @(negedge clk);
            din_valid = 1'b0;
            file_done = 1'b0;
            file_ok = 1'b0;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
        end
    endtask

    // Feed n bytes from file_mem. With random_stall=0 all bytes are consecutive,
    // intentionally exercising header_done + first pixel byte on the same edge.
    task feed_bytes;
        input integer n;
        input integer random_stall;
        integer sent;
        integer rv;
        begin
            sent = 0;
            while (sent < n) begin
                @(negedge clk);
                rv = $random;
                if (random_stall && ((rv & 32'h3) == 0)) begin
                    din_valid = 1'b0;
                end else begin
                    din = file_mem[sent];
                    din_valid = 1'b1;
                    sent = sent + 1;
                end
            end
            @(negedge clk);
            din_valid = 1'b0;
        end
    endtask

    task pulse_file_done;
        input integer success;
        begin
            @(negedge clk);
            file_ok = success ? 1'b1 : 1'b0;
            file_done = 1'b1;
            @(negedge clk);
            file_done = 1'b0;
            file_ok = 1'b0;
        end
    endtask

    task wait_done;
        input integer max_cycles;
        integer n;
        begin
            n = 0;
            while (!done && n < max_cycles) begin
                @(posedge clk); #1;
                n = n + 1;
            end
            if (!done) begin
                $display("ERROR: timeout waiting DUT done");
                errors = errors + 1;
            end
        end
    endtask

    task begin_expected_case;
        input integer w;
        input integer h;
        input integer compare_pixels;
        begin
            case_width = w;
            case_height = h;
            case_compare_pixels = compare_pixels;
            pixel_count = 0;
        end
    endtask

    // Pixel monitor. Expected stream order is BMP file order (bottom row first),
    // but coordinates must already be display coordinates via pixel_y.
    always @(posedge clk) begin : MONITOR
        integer exp_x;
        integer exp_y;
        #1;
        if (pixel_valid) begin
            if (!case_compare_pixels) begin
                $display("ERROR: unexpected pixel output x=%0d y=%0d", pixel_x, pixel_y);
                errors = errors + 1;
            end else if (case_width > 0) begin
                exp_x = pixel_count % case_width;
                exp_y = case_height - 1 - (pixel_count / case_width);
                check_int(pixel_x, exp_x, "pixel_x");
                check_int(pixel_y, exp_y, "pixel_y bottom-up mapping");
                check_byte(pixel_r, pat_r(exp_x, exp_y), "pixel_r");
                check_byte(pixel_g, pat_g(exp_x, exp_y), "pixel_g");
                check_byte(pixel_b, pat_b(exp_x, exp_y), "pixel_b");
                pixel_count = pixel_count + 1;
            end
        end
    end

    initial begin
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;

        // ------------------------------------------------------------
        // CASE0: 2x2, padding=2, no stalls.
        // Also guarantees header byte53 is followed immediately by first B byte.
        // ------------------------------------------------------------
        $display("CASE0 2x2 pad=2 consecutive stream / first-pixel boundary");
        build_bmp(2, 2, 54, 0, 0, 0);
        begin_expected_case(2, 2, 1);
        pulse_start;
        feed_bytes(file_len, 0);
        pulse_file_done(1);
        wait_done(100);
        check_int(ok, 1, "case0 ok");
        check_int(pixel_count, 4, "case0 pixel count");

        // CASE1: padding=0.
        $display("CASE1 width=4 pad=0 random stalls");
        build_bmp(4, 3, 54, 0, 0, 0);
        begin_expected_case(4, 3, 1);
        pulse_start; feed_bytes(file_len, 1); pulse_file_done(1); wait_done(100);
        check_int(ok, 1, "case1 ok");
        check_int(pixel_count, 12, "case1 pixel count");

        // CASE2: padding=1.
        $display("CASE2 width=1 pad=1 random stalls");
        build_bmp(1, 3, 54, 0, 0, 0);
        begin_expected_case(1, 3, 1);
        pulse_start; feed_bytes(file_len, 1); pulse_file_done(1); wait_done(100);
        check_int(ok, 1, "case2 ok");
        check_int(pixel_count, 3, "case2 pixel count");

        // CASE3: padding=2.
        $display("CASE3 width=2 pad=2 random stalls");
        build_bmp(2, 3, 54, 0, 0, 0);
        begin_expected_case(2, 3, 1);
        pulse_start; feed_bytes(file_len, 1); pulse_file_done(1); wait_done(100);
        check_int(ok, 1, "case3 ok");
        check_int(pixel_count, 6, "case3 pixel count");

        // CASE4: padding=3.
        $display("CASE4 width=3 pad=3 random stalls");
        build_bmp(3, 2, 54, 0, 0, 0);
        begin_expected_case(3, 2, 1);
        pulse_start; feed_bytes(file_len, 1); pulse_file_done(1); wait_done(100);
        check_int(ok, 1, "case4 ok");
        check_int(pixel_count, 6, "case4 pixel count");

        // Architecture-required non-trivial width.
        $display("CASE5 width=17 random stalls");
        build_bmp(17, 4, 54, 0, 0, 0);
        begin_expected_case(17, 4, 1);
        pulse_start; feed_bytes(file_len, 1); pulse_file_done(1); wait_done(100);
        check_int(ok, 1, "case5 ok");
        check_int(pixel_count, 68, "case5 pixel count");

        // Frozen baseline width: 640 has no row padding for RGB888.
        $display("CASE6 width=640 pad=0 random stalls");
        build_bmp(640, 2, 54, 0, 0, 0);
        begin_expected_case(640, 2, 1);
        pulse_start; feed_bytes(file_len, 1); pulse_file_done(1); wait_done(100);
        check_int(ok, 1, "case6 ok");
        check_int(pixel_count, 1280, "case6 pixel count");

        // Width 641 catches row-size assumptions that only work for 640.
        $display("CASE7 width=641 pad=1 random stalls");
        build_bmp(641, 2, 54, 0, 0, 0);
        begin_expected_case(641, 2, 1);
        pulse_start; feed_bytes(file_len, 1); pulse_file_done(1); wait_done(100);
        check_int(ok, 1, "case7 ok");
        check_int(pixel_count, 1282, "case7 pixel count");

        // data_offset need not be 54. Gap bytes must never become pixels.
        $display("CASE8 data_offset=70 gap bytes ignored");
        build_bmp(5, 2, 70, 0, 0, 4);
        begin_expected_case(5, 2, 1);
        pulse_start; feed_bytes(file_len, 1); pulse_file_done(1); wait_done(100);
        check_int(ok, 1, "case8 ok");
        check_int(pixel_count, 10, "case8 pixel count");

        // Invalid header: parser_done still occurs from data_offset, but bmp_ok=0.
        $display("CASE9 bad magic rejected");
        build_bmp(2, 2, 54, 1, 0, 0);
        begin_expected_case(2, 2, 0);
        pulse_start; feed_bytes(file_len, 0); pulse_file_done(1); wait_done(100);
        check_int(ok, 0, "case9 must fail");
        check_int(pixel_count, 0, "case9 no pixels");

        // Baseline explicitly supports bottom-up only; reject negative height.
        $display("CASE10 top-down negative height rejected");
        build_bmp(2, 2, 54, 0, 1, 0);
        begin_expected_case(2, 2, 0);
        pulse_start; feed_bytes(file_len, 0); pulse_file_done(1); wait_done(100);
        check_int(ok, 0, "case10 must fail");
        check_int(pixel_count, 0, "case10 no pixels");

        $display("CASE11 zero width rejected");
        build_bmp(0, 2, 54, 0, 0, 0);
        begin_expected_case(0, 2, 0);
        pulse_start; feed_bytes(file_len, 0); pulse_file_done(1); wait_done(100);
        check_int(ok, 0, "case11 must fail");
        check_int(pixel_count, 0, "case11 no pixels");

        // Truncate after header + 5 pixel bytes: exactly one whole pixel was emitted,
        // then upstream ends before the 2x2 array is complete.
        $display("CASE12 premature file_done after partial pixel data");
        build_bmp(2, 2, 54, 0, 0, 0);
        begin_expected_case(2, 2, 1);
        pulse_start; feed_bytes(54 + 5, 0); pulse_file_done(1); wait_done(100);
        check_int(ok, 0, "case12 must fail");
        check_int(pixel_count, 1, "case12 one complete pixel before truncation");

        // Upstream read error after one pixel must also terminate as failure.
        $display("CASE13 upstream file_ok=0");
        build_bmp(2, 2, 54, 0, 0, 0);
        begin_expected_case(2, 2, 1);
        pulse_start; feed_bytes(54 + 3, 0); pulse_file_done(0); wait_done(100);
        check_int(ok, 0, "case13 must fail");
        check_int(pixel_count, 1, "case13 one pixel before upstream error");

        if (errors == 0)
            $display("PASS: bmp_pixel_stream all adversarial cases passed (checks=%0d)", checks);
        else
            $display("FAIL: bmp_pixel_stream errors=%0d checks=%0d", errors, checks);
        $finish;
    end

endmodule
