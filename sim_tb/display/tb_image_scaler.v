`timescale 1ns/1ps

// ================================================================
// Testbench : tb_image_scaler
// 用两个实例:
//   u2: 320x240 -> 640x480 (2x 最近邻, sx=px/2, sy=py/2)
//   u3: 100x100 -> 300x300 (3x, sx=floor(px/3))
// 验证最近邻映射与 clamp(越界坐标)。
// 结局: PASS / FAIL
// ================================================================

module tb_image_scaler;
    reg        clk = 1'b0;
    reg        rst_n = 1'b0;
    reg        valid = 1'b0;
    reg  [11:0] px = 12'd0, py = 12'd0;
    wire [11:0] sx2, sy2; wire v2;
    wire [11:0] sx3, sy3; wire v3;

    image_scaler #(.SRC_W(320), .SRC_H(240), .DST_W(640), .DST_H(480)) u2 (
        .clk(clk), .rst_n(rst_n), .valid(valid), .px(px), .py(py),
        .sx(sx2), .sy(sy2), .src_valid(v2)
    );
    image_scaler #(.SRC_W(100), .SRC_H(100), .DST_W(300), .DST_H(300)) u3 (
        .clk(clk), .rst_n(rst_n), .valid(valid), .px(px), .py(py),
        .sx(sx3), .sy(sy3), .src_valid(v3)
    );

    always #5 clk = ~clk;

    integer errors = 0;
    integer checks = 0;

    task check_v;
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

    task feed;
        input [11:0] ipx, ipy;
        begin
            px = ipx; py = ipy; valid = 1'b1;
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        rst_n = 1'b0; #20; rst_n = 1'b1; #10;

        // 2x 放大
        feed(12'd0, 12'd0);
        check_v(sx2, 0, "2x sx0"); check_v(sy2, 0, "2x sy0"); check_v(v2, 1, "2x valid");
        feed(12'd1, 12'd0);
        check_v(sx2, 0, "2x sx1"); check_v(sy2, 0, "2x sy1");
        feed(12'd2, 12'd1);
        check_v(sx2, 1, "2x sx2"); check_v(sy2, 0, "2x sy2");
        feed(12'd639, 12'd479);
        check_v(sx2, 319, "2x sx_end"); check_v(sy2, 239, "2x sy_end");
        // 越界坐标 -> clamp
        feed(12'd640, 12'd480);
        check_v(sx2, 319, "2x sx_clamp"); check_v(sy2, 239, "2x sy_clamp");

        // 3x 放大(非整除取整)
        feed(12'd0, 12'd0);
        check_v(sx3, 0, "3x sx0"); check_v(sy3, 0, "3x sy0");
        feed(12'd149, 12'd200);
        check_v(sx3, 49, "3x sx149"); check_v(sy3, 66, "3x sy200");
        feed(12'd299, 12'd299);
        check_v(sx3, 99, "3x sx299"); check_v(sy3, 99, "3x sy299");

        // valid 拉低后 src_valid 应清零
        valid = 1'b0; px = 12'd0; py = 12'd0;
        @(posedge clk); #1;
        check_v(v2, 0, "2x valid cleared");
        check_v(v3, 0, "3x valid cleared");

        if (errors == 0)
            $display("PASS: image_scaler ok (checks=%0d)", checks);
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
