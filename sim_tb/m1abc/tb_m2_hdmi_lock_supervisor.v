`timescale 1ns/1ps
module tb_m2_hdmi_lock_supervisor;
    reg clk=0, rst_n=0, pll_lock=0, video_locked=0;
    wire hdmi_rst, video_locked_sync, video_ready, recovery_pulse;
    integer errors=0;
    integer recoveries=0;

    always #10 clk=~clk;

    m2_hdmi_lock_supervisor #(
        .RESET_HOLD_CYCLES(8),
        .LOCK_WAIT_CYCLES(20),
        .UNLOCK_FILTER_CYCLES(5)
    ) dut (
        .clk(clk), .ext_rst_n(rst_n), .pll_lock(pll_lock),
        .video_locked_async(video_locked), .hdmi_rst(hdmi_rst),
        .video_locked_sync(video_locked_sync), .video_ready(video_ready),
        .recovery_pulse(recovery_pulse));

    always @(posedge clk) if(recovery_pulse) recoveries=recoveries+1;

    task check;
        input cond;
        input [8*96-1:0] msg;
        begin
            if(!cond) begin
                $display("FAIL: %0s", msg);
                errors=errors+1;
            end
        end
    endtask

    initial begin
        repeat(3) @(posedge clk);
        rst_n=1;
        repeat(3) @(posedge clk);
        check(hdmi_rst==1, "reset must remain asserted while PLL is unlocked");

        pll_lock=1;
        repeat(8) @(posedge clk);
        #1 check(hdmi_rst==1, "reset must cover the full configured hold interval");
        @(posedge clk);
        #1 check(hdmi_rst==0, "reset must release on the following source-clock edge");

        // Leave video unlocked long enough to force one automatic recovery.
        repeat(22) @(posedge clk);
        #1 check(recoveries>=1, "missing automatic recovery when video lock never arrives");
        check(hdmi_rst==1, "recovery must reassert HDMI reset");

        // Complete the new reset hold, then acquire lock.
        repeat(9) @(posedge clk);
        video_locked=1;
        repeat(5) @(posedge clk);
        #1 check(video_ready==1, "video_ready must assert after synchronized APUG092 lock");

        // A short lock drop must be filtered.
        video_locked=0;
        repeat(3) @(posedge clk);
        video_locked=1;
        repeat(4) @(posedge clk);
        #1 check(video_ready==1, "short video-lock glitch must not restart HDMI");

        // A sustained lock loss must restart the HDMI sequence.
        video_locked=0;
        repeat(9) @(posedge clk);
        #1 check(recoveries>=2, "sustained lock loss must trigger recovery");
        check(hdmi_rst==1, "sustained lock loss must assert HDMI reset");

        if(errors==0)
            $display("PASS: HDMI lock supervisor reset/acquire/recovery behavior");
        else
            $fatal(1,"HDMI lock supervisor errors=%0d",errors);
        $finish;
    end

    initial begin
        #20000;
        $fatal(1,"watchdog");
    end
endmodule
