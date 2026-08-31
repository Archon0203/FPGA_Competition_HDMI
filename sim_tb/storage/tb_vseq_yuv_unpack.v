`timescale 1ns/1ps

// ================================================================
// Testbench : tb_vseq_yuv_unpack
// 喂入 2 帧 YUV444 字节流，核对每 3 字节解出一个像素，并在
// frame_start 时重新对齐相位。
// 结局: PASS / FAIL
// ================================================================

module tb_vseq_yuv_unpack;
    reg        clk = 1'b0;
    reg        rst_n = 1'b0;
    reg        byte_valid = 1'b0;
    reg  [7:0] byte_data = 8'd0;
    reg        frame_start = 1'b0;
    wire       pix_valid;
    wire [7:0] y, cb, cr;

    vseq_yuv_unpack #(.DW(8)) u_dut (
        .clk(clk), .rst_n(rst_n), .byte_valid(byte_valid), .byte_data(byte_data),
        .frame_start(frame_start), .pix_valid(pix_valid), .y(y), .cb(cb), .cr(cr)
    );

    always #5 clk = ~clk;

    integer errors = 0;
    integer checks = 0;
    integer i;

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

    task feed;
        input [7:0] b;
        input       fs;
        begin
            @(negedge clk);
            byte_valid = 1'b1; byte_data = b; frame_start = fs;
            @(posedge clk);
            byte_valid = 1'b0; frame_start = 1'b0;
        end
    endtask

    initial begin
        rst_n = 1'b0; #20; rst_n = 1'b1; #10;

        // 像素1: Y=10 Cb=20 Cr=30; 像素2: Y=11 Cb=21 Cr=31
        feed(8'd10, 1'b1);
        feed(8'd20, 1'b0);
        feed(8'd30, 1'b0);
        @(negedge clk); #1;
        check(pix_valid, 1, "pix_valid p1");
        check(y, 10, "y p1"); check(cb, 20, "cb p1"); check(cr, 30, "cr p1");

        feed(8'd11, 1'b0);
        feed(8'd21, 1'b0);
        feed(8'd31, 1'b0);
        @(negedge clk); #1;
        check(pix_valid, 1, "pix_valid p2");
        check(y, 11, "y p2"); check(cb, 21, "cb p2"); check(cr, 31, "cr p2");

        // 人为在中途拉 frame_start，验证相位重置
        feed(8'd99, 1'b1);
        feed(8'd88, 1'b0);
        feed(8'd77, 1'b0);
        @(negedge clk); #1;
        check(pix_valid, 1, "pix_valid after realign");
        check(y, 99, "y after realign"); check(cb, 88, "cb after realign"); check(cr, 77, "cr after realign");

        if (errors == 0)
            $display("PASS: vseq_yuv_unpack ok (checks=%0d)", checks);
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
