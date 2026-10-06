// Real M2 Master control plane.
//
// Dedicated control wrapper without the legacy local diagnostic instance.
// catalog_valid and catalog_count come from the live UART coordinator, as
// in the previous M1 wrapper. OPEN requests
// are issued only after the Slave has answered PING and are held until the
// matching image reports DONE.
module m2_master_media_control #(
    parameter integer ENABLE_LOCAL_CACHE = 0,
    parameter integer UART_CLKS_PER_BIT = 434,
    parameter integer POR_CYCLES = 1_000_000,
    parameter integer SLIDE_PERIOD_CLKS = 250_000_000,
    parameter integer KEY_FILTER_CYCLES = 500000,
    parameter integer DISCOVERY_INTERVAL_CYCLES = 5_000_000,
    parameter integer ACK_TIMEOUT_CYCLES = 2_500_000,
    parameter integer STATUS_POLL_INTERVAL_CYCLES = 50_000
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       uart_rx,
    output wire       uart_tx,
    input  wire       key_next_n,
    input  wire       key_prev_n,
    input  wire       key_play_n,
    output wire [3:0] led,
    output wire       catalog_valid,
    output wire [7:0] catalog_count,
    output wire [7:0] selected_image_id,
    output wire       link_ok,
    output wire       fault,
    output wire cache_query_valid, output wire [7:0] cache_query_id,
    input wire cache_query_ready,
    input wire cache_reply_valid, cache_reply_hit, output wire cache_reply_ready,
    output wire card_missing
);
    wire core_rst_n;
    db_startup_reset #(.POR_CYCLES(POR_CYCLES)) u_por (
        .clk(clk), .ext_rst_n(rst_n), .rst_n(core_rst_n));

    wire [3:0] key_event;
    wire [3:0] key_raw_n = {1'b1, key_prev_n, key_next_n, key_play_n};
    wire [3:0] key_level;
    key_filter #(.CNT_MAX(KEY_FILTER_CYCLES), .ACTIVE_LOW(1'b1)) u_keys (
        .clk(clk), .rst_n(core_rst_n), .key_in(key_raw_n),
        .key_out(key_level), .key_event(key_event));

    wire media_cmd_valid, media_cmd_ready;
    wire [7:0] media_cmd_image_id;
    wire [1:0] media_cmd_mode;
    wire [7:0] selected_image;
    wire play_en, emergency, slide_tick, beep_alert;
    wire [1:0] transition_mode;
    wire [7:0] contrast;
    wire signed [7:0] brightness;
    wire osd_en;
    media_command_controller #(
        .IMAGE_ID_WIDTH(8), .SLIDE_PERIOD_CLKS(SLIDE_PERIOD_CLKS),
        .ENABLE_PREFETCH(ENABLE_LOCAL_CACHE)
    ) u_commands (
        .clk(clk), .rst_n(core_rst_n), .key_event(key_event), .sw(4'b0000),
        .catalog_valid(catalog_valid), .catalog_count(catalog_count),
        .media_cmd_ready(media_cmd_ready), .media_cmd_valid(media_cmd_valid),
        .media_cmd_image_id(media_cmd_image_id), .media_cmd_mode(media_cmd_mode),
        .selected_image_id(selected_image), .play_en(play_en),
        .emergency(emergency), .slide_tick(slide_tick),
        .transition_mode(transition_mode), .contrast(contrast),
        .brightness(brightness), .osd_en(osd_en), .beep_alert(beep_alert));

    wire coord_cmd_valid, coord_cmd_ready;
    wire [7:0] coord_cmd_id;
    wire [1:0] coord_cmd_mode;
    wire local_commit;
    generate if(ENABLE_LOCAL_CACHE) begin : g_cache
        m2_cache_command_router u_router(
            .clk(clk), .rst_n(core_rst_n),
            .cmd_valid(media_cmd_valid), .cmd_id(media_cmd_image_id), .cmd_mode(media_cmd_mode),
            .cmd_ready(media_cmd_ready), .query_valid(cache_query_valid), .query_id(cache_query_id),
            .query_ready(cache_query_ready), .reply_valid(cache_reply_valid), .reply_hit(cache_reply_hit),
            .reply_ready(cache_reply_ready), .remote_valid(coord_cmd_valid), .remote_id(coord_cmd_id),
            .remote_mode(coord_cmd_mode), .remote_ready(coord_cmd_ready), .local_commit(local_commit));
    end else begin : g_direct
        assign coord_cmd_valid=media_cmd_valid;
        assign coord_cmd_id=media_cmd_image_id;
        assign coord_cmd_mode=media_cmd_mode;
        assign media_cmd_ready=coord_cmd_ready;
        assign cache_query_valid=0; assign cache_query_id=0; assign cache_reply_ready=0;
        assign local_commit=0;
    end endgenerate

    wire uart_ready, uart_start, rx_byte_valid, rx_framing_error, rx_activity;
    wire [7:0] uart_data, rx_byte_data;
    wire frame_tx_busy, rx_frame_valid, rx_frame_error;
    wire [7:0] rx_frame_opcode;
    wire [2:0] rx_frame_length;
    wire [31:0] rx_frame_payload;
    wire coord_tx_request;
    wire [7:0] coord_tx_opcode;
    wire [2:0] coord_tx_length;
    wire [31:0] coord_tx_payload;
    wire [7:0] remote_selected_image, remote_status, remote_error;
    wire ack_toggle, image_change_toggle;

    db_uart_tx #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) u_tx (
        .clk(clk), .rst_n(core_rst_n), .start(uart_start), .data(uart_data),
        .ready(uart_ready), .tx(uart_tx));
    db_uart_rx #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) u_rx (
        .clk(clk), .rst_n(core_rst_n), .rx(uart_rx), .valid(rx_byte_valid),
        .data(rx_byte_data), .framing_error(rx_framing_error),
        .rx_activity(rx_activity));
    db_ctrl_frame_tx u_frame_tx (
        .clk(clk), .rst_n(core_rst_n), .request(coord_tx_request),
        .opcode(coord_tx_opcode), .length(coord_tx_length),
        .payload(coord_tx_payload), .uart_ready(uart_ready),
        .uart_start(uart_start), .uart_data(uart_data), .busy(frame_tx_busy));
    db_ctrl_frame_parser u_frame_rx (
        .clk(clk), .rst_n(core_rst_n), .byte_valid(rx_byte_valid),
        .byte_data(rx_byte_data), .frame_valid(rx_frame_valid),
        .opcode(rx_frame_opcode), .length(rx_frame_length),
        .payload(rx_frame_payload), .frame_error(rx_frame_error));
    m1c_coordinator_uart #(
        .ENABLE_LOCAL_CACHE(ENABLE_LOCAL_CACHE),
        .DISCOVERY_INTERVAL_CYCLES(DISCOVERY_INTERVAL_CYCLES),
        .ACK_TIMEOUT_CYCLES(ACK_TIMEOUT_CYCLES),
        .STATUS_POLL_INTERVAL_CYCLES(STATUS_POLL_INTERVAL_CYCLES)
    ) u_coordinator (
        .clk(clk), .rst_n(core_rst_n),
        .local_cache_commit(local_commit),
        .media_cmd_valid(coord_cmd_valid), .media_cmd_image_id(coord_cmd_id),
        .media_cmd_mode(coord_cmd_mode), .media_cmd_ready(coord_cmd_ready),
        .frame_tx_busy(frame_tx_busy), .frame_tx_request(coord_tx_request),
        .frame_tx_opcode(coord_tx_opcode), .frame_tx_length(coord_tx_length),
        .frame_tx_payload(coord_tx_payload), .rx_frame_valid(rx_frame_valid),
        .rx_frame_opcode(rx_frame_opcode), .rx_frame_length(rx_frame_length),
        .rx_frame_payload(rx_frame_payload), .rx_frame_error(rx_frame_error),
        .rx_framing_error(rx_framing_error), .catalog_valid(catalog_valid),
        .catalog_count(catalog_count), .remote_selected_image(remote_selected_image),
        .remote_status(remote_status), .remote_error(remote_error),
        .link_ok(link_ok), .fault(fault), .ack_toggle(ack_toggle),
        .image_change_toggle(image_change_toggle));

    assign card_missing = (remote_status==8'hE0) && remote_error>=8'h41 && remote_error<=8'h45;
    assign selected_image_id = selected_image;
    assign led[0] = ack_toggle;
    assign led[1] = link_ok;
    assign led[2] = image_change_toggle;
    assign led[3] = fault;

    wire unused = ^key_level ^ play_en ^ emergency ^ slide_tick ^
                  ^transition_mode ^ ^contrast ^ ^brightness ^ osd_en ^
                  beep_alert ^ ^remote_selected_image ^ ^remote_status ^
                  ^remote_error ^ rx_activity;
endmodule
