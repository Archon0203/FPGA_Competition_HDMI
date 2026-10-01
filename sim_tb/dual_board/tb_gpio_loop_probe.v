`timescale 1ns/1ps
module tb_gpio_loop_probe;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    wire tx;
    wire [7:0] seg_data, seg_sel;
    always #10 clk = ~clk;

    dual_board_gpio_loop_probe_top #(
        .HALF_PERIOD_CYCLES(8), .POR_CYCLES(4)
    ) dut (
        .clk(clk), .rst_n(rst_n), .uart_rx(tx), .uart_tx(tx),
        .seg_data(seg_data), .seg_sel(seg_sel)
    );

    initial begin
        #100 rst_n = 1'b1;
        #5000;
        if (dut.rx_edge_count < 8'd5)
            $fatal(1, "GPIO loopback did not detect transitions: %0d", dut.rx_edge_count);
        $display("PASS: GPIO loopback transitions=%0d", dut.rx_edge_count);
        $finish;
    end
endmodule
