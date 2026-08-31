`timescale 1ns/1ps

// ================================================================
// Testbench : tb_tone_gen
// N=16, freq=0x1000(2^12) -> 方波周期 16 采样(8 负 + 8 正)。
// 三角波只做范围与正负出现检查。
// 结局: PASS / FAIL
// ================================================================

module tb_tone_gen;
    localparam N = 16, DW = 16;
    localparam signed [DW-1:0] AMP = 16'sh7FFF;

    reg        clk = 1'b0;
    reg        rst_n = 1'b0;
    reg        samples_valid = 1'b0;
    reg  [N-1:0] freq = 16'h1000;
    reg  [1:0] wave = 2'd0;
    wire signed [DW-1:0] pcm;

    tone_gen #(.N(N), .DW(DW)) u_dut (
        .clk(clk), .rst_n(rst_n), .samples_valid(samples_valid),
        .freq(freq), .wave(wave), .pcm(pcm)
    );

    always #5 clk = ~clk;

    integer errors = 0;
    integer checks = 0;
    integer k;
    integer spos, sneg, allamp, tripos, trineg, inrange;
    reg signed [DW-1:0] samp [0:31];

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

    task collect;
        input integer n;
        begin
            for (k = 0; k < n; k = k + 1) begin
                @(posedge clk);
                samples_valid = 1'b1;
                @(posedge clk);
                samp[k] = pcm;
            end
            samples_valid = 1'b0;
        end
    endtask

    initial begin
        rst_n = 1'b0; #20; rst_n = 1'b1; #10;

        // 方波: 一个周期内 8 负 + 8 正, 且幅度仅为 +/-AMP
        wave = 2'd0;
        collect(16);
        spos = 0; sneg = 0; allamp = 1;
        for (k = 0; k < 16; k = k + 1) begin
            if (samp[k] == AMP) spos = spos + 1;
            else if (samp[k] == -AMP) sneg = sneg + 1;
            else allamp = 0;
        end
        check(spos, 8, "square 8 positive");
        check(sneg, 8, "square 8 negative");
        check(allamp, 1, "square amplitude only");

        // 三角波: 有正有负且在 [-AMP, AMP] 内
        wave = 2'd1;
        collect(32);
        tripos = 0; trineg = 0; inrange = 1;
        for (k = 0; k < 32; k = k + 1) begin
            if (samp[k] > 0) tripos = tripos + 1;
            if (samp[k] < 0) trineg = trineg + 1;
            if (samp[k] < -AMP || samp[k] > AMP) inrange = 0;
        end
        check((tripos > 0), 1, "triangle has positive");
        check((trineg > 0), 1, "triangle has negative");
        check(inrange, 1, "triangle in range");

        if (errors == 0)
            $display("PASS: tone_gen ok (checks=%0d)", checks);
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
