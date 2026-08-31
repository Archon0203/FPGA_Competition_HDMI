`timescale 1ns/1ps

// ================================================================
// Testbench : tb_yuv420_upsample
// 4x4 帧, 色度 2x2。在每块左上像素给出该块 cb/cr。
// 校验: 输出像素 (x,y) 的色度 = 块(x>>1,y>>1), 并核对 1 拍输出延迟。
// 结局: PASS / FAIL
// ================================================================

module tb_yuv420_upsample;
    reg        clk = 1'b0;
    reg        rst_n = 1'b0;
    reg        pix_valid = 1'b0;
    reg        c_valid = 1'b0;
    reg  [7:0] y_in = 8'd0, cb_in = 8'd0, cr_in = 8'd0;
    wire [7:0] y_out, cb_out, cr_out;
    wire       out_valid;
    wire [11:0] out_px, out_py;
    reg [11:0] px_r = 12'd0, py_r = 12'd0;

    yuv420_upsample #(.HW(2), .DW(8)) u_dut (
        .clk(clk), .rst_n(rst_n), .pix_valid(pix_valid), .px(px_r), .py(py_r), .c_valid(c_valid),
        .y_in(y_in), .cb_in(cb_in), .cr_in(cr_in),
        .y_out(y_out), .cb_out(cb_out), .cr_out(cr_out), .out_valid(out_valid),
        .out_px(out_px), .out_py(out_py)
    );

    always #5 clk = ~clk;

    integer errors = 0;
    integer checks = 0;
    integer fidx, px, py;

    // 色度块源: cb = bx*16 + by*4 + 10 (取值区分), cr = bx*2 + by + 30
    task block_cb(input integer bx, by, output reg [7:0] v);
        begin v = bx*16 + by*4 + 10; end
    endtask
    task block_cr(input integer bx, by, output reg [7:0] v);
        begin v = bx*2 + by + 30; end
    endtask

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

    initial begin
        rst_n = 1'b0; #20; rst_n = 1'b1; #10;

        for (fidx = 0; fidx < 16; fidx = fidx + 1) begin
            px = fidx % 4; py = fidx / 4;
            @(negedge clk);
            px_r = px; py_r = py;
            pix_valid = 1'b1;
            y_in = py*4 + px;
            if ((px & 1) == 0 && (py & 1) == 0) begin
                c_valid = 1'b1;
                block_cb(px>>1, py>>1, cb_in);
                block_cr(px>>1, py>>1, cr_in);
            end else begin
                c_valid = 1'b0;
            end
            @(posedge clk); #1;
            if (fidx > 0) begin
                check(out_valid, 1, "out_valid");
                check(out_px, px, "out_px delayed coord");
                check(out_py, py, "out_py delayed coord");
                check(y_out, py*4 + px, "y passthrough");
                // 期望色度 = 块(px>>1, py>>1) (当前像素)
                begin : expblk
                    reg [7:0] e_cb, e_cr;
                    block_cb(px>>1, py>>1, e_cb);
                    block_cr(px>>1, py>>1, e_cr);
                    check(cb_out, e_cb, "cb nearest");
                    check(cr_out, e_cr, "cr nearest");
                end
            end
        end

        if (errors == 0)
            $display("PASS: yuv420_upsample ok (checks=%0d)", checks);
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
