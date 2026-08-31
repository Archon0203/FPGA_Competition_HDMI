`timescale 1ns/1ps

// ================================================================
// Testbench : tb_app_scenario
// IMG_COUNT=4, SLIDE_CLKS=8。验证:
//   自动轮播/暂停/上下一张/回绕/应急切换与提示音。
// 结局: PASS / FAIL
// ================================================================

module tb_app_scenario;
    localparam IMG_COUNT = 4;
    localparam SLIDE_CLKS = 8;

    reg        clk = 1'b0;
    reg        rst_n = 1'b0;
    reg        play_en = 1'b1;
    reg        emergency = 1'b0;
    reg        cmd_next = 1'b0, cmd_prev = 1'b0;
    wire [7:0] index;
    wire       slide_tick, beep_alert;
    wire [1:0] mode;

    app_scenario #(.IMG_COUNT(IMG_COUNT), .SLIDE_CLKS(SLIDE_CLKS)) u_dut (
        .clk(clk), .rst_n(rst_n), .play_en(play_en), .emergency(emergency),
        .cmd_next(cmd_next), .cmd_prev(cmd_prev),
        .index(index), .slide_tick(slide_tick),
        .beep_alert(beep_alert), .mode(mode)
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

    task run_n;
        input integer n;
        begin
            for (k = 0; k < n; k = k + 1) @(posedge clk);
        end
    endtask

    task cmd;
        input is_next;
        begin
            @(negedge clk);
            cmd_next = (is_next == 1);
            cmd_prev = (is_next == 0);
            @(posedge clk);
            cmd_next = 1'b0; cmd_prev = 1'b0;
            #1;
        end
    endtask

    initial begin
        rst_n = 1'b0; #20;
        @(negedge clk);
        rst_n = 1'b1;

        // 复位默认
        check(index, 0, "reset index");
        check(mode, 0, "reset mode"); check(beep_alert, 0, "reset beep");

        // 自动轮播: 一个周期 -> index 1 且 tick 脉冲
        run_n(SLIDE_CLKS); #1;
        check(index, 1, "auto to 1");
        check(slide_tick, 1, "auto tick");
        run_n(1); #1;
        check(slide_tick, 0, "tick cleared");

        // 再一个周期 -> 2
        run_n(SLIDE_CLKS); #1;
        check(index, 2, "auto to 2");

        // 暂停
        play_en = 1'b0;
        run_n(SLIDE_CLKS + 2); #1;
        check(index, 2, "paused keeps index");
        play_en = 1'b1;

        // cmd_next -> 3, 再 next -> 0(回绕)
        cmd(1);
        check(index, 3, "next to 3");
        cmd(1);
        check(index, 0, "wrap to 0");
        // cmd_prev -> 3(反向回绕)
        cmd(0);
        check(index, 3, "prev wrap to 3");

        // 应急
        emergency = 1'b1;
        @(posedge clk); #1;
        check(mode, 1, "emergency mode");
        check(beep_alert, 1, "emergency beep");
        emergency = 1'b0;
        @(posedge clk); #1;
        check(mode, 0, "normal mode back");
        check(beep_alert, 0, "beep off");

        if (errors == 0)
            $display("PASS: app_scenario ok (checks=%0d)", checks);
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
