`timescale 1ns/1ps
module tb_m2_remote_frame_link;
    reg a=0,b=0,rst=0;
    always #20 a=~a;
    always #17 b=~b;
    reg start=0,done=0,err=0,wvalid=0;
    reg [7:0] id=0;
    reg [20:0] addr=0;
    reg [31:0] data=0;
    wire wready,tvalid,tready,txbusy;
    wire [31:0] tdata,rdata;
    wire [6:0] pins;
    wire req,ack,rvalid,rready;
    wire begin_rx,done_rx,error_rx,rxbusy,mvalid;
    wire [7:0] image;
    wire [20:0] maddr;
    wire [31:0] mdata;
    reg mready=0,corrupt=0;
    reg [3:0] phase=0;
    integer commits=0,errors=0,writes=0,checks=0,k;
    m2_remote_frame_tx tx(a,rst,start,id,wvalid,addr,data,wready,done,err,tvalid,tdata,tready,txbusy);
    m2_gpio_mailbox_tx phy_tx(a,rst,tvalid,tdata,tready,pins,req,ack);
    m2_gpio_mailbox_rx phy_rx(b,rst,pins,req,ack,rvalid,rdata,rready);
    // Corrupt one payload bit downstream of the physical receiver.
    wire [31:0] injected=rdata ^ ((corrupt && rdata==32'h00112204) ? 32'd1 : 32'd0);
    m2_remote_frame_rx #(.PIXELS(8)) rx(b,rst,rvalid,injected,rready,
        begin_rx,done_rx,error_rx,image,mvalid,maddr,mdata,mready,rxbusy);
    always @(posedge b) begin
        phase<=phase+1'b1;
        mready<=phase>5;
        if(done_rx) commits=commits+1;
        if(error_rx) errors=errors+1;
        if(mvalid && mready) begin
            writes=writes+1;
            if(maddr>7) $fatal(1,"address out of bounds");
            if(!corrupt && mdata != 32'h00112200+maddr) $fatal(1,"pixel/address mismatch");
            checks=checks+1;
        end
    end
    task frame;
        input [7:0] n;
        begin
            @(negedge a);id=n;start=1;
            @(negedge a);start=0;
            for(k=7;k>=0;k=k-1) begin
                while(!wready) @(negedge a);
                wvalid=1;addr=k;data=32'h00112200+k;
                @(negedge a);wvalid=0;
            end
            done=1;@(negedge a);done=0;
            wait(!txbusy); repeat(100) @(negedge a);
        end
    endtask
    initial begin
        repeat(5) @(negedge a);rst=1;
        frame(2); if(commits!=1 || errors!=0 || image!=2) $fatal(1,"first frame");
        frame(3); if(commits!=2 || errors!=0 || image!=3) $fatal(1,"repeat frame");
        corrupt=1; frame(4); if(commits!=2 || errors==0) $fatal(1,"CRC did not reject");
        corrupt=0; frame(1); if(commits!=3 || image!=1) $fatal(1,"recovery frame");
        $display("PASS: remote frame mailbox, async clocks, backpressure, CRC rejection, recovery writes=%0d checks=%0d",writes,checks);
        $finish;
    end
    initial begin #2000000; $fatal(1,"watchdog"); end
endmodule
