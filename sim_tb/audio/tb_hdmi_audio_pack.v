`timescale 1ns/1ps

// ================================================================
// Testbench : tb_hdmi_audio_pack
// 校验 IEC60958 子帧的采样位置、V/U/C 位、偶校验，以及 1 拍输出延迟。
// 结局: PASS / FAIL
// ================================================================

module tb_hdmi_audio_pack;
    reg        clk = 1'b0;
    reg        rst_n = 1'b0;
    reg        sample_valid = 1'b0;
    reg signed [23:0] sample = 24'sd0;
    reg        v = 1'b0, u = 1'b0, c = 1'b0;
    wire       subframe_valid;
    wire [27:0] subframe;

    hdmi_audio_pack #(.AW(24)) u_dut (
        .clk(clk), .rst_n(rst_n), .sample_valid(sample_valid), .sample(sample),
        .v(v), .u(u), .c(c),
        .subframe_valid(subframe_valid), .subframe(subframe)
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
                $display("ERROR: %s got=%0h exp=%0h", msg, val, exp);
                errors = errors + 1;
            end
        end
    endtask

    task push;
        input signed [23:0] s;
        input iv, iu, ic;
        begin
            @(negedge clk);
            sample = s; v = iv; u = iu; c = ic; sample_valid = 1'b1;
            @(posedge clk);
            sample_valid = 1'b0;
        end
    endtask

    function [27:0] expected_subframe;
        input signed [23:0] s;
        input iv, iu, ic;
        reg p;
        integer i;
        begin
            p = ic ^ iu ^ iv;
            for (i = 0; i < 24; i = i + 1)
                p = p ^ s[i];
            expected_subframe = {p, ic, iu, iv, s};
        end
    endfunction

    initial begin
        rst_n = 1'b0; #20;
        check(subframe_valid, 0, "reset valid");
        check(subframe, 28'h0000000, "reset subframe");
        rst_n = 1'b1; #10;

        // 第一个采样：0x123456, V=0,U=1,C=0
        push(24'h123456, 1'b0, 1'b1, 1'b0);
        #1;
        check(subframe_valid, 1, "valid after sample");
        check(subframe, expected_subframe(24'h123456, 1'b0, 1'b1, 1'b0), "subframe 0x123456");
        check(^subframe, 1'b0, "even parity");

        // 负采样，所有标志位置 1
        push(-24'sd12345, 1'b1, 1'b1, 1'b1);
        #1;
        check(subframe, expected_subframe(-24'sd12345, 1'b1, 1'b1, 1'b1), "subframe negative");
        check(^subframe, 1'b0, "even parity negative");

        // 0 和满幅边界
        push(24'h000000, 1'b0, 1'b0, 1'b0);
        #1;
        check(subframe, expected_subframe(24'h000000, 1'b0, 1'b0, 1'b0), "subframe zero");
        push(24'h7fffff, 1'b0, 1'b0, 1'b0);
        #1;
        check(subframe, expected_subframe(24'h7fffff, 1'b0, 1'b0, 1'b0), "subframe pos full");

        if (errors == 0)
            $display("PASS: hdmi_audio_pack ok (checks=%0d)", checks);
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
