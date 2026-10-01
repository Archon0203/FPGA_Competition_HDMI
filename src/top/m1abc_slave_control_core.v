// Simulation/reuse wrapper for the M1 slave control path (no HDMI vendor IP).
module m1abc_slave_control_core #(
    parameter integer UART_CLKS_PER_BIT = 434,
    parameter integer POR_CYCLES = 1_000_000
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       uart_rx,
    output wire       uart_tx,
    output wire [7:0] display_image_id,
    output wire       display_update_toggle,
    output wire       link_seen,
    output wire       fault,
    output wire       command_toggle,
    output wire       packet_test_done,
    output wire       packet_test_pass
);
    wire core_rst_n;
    db_startup_reset #(.POR_CYCLES(POR_CYCLES)) u_por (
        .clk(clk), .ext_rst_n(rst_n), .rst_n(core_rst_n));

    wire uart_ready, uart_start, frame_tx_busy;
    wire [7:0] uart_data;
    wire rx_byte_valid, rx_framing_error, rx_activity;
    wire [7:0] rx_byte_data;
    wire rx_frame_valid, rx_frame_error;
    wire [7:0] rx_frame_opcode;
    wire [2:0] rx_frame_length;
    wire [31:0] rx_frame_payload;
    wire bridge_tx_request;
    wire [7:0] bridge_tx_opcode;
    wire [2:0] bridge_tx_length;
    wire [31:0] bridge_tx_payload;
    wire bridge_fault;
    wire reply_toggle;
    wire catalog_valid;
    wire [7:0] catalog_count;
    wire [15:0] catalog_epoch;
    wire source_ready, source_busy, source_done, source_error;
    wire [15:0] credit_level;
    wire media_valid;
    wire [31:0] media_data;
    wire media_line_start, media_line_end, media_frame_end;
    wire [15:0] media_frame_id;
    wire [7:0] media_image_id;
    wire [15:0] media_line_index;
    wire packet_test_fail;
    wire [15:0] good_packets;

    db_uart_tx #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) u_uart_tx (
        .clk(clk), .rst_n(core_rst_n), .start(uart_start), .data(uart_data),
        .ready(uart_ready), .tx(uart_tx));
    db_uart_rx #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) u_uart_rx (
        .clk(clk), .rst_n(core_rst_n), .rx(uart_rx), .valid(rx_byte_valid),
        .data(rx_byte_data), .framing_error(rx_framing_error),
        .rx_activity(rx_activity));
    db_ctrl_frame_tx u_ctrl_tx (
        .clk(clk), .rst_n(core_rst_n), .request(bridge_tx_request),
        .opcode(bridge_tx_opcode), .length(bridge_tx_length),
        .payload(bridge_tx_payload), .uart_ready(uart_ready),
        .uart_start(uart_start), .uart_data(uart_data), .busy(frame_tx_busy));
    db_ctrl_frame_parser u_ctrl_rx (
        .clk(clk), .rst_n(core_rst_n), .byte_valid(rx_byte_valid),
        .byte_data(rx_byte_data), .frame_valid(rx_frame_valid),
        .opcode(rx_frame_opcode), .length(rx_frame_length),
        .payload(rx_frame_payload), .frame_error(rx_frame_error));

    m1a_uart_service_bridge #(.CATALOG_COUNT(4)) u_service_bridge (
        .clk(clk), .rst_n(core_rst_n), .rx_frame_valid(rx_frame_valid),
        .rx_frame_opcode(rx_frame_opcode), .rx_frame_length(rx_frame_length),
        .rx_frame_payload(rx_frame_payload), .rx_frame_error(rx_frame_error),
        .rx_framing_error(rx_framing_error), .frame_tx_busy(frame_tx_busy),
        .frame_tx_request(bridge_tx_request), .frame_tx_opcode(bridge_tx_opcode),
        .frame_tx_length(bridge_tx_length), .frame_tx_payload(bridge_tx_payload),
        .display_image_id(display_image_id), .link_seen(link_seen),
        .fault(bridge_fault), .command_toggle(command_toggle),
        .reply_toggle(reply_toggle), .display_update_toggle(display_update_toggle),
        .catalog_valid(catalog_valid), .catalog_count(catalog_count),
        .catalog_epoch(catalog_epoch), .source_ready(source_ready),
        .source_busy(source_busy), .source_done(source_done),
        .source_error(source_error), .credit_level(credit_level),
        .media_valid(media_valid), .media_ready(1'b1), .media_data(media_data),
        .media_line_start(media_line_start), .media_line_end(media_line_end),
        .media_frame_end(media_frame_end), .media_frame_id(media_frame_id),
        .media_image_id(media_image_id), .media_line_index(media_line_index));

    m1b_packet_selftest u_packet_selftest (
        .clk(clk), .rst_n(core_rst_n), .done(packet_test_done),
        .pass(packet_test_pass), .fail(packet_test_fail),
        .good_packets(good_packets));

    assign fault = bridge_fault | packet_test_fail;
    wire _unused = reply_toggle ^ catalog_valid ^ ^catalog_count ^ ^catalog_epoch ^
                   source_ready ^ source_busy ^ source_done ^ source_error ^
                   ^credit_level ^ media_valid ^ ^media_data ^ media_line_start ^
                   media_line_end ^ media_frame_end ^ ^media_frame_id ^
                   ^media_image_id ^ ^media_line_index ^ rx_activity ^ ^good_packets;
endmodule
