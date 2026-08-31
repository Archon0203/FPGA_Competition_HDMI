`timescale 1ns/1ps

// ================================================================
// Testbench : tb_color_space
// 使用独立计算出的 BT.601 limited-range golden vectors 精确比对;
// 包含白/黑/灰锚点与越界 clamp 检查，避免 DUT 与 reference 同源同错。
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
        input [7:0] er, eg, eb;
        begin
            pixel_valid = 1'b1; y = iy; cb = icb; cr = icr;
            #1;
            if (!out_valid) begin
                $display("ERROR: out_valid=0"); errors = errors + 1;
            end
            check(r, er, "R");
            check(g, eg, "G");
            check(b, eb, "B");
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
        check3(8'd235, 8'd128, 8'd128, 8'd255, 8'd255, 8'd255);   // 白
        check3(8'd16,  8'd128, 8'd128, 8'd0,   8'd0,   8'd0);     // 黑
        check3(8'd128, 8'd128, 8'd128, 8'd130, 8'd130, 8'd130);   // 灰

        // 彩色/边界/钳位向量（独立 golden）
        check3(8'd76,  8'd84,  8'd255, 8'd255, 8'd0,   8'd0);   // 红
        check3(8'd150, 8'd43,  8'd21,  8'd0,   8'd255, 8'd0);   // 绿
        check3(8'd41,  8'd240, 8'd110, 8'd0,   8'd0,   8'd255); // 蓝
        check3(8'd235, 8'd255, 8'd255, 8'd255, 8'd102, 8'd255); // 高Y高色度
        check3(8'd16,  8'd0,   8'd0,   8'd0,   8'd154, 8'd0);   // 低Y低色度
        check3(8'd200, 8'd0,   8'd255, 8'd255, 8'd161, 8'd0);   // 强偏红

        if (errors == 0)
            $display("PASS: color_space ok (checks=%0d)", checks);
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
