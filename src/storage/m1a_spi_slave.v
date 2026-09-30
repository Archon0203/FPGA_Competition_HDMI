// M1A SPI mode-0 byte slave.
// One chip-select transaction transfers one byte. The byte stream is handed to
// the M1A ingress FIFO; the service shell owns the clock-domain crossing.
module m1a_spi_slave (
    input  wire       spi_clk,
    input  wire       spi_cs_n,
    input  wire       spi_mosi,
    output wire       spi_miso,
    input  wire [7:0] tx_data,
    output wire       tx_ready,
    output wire       rx_valid,
    output wire [7:0] rx_data
);
    reg [7:0] rx_shift;
    reg [7:0] rx_latched;
    reg [2:0] rx_bit_count;
    reg [2:0] tx_bit_count;

    assign tx_ready = spi_cs_n;
    // CPHA=0 presents bit 7 before the first rising edge, then advances on
    // each falling edge. tx_data must remain stable during the byte transfer.
    assign spi_miso = spi_cs_n ? 1'b0 : tx_data[7-tx_bit_count];
    // Combinational final-byte strobe lets a posedge-clocked async FIFO sample
    // the byte on the same eighth SPI rising edge, even if CS rises immediately.
    assign rx_valid = !spi_cs_n && (rx_bit_count == 3'd7);
    // On the final edge expose the completed byte combinationally so the FIFO
    // samples it with rx_valid; afterward retain it for byte-oriented users.
    assign rx_data = rx_valid ? {rx_shift[6:0], spi_mosi} : rx_latched;

    always @(posedge spi_clk or posedge spi_cs_n) begin
        if (spi_cs_n) begin
            rx_shift <= 8'h00;
            rx_bit_count <= 3'd0;
        end else begin
            rx_shift <= {rx_shift[6:0], spi_mosi};
            if (rx_bit_count == 3'd7) begin
                rx_bit_count <= 3'd0;
            end else begin
                rx_bit_count <= rx_bit_count + 1'b1;
            end
        end
    end

    always @(posedge spi_clk) begin
        if (!spi_cs_n && (rx_bit_count == 3'd7))
            rx_latched <= {rx_shift[6:0], spi_mosi};
    end

    // CPHA=0 transmit data changes on falling edges; the first bit is loaded
    // at chip-select assertion, before the first sampling rising edge.
    always @(negedge spi_clk or posedge spi_cs_n) begin
        if (spi_cs_n) begin
            tx_bit_count <= 3'd0;
        end else if (tx_bit_count != 3'd7) tx_bit_count <= tx_bit_count + 1'b1;
    end
endmodule
