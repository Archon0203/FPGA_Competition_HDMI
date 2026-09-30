`timescale 1ns/1ps
module tb_m1a_provider_cdc;
    reg src_clk=0,dst_clk=0,src_rst_n=0,dst_rst_n=0,src_valid=0,dst_ready=0;
    reg [7:0] src_data=0; wire src_ready,src_overflow,dst_valid; wire [7:0] dst_data;
    integer errors=0,checks=0,i,received=0;
    always #3 src_clk=~src_clk; always #5 dst_clk=~dst_clk;
    m1a_provider_cdc #(.ADDR_WIDTH(2)) dut(.src_clk(src_clk),.src_rst_n(src_rst_n),.src_valid(src_valid),.src_data(src_data),.src_ready(src_ready),.src_overflow(src_overflow),.dst_clk(dst_clk),.dst_rst_n(dst_rst_n),.dst_valid(dst_valid),.dst_data(dst_data),.dst_ready(dst_ready));
    always @(posedge dst_clk) begin
        if(dst_rst_n && dst_valid && dst_ready) begin
            checks=checks+1;
            if(dst_data !== received[7:0]) begin $display("ERROR CDC byte index=%0d got=%h",received,dst_data); errors=errors+1; end
            received=received+1;
        end
    end
    task send_byte; input [7:0] value; begin
        @(negedge src_clk); src_data=value; src_valid=1;
        // Keep valid and payload unchanged until a sampled ready handshake.
        begin : wait_accept
            reg accepted;
            accepted=0;
            while(!accepted) begin
                @(posedge src_clk);
                if(src_ready) accepted=1;
            end
        end
        @(negedge src_clk); src_valid=0;
    end endtask
    initial begin
        #20; src_rst_n=1; dst_rst_n=1; dst_ready=1;
        for(i=0;i<6;i=i+1) send_byte(i[7:0]);
        repeat(20) @(posedge dst_clk);
        checks=checks+1; if(src_overflow) begin $display("ERROR unexpected overflow"); errors=errors+1; end
        checks=checks+1; if(received!=6) begin $display("ERROR CDC count=%0d expected=6",received); errors=errors+1; end
        if(errors==0) $display("PASS: m1a_provider_cdc checks=%0d",checks); else $display("FAIL: %0d errors",errors);
        $finish;
    end
endmodule
