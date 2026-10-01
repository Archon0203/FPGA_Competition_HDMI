`timescale 1ns/1ps
module tb_dual_board_uart;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    wire master_tx, slave_tx;
    wire [7:0] master_seg, slave_seg;
    wire [7:0] master_sel, slave_sel;
    always #10 clk = ~clk;

    dual_board_master_top #(.UART_CLKS_PER_BIT(4), .COMMAND_INTERVAL_CYCLES(200), .POR_CYCLES(32)) u_master (
        .clk(clk), .rst_n(rst_n), .uart_rx(slave_tx), .uart_tx(master_tx),
        .seg_data(master_seg), .seg_sel(master_sel));
    dual_board_slave_top #(.UART_CLKS_PER_BIT(4), .POR_CYCLES(32)) u_slave (
        .clk(clk), .rst_n(rst_n), .uart_rx(master_tx), .uart_tx(slave_tx),
        .seg_data(slave_seg), .seg_sel(slave_sel));

    initial begin
        #100 rst_n = 1'b1;
        #200000;
        if (u_slave.frame_count < 8'd3) $fatal(1, "slave did not receive frames: %0d", u_slave.frame_count);
        if (u_master.reply_count < 8'd3) $fatal(1, "master did not receive replies: %0d", u_master.reply_count);
        if (u_master.error_count != 0 || u_slave.error_count != 0) $fatal(1, "UART/protocol error");
        $display("PASS: dual-board UART frames=%0d replies=%0d last_cmd=%02h last_reply=%02h",
            u_slave.frame_count, u_master.reply_count, u_slave.last_command, u_master.last_reply);
        $finish;
    end
endmodule
