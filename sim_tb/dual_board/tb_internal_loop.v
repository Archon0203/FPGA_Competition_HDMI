`timescale 1ns/1ps
module tb_internal_loop;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    wire tx;
    wire [7:0] seg_data, seg_sel;
    always #10 clk = ~clk;
    dual_board_internal_loop_top #(
        .UART_CLKS_PER_BIT(4), .COMMAND_INTERVAL_CYCLES(200), .POR_CYCLES(32)
    ) dut (.clk(clk), .rst_n(rst_n), .uart_tx(tx), .seg_data(seg_data), .seg_sel(seg_sel));
    initial begin
        #100 rst_n = 1'b1;
        #200000;
        if (dut.u_master.reply_count < 8'd3)
            $fatal(1, "internal UART loopback failed: replies=%0d", dut.u_master.reply_count);
        if (dut.u_master.error_count != 0)
            $fatal(1, "internal UART loopback errors=%0d", dut.u_master.error_count);
        $display("PASS: internal UART loopback replies=%0d", dut.u_master.reply_count);
        $finish;
    end
endmodule
