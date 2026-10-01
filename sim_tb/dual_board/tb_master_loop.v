`timescale 1ns/1ps
module tb_master_loop;
reg clk=0; reg rst_n=0; wire tx; wire [7:0] sd,ss;
always #10 clk=~clk;
dual_board_master_top #(.UART_CLKS_PER_BIT(4),.COMMAND_INTERVAL_CYCLES(200),.POR_CYCLES(32)) dut(.clk(clk),.rst_n(rst_n),.uart_rx(tx),.uart_tx(tx),.seg_data(sd),.seg_sel(ss));
initial begin #100 rst_n=1; #200000; if(dut.reply_count<3) $fatal(1,"no loopback replies %0d",dut.reply_count); $display("PASS loopback %0d",dut.reply_count); $finish; end
endmodule
