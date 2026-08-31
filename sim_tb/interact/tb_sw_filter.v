`timescale 1ns/1ps

// ================================================================
// Testbench : tb_sw_filter
// 验证拨码消抖与电平变化事件:
//   1) 短毛刺不改变 sw_out
//   2) 稳定后 sw_out 跟随, 且 sw_changed 在电平翻转时各脉动一次
// 结局: PASS / FAIL
// ================================================================

module tb_sw_filter;
    localparam CNT_MAX = 5;

    reg        clk = 1'b0;
    reg        rst_n = 1'b0;
    reg  [3:0] sw_in = 4'b1111;
    wire [3:0] sw_out;
    wire [3:0] sw_changed;

    sw_filter #(.CNT_MAX(CNT_MAX), .ACTIVE_LOW(1'b1)) u_dut (
        .clk(clk), .rst_n(rst_n), .sw_in(sw_in),
        .sw_out(sw_out), .sw_changed(sw_changed)
    );

    always #5 clk = ~clk;

    integer errors = 0;
    integer checks = 0;
    integer ch0 = 0;   // sw_changed[0] 计数
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

    task wait_n;
        input integer n;
        begin
            for (k = 0; k < n; k = k + 1) @(posedge clk);
        end
    endtask

    always @(posedge clk) if (sw_changed[0]) ch0 = ch0 + 1;

    initial begin
        rst_n = 1'b0; wait_n(3); rst_n = 1'b1; wait_n(2);

        // 毛刺(短于阈值)不改变
        sw_in[0] = 1'b0; wait_n(2); sw_in[0] = 1'b1; wait_n(2);
        check(sw_out[0], 0, "glitch no change");
        check(ch0, 0, "no change event on glitch");

        // 拨到 ON(0 有效 -> 逻辑1), 持续超过阈值
        sw_in[0] = 1'b0; wait_n(CNT_MAX + 5);
        check(sw_out[0], 1, "turn on");
        check(ch0, 1, "one change event on");

        // 拨回 OFF(1), 产生第二次变化
        sw_in[0] = 1'b1; wait_n(CNT_MAX + 5);
        check(sw_out[0], 0, "turn off");
        check(ch0, 2, "second change event off");

        // 其他通道保持
        check(sw_out[3:1], 3'b000, "other chans off");

        if (errors == 0)
            $display("PASS: sw_filter ok (checks=%0d)", checks);
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
