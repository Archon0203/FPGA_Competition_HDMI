`timescale 1ns/1ps

// ================================================================
// Testbench : tb_key_filter
// 验证:
//   1) 短毛刺(< CNT_MAX)不改变 key_out
//   2) 持续按压(>= CNT_MAX)后 key_out=1 且 key_event 只脉动一次
//   3) 释放(>= CNT_MAX)后 key_out=0
//   4) ACTIVE_LOW 归一化正确(key_in=0 => 按下)
// 结局: PASS / FAIL
// ================================================================

module tb_key_filter;
    localparam CNT_MAX = 5;

    reg        clk = 1'b0;
    reg        rst_n = 1'b0;
    reg  [3:0] key_in = 4'b1111;   // 高=释放(低有效)
    wire [3:0] key_out;
    wire [3:0] key_event;

    key_filter #(
        .CNT_MAX(CNT_MAX),
        .ACTIVE_LOW(1'b1)
    ) u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .key_in(key_in),
        .key_out(key_out),
        .key_event(key_event)
    );

    always #5 clk = ~clk;

    integer errors = 0;
    integer checks = 0;
    integer ev0 = 0;      // key_event[0] 计数
    integer ev1 = 0;      // key_event[1] 计数
    integer k;            // 循环暂存

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

    always @(posedge clk) begin
        if (key_event[0]) ev0 = ev0 + 1;
        if (key_event[1]) ev1 = ev1 + 1;
    end

    // 等待 n 拍
    task wait_n;
        input integer n;
        begin
            for (k = 0; k < n; k = k + 1) @(posedge clk);
        end
    endtask

    initial begin
        // 复位
        rst_n = 1'b0;
        wait_n(3);
        rst_n = 1'b1;
        wait_n(2);

        // ---- 通道0: 短毛刺不应触发 ----
        key_in[0] = 1'b0;            // 出现一个"按下"候选
        wait_n(2);                   // 仅 2 拍, 小于 CNT_MAX
        key_in[0] = 1'b1;            // 收回
        wait_n(2);
        key_in[0] = 1'b0;            // 第二次短候选
        wait_n(1);
        key_in[0] = 1'b1;
        wait_n(1);
        check(key_out[0], 0, "glitch does not set key_out[0]");
        check(ev0, 0, "no event on glitch");

        // ---- 通道0: 持续按压(>= CNT_MAX)触发 ----
        key_in[0] = 1'b0;
        wait_n(CNT_MAX + 5);         // 超过阈值 + 2FF 同步
        check(key_out[0], 1, "press sets key_out[0]");
        check(ev0, 1, "one press event");

        // 长按期间不再重复触发
        wait_n(CNT_MAX);
        check(ev0, 1, "no repeat event during hold");

        // ---- 通道0: 释放 ----
        key_in[0] = 1'b1;
        wait_n(CNT_MAX + 5);
        check(key_out[0], 0, "release clears key_out[0]");

        // ---- 通道1: 干净按压/释放 ----
        key_in[1] = 1'b0;
        wait_n(CNT_MAX + 4);
        check(key_out[1], 1, "ch1 pressed");
        check(ev1, 1, "ch1 one event");
        key_in[1] = 1'b1;
        wait_n(CNT_MAX + 4);
        check(key_out[1], 0, "ch1 released");

        // 结语
        if (errors == 0)
            $display("PASS: key_filter ok (checks=%0d)", checks);
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
