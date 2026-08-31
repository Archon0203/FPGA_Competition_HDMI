`timescale 1ns/1ps

// ================================================================
// Testbench : tb_audio_visual
// DW=16, ENV_W=8, BAR_H=256, DECAY=4, BAR_X0=8, BAR_W=16。
// 验证: 包络攻击/释放; 柱内像素命中判定。
// 结局: PASS / FAIL
// ================================================================

module tb_audio_visual;
    reg        clk = 1'b0;
    reg        rst_n = 1'b0;
    reg        sample_valid = 1'b0;
    reg signed [15:0] sample = 16'sd0;
    reg        disp_valid = 1'b0;
    reg  [11:0] px = 12'd0, py = 12'd0;
    wire [7:0]  level;
    wire        vis_on;

    audio_visual #(.DW(16), .ENV_W(8), .BAR_X0(8), .BAR_W(16), .BAR_H(256), .DECAY(4)) u_dut (
        .clk(clk), .rst_n(rst_n), .sample_valid(sample_valid), .sample(sample),
        .disp_valid(disp_valid), .px(px), .py(py),
        .level(level), .vis_on(vis_on)
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
                $display("ERROR: %s got=%0d exp=%0d", msg, val, exp);
                errors = errors + 1;
            end
        end
    endtask

    // 推送一个采样
    task push;
        input signed [15:0] s;
        begin
            @(negedge clk);
            sample = s; sample_valid = 1'b1;
            @(posedge clk);
            sample_valid = 1'b0;
        end
    endtask

    // 检查某像素是否命中
    task check_px;
        input [11:0] ix, iy;
        input        exp;
        begin
            @(negedge clk);
            disp_valid = 1'b1; px = ix; py = iy;
            @(posedge clk); #1;
            check(vis_on, exp, "vis_on pixel");
            disp_valid = 1'b0;
        end
    endtask

    initial begin
        rst_n = 1'b0; #20; rst_n = 1'b1; #10;

        // 100 个静音采样 -> env=0
        for (k = 0; k < 100; k = k + 1) push(16'sd0);
        check(level, 0, "initial env 0");

        // 持续 0x4000(amp=64) -> env=64; bar_h=128, bar_top=128
        for (k = 0; k < 5; k = k + 1) push(16'sh4000);
        check(level, 64, "env after 5 high samples");

        // 柱内/外像素
        check_px(12'd8,  12'd128, 1);    // 柱顶行 -> 命中
        check_px(12'd8,  12'd255, 1);    // 柱底 -> 命中
        check_px(12'd8,  12'd127, 0);    // 柱顶上一行 -> 未命中
        check_px(12'd7,  12'd255, 0);    // x 在柱左 -> 未命中
        check_px(12'd24, 12'd255, 0);    // x 在柱右 -> 未命中

        // 更高峰值 0x7FFF -> env=127; bar_h=254, bar_top=2
        for (k = 0; k < 3; k = k + 1) push(16'sh7FFF);
        check(level, 127, "env peak 127");
        check_px(12'd8, 12'd2, 1);
        check_px(12'd8, 12'd1, 0);

        // 释放: 每静音采样 -4
        for (k = 0; k < 5; k = k + 1) push(16'sd0);
        @(negedge clk); #1;   // 等最后一次释放的 NBA 稳定
        check(level, 127 - 5*4, "env decay");

        // 完全静音 -> env=0 -> 柱无命中
        for (k = 0; k < 40; k = k + 1) push(16'sd0);
        check(level, 0, "env to 0");
        check_px(12'd8, 12'd255, 0);

        if (errors == 0)
            $display("PASS: audio_visual ok (checks=%0d)", checks);
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
