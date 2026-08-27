`timescale 1ns/1ps

// ================================================================
// Testbench : tb_osd_overlay
// osd_x=10, osd_y=10, 字模1=实心块, 字模2=上半块。
// 验证: 单元内点=>前景色; 单元外/透明=>透传; 使能关=>透传; invalid=>0
// 结局: PASS / FAIL
// ================================================================

module tb_osd_overlay;
    localparam BX = 10, BY = 10;   // osd 位置

    reg        clk = 1'b0;
    reg        rst_n = 1'b0;
    reg        valid = 1'b0;
    reg  [11:0] x = 12'd0, y = 12'd0;
    reg  [7:0] r_in, g_in, b_in;
    reg        osd_en = 1'b0;
    reg  [11:0] osd_x = BX, osd_y = BY;
    reg  [3:0] char_code = 4'd0;
    reg  [7:0] fg_r, fg_g, fg_b;
    wire [7:0] out_r, out_g, out_b;
    wire       out_valid;

    osd_overlay #(.FW(8), .FH(16), .DW(8)) u_dut (
        .clk(clk), .rst_n(rst_n), .valid(valid), .x(x), .y(y),
        .r_in(r_in), .g_in(g_in), .b_in(b_in),
        .osd_en(osd_en), .osd_x(osd_x), .osd_y(osd_y), .char_code(char_code),
        .fg_r(fg_r), .fg_g(fg_g), .fg_b(fg_b),
        .out_r(out_r), .out_g(out_g), .out_b(out_b), .out_valid(out_valid)
    );

    always #5 clk = ~clk;

    integer errors = 0;
    integer checks = 0;

    task check;
        input [31:0] val;
        input [31:0] exp;
        input [255:0] msg;
        begin
            checks = checks + 1;
            if (val !== exp) begin
                $display("ERROR: %s got=%0d exp=%0d", msg, val, exp);
                errors = errors + 1;
            end
        end
    endtask

    // expect_code: 0=透传背景, 1=前景
    task feed;
        input [11:0] ix, iy;
        input        expect_fg;
        begin
            x = ix; y = iy; valid = 1'b1; #1;
            check(out_r, expect_fg ? fg_r : r_in, "R");
            check(out_g, expect_fg ? fg_g : g_in, "G");
            check(out_b, expect_fg ? fg_b : b_in, "B");
        end
    endtask

    initial begin
        rst_n = 1'b0; #20; rst_n = 1'b1; #10;

        r_in = 8'd100; g_in = 8'd100; b_in = 8'd100;
        fg_r = 8'd255; fg_g = 8'd0;   fg_b = 8'd0;
        osd_en = 1'b1;

        // 字模1: 实心块
        char_code = 4'd1;
        feed(12'd10, 12'd10, 1);      // 左上顶点 -> fg
        feed(12'd17, 12'd10, 1);      // 列7 -> fg
        feed(12'd18, 12'd10, 0);      // 列8 越界 -> base
        feed(12'd9,  12'd10, 0);      // x<osd_x -> base
        feed(12'd10, 12'd25, 1);      // 行15 -> fg
        feed(12'd10, 12'd26, 0);      // 行16 越界 -> base

        // 字模2: 上半块 (0..7 行是前景, 8..15 行背景)
        char_code = 4'd2;
        feed(12'd10, 12'd10, 1);      // 行0 -> fg
        feed(12'd10, 12'd17, 1);      // 行7 -> fg
        feed(12'd10, 12'd18, 0);      // 行8 -> base
        feed(12'd10, 12'd25, 0);      // 行15 -> base

        // 使能关闭 -> 全部透传
        osd_en = 1'b0; char_code = 4'd1;
        feed(12'd10, 12'd10, 0);
        feed(12'd17, 12'd25, 0);

        // invalid -> 0
        valid = 1'b0; #1;
        check(out_r, 0, "valid0 out0");

        if (errors == 0)
            $display("PASS: osd_overlay ok (checks=%0d)", checks);
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
