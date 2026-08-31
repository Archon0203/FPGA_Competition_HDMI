`timescale 1ns/1ps

// ================================================================
// Testbench : tb_transition
// 用 DST_W=8, 验证:
//   mode0=直接A; mode1=淡入淡出(端点/中间); mode2=水平擦拭(ax<thresh 为 B)
// 结局: PASS / FAIL
// ================================================================

module tb_transition;
    localparam DST_W = 8;

    reg        clk = 1'b0;
    reg        rst_n = 1'b0;
    reg        valid = 1'b0;
    reg  [1:0] mode = 2'd0;
    reg  [7:0] t = 8'd0;
    reg  [11:0] ax = 12'd0, ay = 12'd0;
    reg  [7:0] a_r, a_g, a_b, b_r, b_g, b_b;
    wire [7:0] out_r, out_g, out_b;
    wire       out_valid;

    transition #(.DST_W(DST_W), .DW(8)) u_dut (
        .clk(clk), .rst_n(rst_n), .valid(valid), .mode(mode), .t(t),
        .ax(ax), .ay(ay),
        .a_r(a_r), .a_g(a_g), .a_b(a_b), .b_r(b_r), .b_g(b_g), .b_b(b_b),
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

    function [7:0] ref_blend;
        input [7:0] a;
        input [7:0] b;
        input [7:0] tt;
        reg [31:0] n;
        begin
            n = ({24'b0, a} * (32'd255 - {24'b0, tt})) +
                ({24'b0, b} * {24'b0, tt});
            ref_blend = n / 255;
        end
    endfunction

    task set_m;
        input [1:0] m;
        input [7:0] tt;
        input [11:0] ipx;
        begin
            mode = m; t = tt; ax = ipx;
            valid = 1'b1; #1;
        end
    endtask

    initial begin
        rst_n = 1'b0; #20; rst_n = 1'b1; #10;

        a_r = 8'd10; a_g = 8'd20; a_b = 8'd30;
        b_r = 8'd200; b_g = 8'd180; b_b = 8'd160;

        // mode0: 直接 A
        set_m(2'd0, 8'd255, 12'd4);
        check(out_r, a_r, "m0 R"); check(out_g, a_g, "m0 G"); check(out_b, a_b, "m0 B");

        // mode1: t=0 精确为 A
        set_m(2'd1, 8'd0, 12'd0);
        check(out_r, a_r, "fade t0 R = A"); check(out_g, a_g, "fade t0 G = A");
        // t=255 接近 B(用参考核对)
        set_m(2'd1, 8'd255, 12'd0);
        check(out_r, ref_blend(a_r,b_r,8'd255), "fade t255 R");
        check(out_r, b_r, "fade t255 R == B (endpoint)");
        // t=128 中间
        set_m(2'd1, 8'd128, 12'd0);
        check(out_r, ref_blend(a_r,b_r,8'd128), "fade t128 R");
        check(out_g, ref_blend(a_g,b_g,8'd128), "fade t128 G");
        check(out_b, ref_blend(a_b,b_b,8'd128), "fade t128 B");

        // mode2: 水平擦拭, DST_W=8
        // t=0 -> B 宽度 0 -> 全 A
        set_m(2'd2, 8'd0, 12'd0);
        check(out_r, a_r, "wipe t0 ax0 = A");
        set_m(2'd2, 8'd0, 12'd7);
        check(out_r, a_r, "wipe t0 ax7 = A");
        // t=128 -> thresh = floor(128*8/255) = 4, ax<4 为 B
        set_m(2'd2, 8'd128, 12'd0);
        check(out_r, b_r, "wipe t128 ax0 = B");
        set_m(2'd2, 8'd128, 12'd3);
        check(out_r, b_r, "wipe t128 ax3 = B");
        set_m(2'd2, 8'd128, 12'd4);
        check(out_r, a_r, "wipe t128 ax4 = A");
        set_m(2'd2, 8'd128, 12'd7);
        check(out_r, a_r, "wipe t128 ax7 = A");
        // t=255 -> 全 B
        set_m(2'd2, 8'd255, 12'd7);
        check(out_r, b_r, "wipe t255 ax7 = B");

        // invalid -> 0
        valid = 1'b0; #1;
        check(out_r, 0, "valid0 out0"); check(out_g, 0, "valid0 out0");

        if (errors == 0)
            $display("PASS: transition ok (checks=%0d)", checks);
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
