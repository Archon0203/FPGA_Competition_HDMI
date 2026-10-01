// Static GPIO direction probe. Use SW6/KEY1-free image to identify the
// physical header path with a multimeter or a direct jumper.
module dual_board_gpio_static_top (
    input wire clk,
    input wire rst_n,
    input wire uart_rx,
    output wire uart_tx,
    output wire [7:0] seg_data,
    output wire [7:0] seg_sel
);
    reg [7:0] count;
    reg rx_meta, rx_sync;
    reg rx_last;
    reg [22:0] tick;
    reg tx_level;
    assign uart_tx = tx_level;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= 8'h00;
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
            rx_last <= 1'b1;
            tx_level <= 1'b0;
            tick <= 23'd0;
        end else begin
            rx_meta <= uart_rx;
            rx_sync <= rx_meta;
            if (rx_sync != rx_last) begin
                rx_last <= rx_sync;
                count <= count + 1'b1;
            end
            if (tick == 23'd4999999) begin
                tick <= 23'd0;
                tx_level <= ~tx_level;
            end else tick <= tick + 1'b1;
        end
    end
    db_hex_display u_display (.clk(clk), .rst_n(rst_n), .status({7'h00, tx_level}),
        .count(count), .seg_data(seg_data), .seg_sel(seg_sel));
endmodule
