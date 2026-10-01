`timescale 1ns/1ps
module tb_m1b_spi_byte_loop;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg start = 1'b0;
    reg [7:0] master_tx = 8'hA5;
    wire busy, master_rx_valid;
    wire [7:0] master_rx;
    wire cs_n, sclk, mosi, miso;
    wire slave_rx_valid;
    wire [7:0] slave_rx;
    wire slave_tx_ready;

    always #10 clk = ~clk;

    m1b_spi_master_byte #(.HALF_DIV(2)) u_master (
        .clk(clk), .rst_n(rst_n), .start(start), .tx_data(master_tx),
        .busy(busy), .rx_valid(master_rx_valid), .rx_data(master_rx),
        .spi_cs_n(cs_n), .spi_clk(sclk), .spi_mosi(mosi), .spi_miso(miso));

    m1a_spi_slave u_slave (
        .spi_clk(sclk), .spi_cs_n(cs_n), .spi_mosi(mosi), .spi_miso(miso),
        .tx_data(8'h3C), .tx_ready(slave_tx_ready),
        .rx_valid(slave_rx_valid), .rx_data(slave_rx));

    integer guard = 0;
    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;
        while (!master_rx_valid && guard < 1000) begin
            @(posedge clk);
            guard = guard + 1;
        end
        #1;
        if (!master_rx_valid || master_rx !== 8'h3C || slave_rx !== 8'hA5)
            $display("FAIL: M1B SPI byte loop master_rx=%02x slave_rx=%02x valid=%0d", master_rx, slave_rx, master_rx_valid);
        else
            $display("PASS: M1B SPI mode-0 byte loop master_rx=%02x slave_rx=%02x", master_rx, slave_rx);
        $finish;
    end
endmodule
