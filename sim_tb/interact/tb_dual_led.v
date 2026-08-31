`timescale 1ns/1ps

// ================================================================
// Testbench : tb_dual_led
// 用 SLOW_CLKS=4, FAST_CLKS=2, 验证各 mode 的绿/红输出与闪烁相位。
// 结局: PASS / FAIL
// ================================================================

module tb_dual_led;
    localparam SLOW_CLKS = 4;
    localparam FAST_CLKS = 2;

    reg        clk = 1'b0;
    reg        rst_n = 1'b0;
    reg  [2:0] mode = 3'd0;
    wire [3:0] led_g;
    wire [3:0] led_r;

    dual_led #(.SLOW_CLKS(SLOW_CLKS), .FAST_CLKS(FAST_CLKS)) u_dut (
        .clk(clk), .rst_n(rst_n), .mode(mode), .led_g(led_g), .led_r(led_r)
    );

    always #5 clk = ~clk;

    integer errors = 0;
    integer checks = 0;
    integer k;

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

    task wait_n;
        input integer n;
        begin
            for (k = 0; k < n; k = k + 1) @(posedge clk);
        end
    endtask

    initial begin
        rst_n = 1'b0; wait_n(3); rst_n = 1'b1; wait_n(2);

        // mode=0 灭
        mode = 3'd0; wait_n(1);
        check(led_g, 4'h0, "mode0 G off");
        check(led_r, 4'h0, "mode0 R off");

        // mode=1 绿常亮
        mode = 3'd1; wait_n(1);
        check(led_g, 4'hF, "mode1 G on");
        check(led_r, 4'h0, "mode1 R off");

        // mode=2 红常亮
        mode = 3'd2; wait_n(1);
        check(led_g, 4'h0, "mode2 G off");
        check(led_r, 4'hF, "mode2 R on");

        // mode=3 绿慢闪: led_g 跟随 slow_phase(取反映射), 并通过相位翻转验证
        // 先观测 phase 翻转一次(等待 2*SLOW_CLKS 拍), 期间检查映射一致
        mode = 3'd3;
        begin : m3
            integer p0;
            p0 = u_dut.slow_phase;
            wait_n(SLOW_CLKS + 1);
            // 此时应已翻转
            check((u_dut.slow_phase != p0), 1, "mode3 phase toggled");
            check(led_g, {4{u_dut.slow_phase}}, "mode3 G follows phase");
            check(led_r, 4'h0, "mode3 R off");
        end

        // mode=4 红慢闪
        mode = 3'd4;
        begin : m4
            integer p0;
            p0 = u_dut.slow_phase;
            wait_n(SLOW_CLKS + 1);
            check((u_dut.slow_phase != p0), 1, "mode4 phase toggled");
            check(led_r, {4{u_dut.slow_phase}}, "mode4 R follows phase");
            check(led_g, 4'h0, "mode4 G off");
        end

        // mode=5 绿红交替
        mode = 3'd5;
        begin : m5
            integer p0;
            p0 = u_dut.slow_phase;
            wait_n(SLOW_CLKS + 1);
            check((u_dut.slow_phase != p0), 1, "mode5 phase toggled");
            check(led_g, {4{u_dut.slow_phase}}, "mode5 G follows phase");
            check(led_r, {4{~u_dut.slow_phase}}, "mode5 R inverse");
        end

        // mode=6 黄(双亮)
        mode = 3'd6; wait_n(1);
        check(led_g, 4'hF, "mode6 G on");
        check(led_r, 4'hF, "mode6 R on");

        // mode=7 红快闪(FAST_CLKS=2): led_r 跟随 fast_phase
        mode = 3'd7;
        begin : m7
            integer p0;
            p0 = u_dut.fast_phase;
            wait_n(FAST_CLKS + 1);
            check((u_dut.fast_phase != p0), 1, "mode7 fast phase toggled");
            check(led_r, {4{u_dut.fast_phase}}, "mode7 R follows phase");
            check(led_g, 4'h0, "mode7 G off");
        end

        if (errors == 0)
            $display("PASS: dual_led ok (checks=%0d)", checks);
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
