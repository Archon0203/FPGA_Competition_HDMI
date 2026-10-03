`timescale 1ns/1ps
module tb_m2_gpio7_word_phy;
  reg clk=0, rst_n=0, in_valid=0, in_last=0;
  reg [31:0] in_data=0;
  wire in_ready, link_clk; wire [6:0] link_data;
  wire out_valid, out_last, out_ready; wire [31:0] out_data;
  assign out_ready = 1'b1;
  wire overflow;
  integer n=0, errors=0;
  always #5 clk=~clk;
  m2_gpio7_word_tx tx(.clk(clk),.rst_n(rst_n),.in_valid(in_valid),.in_data(in_data),.in_last(in_last),.in_ready(in_ready),.link_data(link_data),.link_clk(link_clk));
  m2_gpio7_word_rx rx(.link_clk(link_clk),.link_data(link_data),.link_rst_n(rst_n),.sys_clk(clk),.sys_rst_n(rst_n),.out_valid(out_valid),.out_data(out_data),.out_last(out_last),.out_ready(out_ready),.overflow_sticky(overflow));
  initial begin
    repeat(4) @(posedge clk); rst_n=1;
    send(32'h11223344,0); send(32'haabbccdd,0); send(32'hdeadbeef,1);
    repeat(40) @(posedge clk);
    if(n!=3) begin $display("COUNT FAIL %0d",n); errors=errors+1; end
    if(overflow) begin $display("OVERFLOW"); errors=errors+1; end
    if(errors==0) $display("PASS"); else $display("FAIL %0d",errors);
    $finish;
  end
  task send(input [31:0] d,input l); begin
    @(posedge clk); while(!in_ready) @(posedge clk); in_data<=d; in_last<=l; in_valid<=1;
    @(posedge clk); while(!in_ready) @(posedge clk); in_valid<=0;
  end endtask
  always @(posedge clk) if(out_valid && out_ready) begin
    if((n==0 && out_data!==32'h11223344)||(n==1 && out_data!==32'haabbccdd)||(n==2 && out_data!==32'hdeadbeef)) begin $display("DATA FAIL %0d %h",n,out_data); errors=errors+1; end
    if((n==2) != out_last) begin $display("LAST FAIL %0d",n); errors=errors+1; end
    n=n+1;
  end
endmodule
