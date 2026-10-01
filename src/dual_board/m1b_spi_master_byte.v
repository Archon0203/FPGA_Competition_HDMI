// ============================================================================
// M1B SPI mode-0 master byte engine.
// M1 freezes this as the future control-plane physical primitive. The current
// board-visible integration intentionally keeps the already board-proven UART
// transport; M2 may replace the transport without changing A/C semantics.
// ============================================================================
module m1b_spi_master_byte #(
    parameter integer HALF_DIV = 25 // 50 MHz -> 1 MHz SCLK
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    input  wire [7:0] tx_data,
    output reg        busy,
    output reg        rx_valid,
    output reg  [7:0] rx_data,
    output reg        spi_cs_n,
    output reg        spi_clk,
    output reg        spi_mosi,
    input  wire       spi_miso
);
    reg [15:0] div_cnt;
    reg [2:0]  bit_index;
    reg [7:0]  tx_shift;
    reg [7:0]  rx_shift;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy      <= 1'b0;
            rx_valid  <= 1'b0;
            rx_data   <= 8'h00;
            spi_cs_n  <= 1'b1;
            spi_clk   <= 1'b0;
            spi_mosi  <= 1'b0;
            div_cnt   <= 16'd0;
            bit_index <= 3'd7;
            tx_shift  <= 8'h00;
            rx_shift  <= 8'h00;
        end else begin
            rx_valid <= 1'b0;
            if (!busy) begin
                spi_clk  <= 1'b0;
                spi_cs_n <= 1'b1;
                div_cnt  <= 16'd0;
                if (start) begin
                    busy      <= 1'b1;
                    spi_cs_n  <= 1'b0;
                    bit_index <= 3'd7;
                    tx_shift  <= tx_data;
                    rx_shift  <= 8'h00;
                    spi_mosi  <= tx_data[7];
                end
            end else if (div_cnt == HALF_DIV-1) begin
                div_cnt <= 16'd0;
                if (!spi_clk) begin
                    // CPOL=0/CPHA=0 rising edge: sample both directions.
                    spi_clk <= 1'b1;
                    rx_shift[bit_index] <= spi_miso;
                end else begin
                    // Falling edge: present the next MOSI bit.
                    spi_clk <= 1'b0;
                    if (bit_index == 3'd0) begin
                        busy     <= 1'b0;
                        spi_cs_n <= 1'b1;
                        rx_data  <= rx_shift;
                        rx_valid <= 1'b1;
                    end else begin
                        bit_index <= bit_index - 1'b1;
                        spi_mosi  <= tx_shift[bit_index-1'b1];
                    end
                end
            end else begin
                div_cnt <= div_cnt + 1'b1;
            end
        end
    end
endmodule
