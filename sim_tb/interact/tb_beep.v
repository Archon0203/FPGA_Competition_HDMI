`timescale 1ns/1ps

// ================================================================
// Testbench : tb_beep
// 用 TONE_HALF=2, GATE_CLKS=4, 验证:
//   1) mode0 静音 / 禁用时输出 0
//   2) mode1 连续音: buzzer 跟随 tone 方波
//   3) mode2 断续: gate off 时静音, gate on 时跟随 tone
// 结局: PASS / FAIL
// ================================================================

module tb_beep;
    localparam TONE_HALF = 2;
    localparam GATE_CLKS = 4;

    reg        clk = 1'b0;
    reg        rst_n = 1'b0;
    reg        beep_en = 1'b0;
    reg  [1:0] mode = 2'd0;
    wire       buzzer;

    beep #(.TONE_HALF(TONE_HALF), .GATE_CLKS(GATE_CLKS), .ACTIVE_HIGH(1'b1)) u_dut (
        .clk(clk), .rst_n(rst_n), .beep_en(beep_en), .mode(mode), .buzzer(buzzer)
    );

    always #5 clk = ~clk;

    integer errors = 0;
    integer checks = 0;
    integer k;
    reg phase0;

    task check;
        input [31:0] val;
        input [31:0] exp;
        input [255:0] msg;
        begin
            checks = checks + 1;
            if (val !== exp) begin
                $display("ERROR: %s got=%0b exp=%0b", msg, val, exp);
                errors = errors + 1;
            end
        end
    endtask

    task wait_n;
        input integer n;
        begin
            for (k = 0; k < n; k = k + 1) @(posedge clk);
        end
    endtask

    initial begin
        rst_n = 1'b0; wait_n(3); rst_n = 1'b1; wait_n(2);

        // mode0: 静音(即使使能)
        mode = 2'd0; beep_en = 1'b1;
        @(posedge clk); #1;
        check(buzzer, 0, "mode0 silent");

        // 禁用: 即使 mode1 也不响
        mode = 2'd1; beep_en = 1'b0;
        @(posedge clk); #1;
        check(buzzer, 0, "disabled silent");

        // mode1: 连续音, buzzer 跟随 tone
        beep_en = 1'b1;
        phase0 = u_dut.tone;
        check(buzzer, phase0, "mode1 follows tone");
        // 观察 tone 翻转(TONE_HALF 拍后必翻转)
        wait_n(TONE_HALF + 1);
        check((u_dut.tone != phase0), 1, "mode1 tone toggled");
        check(buzzer, u_dut.tone, "mode1 buzzer==tone");

        // mode2: 断续。gate off 时静音, gate on 时跟随 tone
        mode = 2'd2;
        // 等到达 gate=0 的时刻
        k = 0;
        while (u_dut.gate == 1'b1 && k < 100) begin
            @(posedge clk);
            k = k + 1;
        end
        @(posedge clk); #1;
        check(buzzer, 0, "mode2 gate-off silent");
        // 等 gate=1
        k = 0;
        while (u_dut.gate == 1'b0 && k < 100) begin
            @(posedge clk);
            k = k + 1;
        end
        @(posedge clk); #1;
        check(buzzer, u_dut.tone, "mode2 gate-on follows tone");

        if (errors == 0)
            $display("PASS: beep ok (checks=%0d)", checks);
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
