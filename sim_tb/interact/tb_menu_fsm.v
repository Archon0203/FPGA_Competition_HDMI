`timescale 1ns/1ps

// ================================================================
// Testbench : tb_menu_fsm
// 验证复位默认、KEY0/3 翻转、KEY1/2 单拍命令、SW 档位映射。
// 结局: PASS / FAIL
// ================================================================

module tb_menu_fsm;
    reg        clk = 1'b0;
    reg        rst_n = 1'b0;
    reg  [3:0] key_event = 4'b0000;
    reg  [3:0] sw = 4'b0000;
    wire       play_en, cmd_next, cmd_prev, emergency, osd_en;
    wire [1:0] transition_mode;
    wire [7:0] contrast, bias;

    menu_fsm u_dut (
        .clk(clk), .rst_n(rst_n), .key_event(key_event), .sw(sw),
        .play_en(play_en), .cmd_next(cmd_next), .cmd_prev(cmd_prev),
        .emergency(emergency), .transition_mode(transition_mode),
        .contrast(contrast), .bias(bias), .osd_en(osd_en)
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
                $display("ERROR: %s got=%0d exp=%0d", msg, val, exp);
                errors = errors + 1;
            end
        end
    endtask

    // 产生一个单拍按键事件并采样
    task pulse_key;
        input [3:0] ev;
        begin
            @(negedge clk);
            key_event = ev;
            @(posedge clk);
            #1;                     // 采样(事件已被消费, 命令为单拍)
            if (ev[1]) check(cmd_next, 1, "KEY1 next pulse");
            if (ev[2]) check(cmd_prev, 1, "KEY2 prev pulse");
            key_event = 4'b0000;
            @(negedge clk);
        end
    endtask

    // 设置拨码并采样
    task set_sw;
        input [3:0] s;
        begin
            @(negedge clk);
            sw = s;
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        rst_n = 1'b0; #20; rst_n = 1'b1; #10;

        // 复位默认
        check(play_en, 1, "reset play");
        check(emergency, 0, "reset emergency");
        check(transition_mode, 0, "reset trans");
        check(contrast, 64, "reset contrast");
        check(bias, 0, "reset bias");
        check(osd_en, 1, "reset osd");
        check(cmd_next, 0, "reset next");

        // KEY0 暂停
        pulse_key(4'b0001);
        @(negedge clk); #1;
        check(play_en, 0, "paused");
        // 再按恢复
        pulse_key(4'b0001);
        @(negedge clk); #1;
        check(play_en, 1, "resumed");

        // KEY1 / KEY2
        pulse_key(4'b0010);
        pulse_key(4'b0100);
        @(negedge clk); #1;

        // KEY3 应急
        pulse_key(4'b1000);
        @(negedge clk); #1;
        check(emergency, 1, "emergency on");

        // 拨码: trans=2, bias=32, contrast=128
        set_sw(4'b1110);
        check(transition_mode, 2, "sw trans");
        check(bias, 32, "sw bias");
        check(contrast, 128, "sw contrast");

        if (errors == 0)
            $display("PASS: menu_fsm ok (checks=%0d)", checks);
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
