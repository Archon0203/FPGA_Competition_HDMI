// ============================================================================
// M1 ABC integrated board demo - MASTER/CONTROLLER role.
//
// Board controls (HX4S20C):
//   KEY1/A2 : reset (rst_n)
//   KEY2/B2 : next image
//   KEY3/B1 : previous image
//   KEY4/C1 : play/pause automatic 2 s rotation
//
// The master owns C-line user intent/coordinator and drives the proven UART
// control link. The slave owns the temporary M1 diagnostic HDMI output.
// This board-demo orientation does NOT move the final M2/M4 media ownership;
// it is a visible control-plane integration gate.
// ============================================================================
module m1abc_master_control_top #(
    parameter integer UART_CLKS_PER_BIT = 434,
    parameter integer POR_CYCLES = 1_000_000,
    parameter integer SLIDE_PERIOD_CLKS = 100_000_000,
    parameter integer DISCOVERY_INTERVAL_CYCLES = 5_000_000,
    parameter integer ACK_TIMEOUT_CYCLES = 2_500_000
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       uart_rx,
    output wire       uart_tx,
    input  wire       key_next_n,
    input  wire       key_prev_n,
    input  wire       key_play_n,
    output wire [3:0] led
);
    wire core_rst_n;
    db_startup_reset #(.POR_CYCLES(POR_CYCLES)) u_por (
        .clk(clk), .ext_rst_n(rst_n), .rst_n(core_rst_n));

    // ---------------------------------------------------------------------
    // C line: input abstraction + media intent
    // ---------------------------------------------------------------------
    wire [3:0] key_level;
    wire [3:0] key_event;
    wire [3:0] key_raw_n = {1'b1, key_prev_n, key_next_n, key_play_n};

    key_filter #(.CNT_MAX(500000), .ACTIVE_LOW(1'b1)) u_key_filter (
        .clk(clk), .rst_n(core_rst_n), .key_in(key_raw_n),
        .key_out(key_level), .key_event(key_event));

    wire catalog_valid;
    wire [7:0] catalog_count;
    wire media_cmd_valid;
    wire media_cmd_ready;
    wire [7:0] media_cmd_image_id;
    wire [1:0] media_cmd_mode;
    wire [7:0] selected_image_id;
    wire play_en;
    wire emergency;
    wire slide_tick;
    wire [1:0] transition_mode;
    wire [7:0] contrast;
    wire signed [7:0] brightness;
    wire osd_en;
    wire beep_alert;

    media_command_controller #(
        .IMAGE_ID_WIDTH(8), .SLIDE_PERIOD_CLKS(SLIDE_PERIOD_CLKS)
    ) u_media_command_controller (
        .clk(clk), .rst_n(core_rst_n),
        .key_event(key_event), .sw(4'b0000),
        .catalog_valid(catalog_valid), .catalog_count(catalog_count),
        .media_cmd_ready(media_cmd_ready),
        .media_cmd_valid(media_cmd_valid),
        .media_cmd_image_id(media_cmd_image_id),
        .media_cmd_mode(media_cmd_mode),
        .selected_image_id(selected_image_id), .play_en(play_en),
        .emergency(emergency), .slide_tick(slide_tick),
        .transition_mode(transition_mode), .contrast(contrast),
        .brightness(brightness), .osd_en(osd_en), .beep_alert(beep_alert));

    // ---------------------------------------------------------------------
    // B line: proven UART transport + generic payload frame
    // ---------------------------------------------------------------------
    wire uart_ready;
    wire uart_start;
    wire [7:0] uart_data;
    wire frame_tx_busy;
    wire rx_byte_valid;
    wire [7:0] rx_byte_data;
    wire rx_framing_error;
    wire rx_activity;
    wire rx_frame_valid;
    wire [7:0] rx_frame_opcode;
    wire [2:0] rx_frame_length;
    wire [31:0] rx_frame_payload;
    wire rx_frame_error;

    wire coord_tx_request;
    wire [7:0] coord_tx_opcode;
    wire [2:0] coord_tx_length;
    wire [31:0] coord_tx_payload;
    wire [7:0] remote_selected_image;
    wire [7:0] remote_status;
    wire [7:0] remote_error;
    wire link_ok;
    wire fault;
    wire ack_toggle;
    wire image_change_toggle;

    db_uart_tx #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) u_uart_tx (
        .clk(clk), .rst_n(core_rst_n), .start(uart_start),
        .data(uart_data), .ready(uart_ready), .tx(uart_tx));
    db_uart_rx #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) u_uart_rx (
        .clk(clk), .rst_n(core_rst_n), .rx(uart_rx),
        .valid(rx_byte_valid), .data(rx_byte_data),
        .framing_error(rx_framing_error), .rx_activity(rx_activity));
    db_ctrl_frame_tx u_ctrl_tx (
        .clk(clk), .rst_n(core_rst_n), .request(coord_tx_request),
        .opcode(coord_tx_opcode), .length(coord_tx_length),
        .payload(coord_tx_payload), .uart_ready(uart_ready),
        .uart_start(uart_start), .uart_data(uart_data), .busy(frame_tx_busy));
    db_ctrl_frame_parser u_ctrl_rx (
        .clk(clk), .rst_n(core_rst_n), .byte_valid(rx_byte_valid),
        .byte_data(rx_byte_data), .frame_valid(rx_frame_valid),
        .opcode(rx_frame_opcode), .length(rx_frame_length),
        .payload(rx_frame_payload), .frame_error(rx_frame_error));

    m1c_coordinator_uart #(
        .DISCOVERY_INTERVAL_CYCLES(DISCOVERY_INTERVAL_CYCLES),
        .ACK_TIMEOUT_CYCLES(ACK_TIMEOUT_CYCLES)
    ) u_coordinator (
        .clk(clk), .rst_n(core_rst_n),
        .media_cmd_valid(media_cmd_valid),
        .media_cmd_image_id(media_cmd_image_id),
        .media_cmd_mode(media_cmd_mode), .media_cmd_ready(media_cmd_ready),
        .frame_tx_busy(frame_tx_busy), .frame_tx_request(coord_tx_request),
        .frame_tx_opcode(coord_tx_opcode), .frame_tx_length(coord_tx_length),
        .frame_tx_payload(coord_tx_payload),
        .rx_frame_valid(rx_frame_valid), .rx_frame_opcode(rx_frame_opcode),
        .rx_frame_length(rx_frame_length), .rx_frame_payload(rx_frame_payload),
        .rx_frame_error(rx_frame_error), .rx_framing_error(rx_framing_error),
        .catalog_valid(catalog_valid), .catalog_count(catalog_count),
        .remote_selected_image(remote_selected_image),
        .remote_status(remote_status), .remote_error(remote_error),
        .link_ok(link_ok), .fault(fault), .ack_toggle(ack_toggle),
        .image_change_toggle(image_change_toggle));

    // LEDs: activity / link / remote image change / fault.
    assign led[0] = ack_toggle;
    assign led[1] = link_ok;
    assign led[2] = image_change_toggle;
    assign led[3] = fault;

    wire _unused_status = ^key_level ^ ^selected_image_id ^ play_en ^ emergency ^
                          slide_tick ^ ^transition_mode ^ ^contrast ^ ^brightness ^
                          osd_en ^ beep_alert ^ ^remote_selected_image ^
                          ^remote_status ^ ^remote_error ^ rx_activity;
endmodule
