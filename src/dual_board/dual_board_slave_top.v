// M1 slave role: accepts the master's control frames and returns an ACK frame
// with bit 7 set. The low nibble on the display shows the last command seen.
module dual_board_slave_top #(
    parameter integer UART_CLKS_PER_BIT = 434,
    parameter integer POR_CYCLES = 1000000
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       uart_rx,
    output wire       uart_tx,
    output wire [7:0] seg_data,
    output wire [7:0] seg_sel
);
    wire rx_valid, rx_framing_error, rx_activity;
    wire [7:0] rx_data;
    wire frame_valid, frame_error;
    wire [7:0] rx_opcode;
    wire tx_ready, tx_start, tx_busy;
    wire [7:0] tx_data;
    wire core_rst_n;
    reg request;
    reg [7:0] response_opcode;
    reg [7:0] last_command;
    reg [7:0] frame_count;
    reg [7:0] error_count;
    reg [7:0] rx_activity_count;
    // E0: idle/no RX start detected, E2: RX activity but no valid frame yet,
    // E1: UART or protocol error, otherwise the last valid command.
    wire [7:0] display_status = (error_count != 0) ? 8'he1 :
                                ((frame_count == 0 && rx_activity_count != 0) ? 8'he2 : last_command);

    db_startup_reset #(.POR_CYCLES(POR_CYCLES)) u_por (
        .clk(clk), .ext_rst_n(rst_n), .rst_n(core_rst_n));

    db_uart_rx #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) u_rx (.clk(clk), .rst_n(core_rst_n), .rx(uart_rx), .valid(rx_valid),
        .data(rx_data), .framing_error(rx_framing_error), .rx_activity(rx_activity));
    db_frame_parser u_parser (.clk(clk), .rst_n(core_rst_n), .byte_valid(rx_valid),
        .byte_data(rx_data), .frame_valid(frame_valid), .opcode(rx_opcode),
        .frame_error(frame_error));
    db_frame_tx u_frame_tx (.clk(clk), .rst_n(core_rst_n), .request(request),
        .opcode(response_opcode), .uart_ready(tx_ready), .uart_start(tx_start),
        .uart_data(tx_data), .busy(tx_busy));
    db_uart_tx #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) u_tx (.clk(clk), .rst_n(core_rst_n), .start(tx_start), .data(tx_data),
        .ready(tx_ready), .tx(uart_tx));
    db_hex_display u_display (.clk(clk), .rst_n(core_rst_n), .status(display_status),
        .count(frame_count), .seg_data(seg_data), .seg_sel(seg_sel));

    always @(posedge clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            request <= 1'b0;
            response_opcode <= 8'h82;
            last_command <= 8'he0;
            frame_count <= 8'h00;
            error_count <= 8'h00;
            rx_activity_count <= 8'h00;
        end else begin
            request <= 1'b0;
            if (rx_activity)
                rx_activity_count <= rx_activity_count + 1'b1;
            if (frame_valid && !tx_busy) begin
                last_command <= rx_opcode;
                frame_count <= frame_count + 1'b1;
                response_opcode <= rx_opcode | 8'h80;
                request <= 1'b1;
            end
            if (frame_error || rx_framing_error)
                error_count <= error_count + 1'b1;
        end
    end
endmodule
