`timescale 1ns/1ps
module tb_m2_cache_command_router;
    reg clk=0,rst_n=0,cv=0,qr=0,rv=0,rh=0,remote_ready=1;
    reg [1:0] cmd_mode=0;
    reg [7:0] id=0;
    wire cr,qv,rr,ov,local_commit;
    wire [7:0] qid,oid;
    wire [1:0] mode;
    integer opens=0,commits=0;
    always #5 clk=~clk;
    m2_cache_command_router dut(clk,rst_n,cv,id,cmd_mode,cr,qv,qid,qr,
        rv,rh,rr,ov,oid,mode,remote_ready,local_commit);
    always @(posedge clk) begin
        if(ov && remote_ready) opens=opens+1;
        if(local_commit) commits=commits+1;
    end
    task command;
        input [7:0] image;
        input [1:0] mode_value;
        begin
            @(negedge clk); cv=1;id=image;cmd_mode=mode_value;
            wait(cr); @(negedge clk); cv=0;
            wait(qv); if(qid!=image) $fatal(1,"query payload");
            @(negedge clk); qr=1; @(negedge clk); qr=0;
        end
    endtask
    task answer;
        input hit;
        begin
            repeat(50) begin @(negedge clk); if(cr || ov) $fatal(1,"command completed before display commit"); end
            rv=1;rh=hit; @(negedge clk); rv=0;
        end
    endtask
    initial begin
        repeat(3) @(negedge clk);rst_n=1;
        command(8'd3,2'd0); answer(1);
        repeat(3) @(negedge clk);
        if(opens!=0 || commits!=1 || !cr) $fatal(1,"hit must skip UART");
        command(8'd7,2'd0); answer(0);
        wait(ov); if(oid!=7) $fatal(1,"miss payload");
        @(negedge clk); remote_ready=0;
        repeat(50) begin @(negedge clk); if(cr) $fatal(1,"miss gate released before remote DONE"); end
        remote_ready=1;repeat(3) @(negedge clk);
        if(opens!=1 || !cr) $fatal(1,"miss completion");
        command(8'd1,2'd0); answer(1);repeat(3) @(negedge clk);
        if(opens!=1 || commits!=2) $fatal(1,"second cached command");
        command(8'd3,2'd1); answer(1);repeat(3) @(negedge clk);
        if(opens!=1 || commits!=2 || !cr) $fatal(1,"prefetch cache hit must finish without remote open or display commit");
        $display("PASS: cache router display hit, prefetch-hit skip, cache miss UART/DONE serialization");$finish;
    end
    initial begin #20000;$fatal(1,"router watchdog");end
endmodule
