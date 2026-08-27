`timescale 1ns/1ps

// ================================================================
// Testbench : tb_image_enhance
// 验证 brightness/contrast: out = clamp((in-128)*gain/64 + 128 + bias)
// 用几组手算结果核对, 输出 PASS/FAIL。
// ================================================================

module tb_image_enhance;

    reg  [7:0] r_in, g_in, b_in;
    reg  [7:0] gain;
    reg signed [7:0] bias;
    reg        pixel_valid = 1'b0;
    wire [7:0] r_out, g_out, b_out;
    wire       out_valid;

    image_enhance #(.DW(8)) uut (
        .pixel_valid(pixel_valid),
        .r_in(r_in), .g_in(g_in), .b_in(b_in),
        .gain(gain), .bias(bias),
        .r_out(r_out), .g_out(g_out), .b_out(b_out),
        .out_valid(out_valid)
    );

    integer errors = 0;

    // 一次测试: 设输入 -> #1 -> 检查输出
    task check(
        input [7:0]        ir, ig, ib,
        input [7:0]        ga,
        input signed [7:0] bi,
        input [7:0]        er, eg, eb
    );
    begin
        r_in = ir; g_in = ig; b_in = ib; gain = ga; bias = bi; pixel_valid = 1'b1;
        #1;
        if (!out_valid) begin
            $error("case: out_valid=0");
            errors = errors + 1;
        end
        if (r_out !== er) begin
            $error("case r in=%0d ga=%0d bi=%0d => got %0d expect %0d", ir, ga, bi, r_out, er);
            errors = errors + 1;
        end
        if (g_out !== eg) begin
            $error("case g in=%0d ga=%0d bi=%0d => got %0d expect %0d", ig, ga, bi, g_out, eg);
            errors = errors + 1;
        end
        if (b_out !== eb) begin
            $error("case b in=%0d ga=%0d bi=%0d => got %0d expect %0d", ib, ga, bi, b_out, eb);
            errors = errors + 1;
        end
        pixel_valid = 1'b0;
        #1;
    end
    endtask

    initial begin
        // gain=64(1.0), bias=0 -> 透传
        check(128,128,128, 64, 0, 128,128,128);
        // gain=128(2.0), bias=0 -> clamp(2*in-128)
        check(200,100,50, 128, 0, 255,72,0);
        // gain=64(1.0), bias=32 -> clamp(in+32)
        check(250,200,150, 64, 32, 255,232,182);
        // gain=64(1.0), bias=-64 -> clamp(in-64)
        check(64,32,16, 64, -64, 0,0,0);
        // gain=128(2.0), bias=0, in=0 -> 0
        check(0,0,0, 128, 0, 0,0,0);

        if (errors == 0)
            $display("PASS: image_enhance ok");
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule

