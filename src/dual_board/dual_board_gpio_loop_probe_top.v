// Hardware-only J1 loopback probe. F13 changes state every half second;
// G14 counts each observed transition. It deliberately does not use UART.
module dual_board_gpio_loop_probe_top #(
    parameter integer HALF_PERIOD_CYCLES = 25000000,
    parameter integer POR_CYCLES = 1000000
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       uart_rx,
    output reg        uart_tx,
    output wire [7:0] seg_data,
    output wire [7:0] seg_sel
);
    reg [25:0] tx_tick;
    reg [7:0] tx_toggle_count;
    reg [7:0] rx_edge_count;
    reg rx_meta, rx_sync, rx_last;
    wire core_rst_n;

    // D0: no transition has returned through G14. D1: local loopback works.
    wire [7:0] display_status = (rx_edge_count == 0) ? 8'hd0 : 8'hd1;

    db_startup_reset #(.POR_CYCLES(POR_CYCLES)) u_por (
        .clk(clk), .ext_rst_n(rst_n), .rst_n(core_rst_n));
    db_hex_display u_display (.clk(clk), .rst_n(core_rst_n), .status(display_status),
        .count(rx_edge_count), .seg_data(seg_data), .seg_sel(seg_sel));

    always @(posedge clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            tx_tick <= 26'd0;
            tx_toggle_count <= 8'd0;
            rx_edge_count <= 8'd0;
            uart_tx <= 1'b1;
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
            rx_last <= 1'b1;
        end else begin
            rx_meta <= uart_rx;
            rx_sync <= rx_meta;
            if (rx_sync != rx_last) begin
                rx_last <= rx_sync;
                if (rx_edge_count != 8'hff)
                    rx_edge_count <= rx_edge_count + 1'b1;
            end
            if (tx_tick >= HALF_PERIOD_CYCLES-1) begin
                tx_tick <= 25'd0;
                uart_tx <= ~uart_tx;
                if (tx_toggle_count != 8'hff)
                    tx_toggle_count <= tx_toggle_count + 1'b1;
            end else begin
                tx_tick <= tx_tick + 1'b1;
            end
        end
    end
endmodule
