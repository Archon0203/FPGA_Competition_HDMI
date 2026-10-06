`timescale 1ns/1ps
module tb_m2_cache_command_cdc;
    reg ctrl_clk=0, media_clk=0, rst_n=0;
    always #7 ctrl_clk=~ctrl_clk;
    always #19 media_clk=~media_clk;
    reg qv=0, rr=0, qr=0, rv=0, rh=0;
    reg [7:0] qi=0;
    wire qready, rvalid, rhit, mqv, mrready;
    wire [7:0] mqi;
    integer sent=0, received=0, answered=0, replies=0, tick=0;
    m2_cache_command_cdc dut(ctrl_clk,media_clk,rst_n,qv,qi,qready,
        rvalid,rhit,rr,mqv,mqi,qr,rv,rh,mrready);
    always @(negedge ctrl_clk) if(rst_n) begin
        tick=tick+1;
        qv=(sent<32) && (tick%3!=0);
        qi=sent;
        rr=(tick%4!=0);
    end
    always @(posedge ctrl_clk) if(rst_n) begin
        if(qv && qready) sent=sent+1;
        if(rvalid && rr) begin
            if(rhit!==replies[0]) $fatal(1,"reply duplicated or reordered %0d",replies);
            replies=replies+1;
        end
    end
    always @(negedge media_clk) if(rst_n) begin
        qr=!rv && (received%3!=1 || tick%2==0);
    end
    always @(posedge media_clk) if(rst_n) begin
        if(rv && mrready) begin rv<=0; answered=answered+1; end
        if(mqv && qr) begin
            if(mqi!==received[7:0]) $fatal(1,"query duplicated or reordered %0d got %0d",received,mqi);
            rh<=received[0]; rv<=1; received=received+1;
        end
    end
    initial begin
        repeat(5) @(negedge ctrl_clk); rst_n=1;
        wait(replies==32);
        repeat(20) @(negedge ctrl_clk);
        if(received!=32 || answered!=32 || rvalid || mqv) $fatal(1,"CDC counts");
        $display("PASS: cache CDC asynchronous clocks, backpressure, no duplicate commands/replies");
        $finish;
    end
    initial begin #100000; $fatal(1,"cache CDC watchdog"); end
endmodule
