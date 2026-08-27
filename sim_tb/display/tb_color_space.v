`timescale 1ns/1ps

// ================================================================
// Testbench : tb_color_space
// 用与 RTL 相同的 BT.601 定点公式作参考, 对一组向量精确比对;
// 另含白/黑/灰独立锚点与越界 clamp 检查。
// 结局: PASS / FAIL
// ================================================================

module tb_color_space;
    reg        clk = 1'b0;
    reg        rst_n = 1'b0;
    reg  [7:0] y = 8'd0, cb = 8'd128, cr = 8'd128;
    reg        pixel_valid = 1'b0;
    wire [7:0] r, g, b;
    wire       out_valid;

    color_space u_dut (
        .y(y), .cb(cb), .cr(cr), .pixel_valid(pixel_valid),
        .r(r), .g(g), .b(b), .out_valid(out_valid)
    );

    always #5 clk = ~clk;

    integer errors = 0;
    integer checks = 0;

    function [7:0] ref_r;
        input [7:0] iy, icb, icr;
        reg signed [31:0] off, s;
        begin
            off = (($signed({2'b00,icr}) - 10'sd128) * 16'sd359);
            s   = $signed({1'b0,iy}) + (off >>> 8);
            ref_r = (s < 0) ? 8'd0 : ((s > 255) ? 8'd255 : s[7:0]);
        end
    endfunction
    function [7:0] ref_g;
        input [7:0] iy, icb, icr;
        reg signed [31:0] off, s;
        begin
            off = (($signed({2'b00,icb}) - 10'sd128) * 16'sd88)
                + (($signed({2'b00,icr}) - 10'sd128) * 16'sd183);
            s   = $signed({1'b0,iy}) - (off >>> 8);
            ref_g = (s < 0) ? 8'd0 : ((s > 255) ? 8'd255 : s[7:0]);
        end
    endfunction
    function [7:0] ref_b;
        input [7:0] iy, icb, icr;
        reg signed [31:0] off, s;
        begin
            off = (($signed({2'b00,icb}) - 10'sd128) * 16'sd454);
            s   = $signed({1'b0,iy}) + (off >>> 8);
            ref_b = (s < 0) ? 8'd0 : ((s > 255) ? 8'd255 : s[7:0]);
        end
    endfunction

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

    // 对一组 (y,cb,cr) 同时核对 r/g/b
    task check3;
        input [7:0] iy, icb, icr;
        begin
            pixel_valid = 1'b1; y = iy; cb = icb; cr = icr;
            #1;
            if (!out_valid) begin
                $display("ERROR: out_valid=0"); errors = errors + 1;
            end
            check(r, ref_r(iy,icb,icr), "R");
            check(g, ref_g(iy,icb,icr), "G");
            check(b, ref_b(iy,icb,icr), "B");
            pixel_valid = 1'b0;
            #1;
            // valid=0 时输出应为 0
            if (r !== 0 || g !== 0 || b !== 0) begin
                $display("ERROR: output not zero when invalid"); errors = errors + 1;
            end
        end
    endtask

    initial begin
        rst_n = 1'b0; #20; rst_n = 1'b1; #10;

        // 独立锚点: 白/黑/灰
        check3(8'd235, 8'd128, 8'd128);   // 白
        check3(8'd16,  8'd128, 8'd128);   // 黑
        check3(8'd128, 8'd128, 8'd128);   // 灰

        // 彩色/边界/钳位向量(参考公式给出精确期望)
        check3(8'd76,  8'd84,  8'd255);   // 红
        check3(8'd150, 8'd43,  8'd21);    // 绿
        check3(8'd41,  8'd240, 8'd110);   // 蓝
        check3(8'd235, 8'd255, 8'd255);   // 高Y高色度 -> 接近白但被钳位
        check3(8'd16,  8'd0,   8'd0);     // 低Y低色度 -> 接近黑
        check3(8'd200, 8'd0,   8'd255);   // 强偏红

        if (errors == 0)
            $display("PASS: color_space ok (checks=%0d)", checks);
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
