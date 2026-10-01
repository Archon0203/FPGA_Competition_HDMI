// ============================================================================
// M1 ABC integrated board demo - SLAVE/HDMI diagnostic role.
//
// Control: receives payload-capable 115200 UART frames and routes them into
// the A-line media-service mock. OPEN(image_id) changes one of four local
// deterministic HDMI patterns. The pattern config crosses 50 -> 25 MHz using
// a stable mailbox and is committed only at a frame boundary.
//
// Display: P1-04C board-proven 640x480 APUG092/HDMI_B boundary is preserved.
// This M1 demo intentionally proves control integration, not the future raw
// 1080p media data-plane bandwidth.
// ============================================================================
module m1abc_slave_hdmi_top #(
    parameter integer UART_CLKS_PER_BIT = 434,
    parameter integer POR_CYCLES = 1_000_000
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       uart_rx,
    output wire       uart_tx,
    output wire [3:0] led,

    output wire HDMI_D0_P,
    output wire HDMI_D1_P,
    output wire HDMI_D2_P,
    output wire HDMI_CLK_P,
    output wire HDMI_DDC_SCL,
    inout  wire HDMI_DDC_SDA
);
    // ---------------------------------------------------------------------
    // 50 MHz control domain reset
    // ---------------------------------------------------------------------
    wire core_rst_n;
    db_startup_reset #(.POR_CYCLES(POR_CYCLES)) u_por (
        .clk(clk), .ext_rst_n(rst_n), .rst_n(core_rst_n));

    // ---------------------------------------------------------------------
    // B control transport: corrected 115200 UART + generic payload frame
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

    wire bridge_tx_request;
    wire [7:0] bridge_tx_opcode;
    wire [2:0] bridge_tx_length;
    wire [31:0] bridge_tx_payload;

    db_uart_tx #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) u_uart_tx (
        .clk(clk), .rst_n(core_rst_n), .start(uart_start),
        .data(uart_data), .ready(uart_ready), .tx(uart_tx));
    db_uart_rx #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) u_uart_rx (
        .clk(clk), .rst_n(core_rst_n), .rx(uart_rx),
        .valid(rx_byte_valid), .data(rx_byte_data),
        .framing_error(rx_framing_error), .rx_activity(rx_activity));
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

    // ---------------------------------------------------------------------
    // A line: media-service shell behind the transport adapter
    // ---------------------------------------------------------------------
    wire [7:0] display_image_id_sys;
    wire display_update_toggle;
    wire link_seen;
    wire bridge_fault;
    wire command_toggle;
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

    m1a_uart_service_bridge #(.CATALOG_COUNT(4)) u_service_bridge (
        .clk(clk), .rst_n(core_rst_n),
        .rx_frame_valid(rx_frame_valid), .rx_frame_opcode(rx_frame_opcode),
        .rx_frame_length(rx_frame_length), .rx_frame_payload(rx_frame_payload),
        .rx_frame_error(rx_frame_error), .rx_framing_error(rx_framing_error),
        .frame_tx_busy(frame_tx_busy), .frame_tx_request(bridge_tx_request),
        .frame_tx_opcode(bridge_tx_opcode), .frame_tx_length(bridge_tx_length),
        .frame_tx_payload(bridge_tx_payload),
        .display_image_id(display_image_id_sys), .link_seen(link_seen),
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

    // B-line packet format/sequence/CRC self-test. This is an RTL contract
    // gate only; future wide GPIO physical PRBS remains a separate board gate.
    wire packet_test_done, packet_test_pass, packet_test_fail;
    wire [15:0] packet_good_count;
    m1b_packet_selftest u_packet_selftest (
        .clk(clk), .rst_n(core_rst_n), .done(packet_test_done),
        .pass(packet_test_pass), .fail(packet_test_fail),
        .good_packets(packet_good_count));

    // ---------------------------------------------------------------------
    // P1-04C golden HDMI clock/reset boundary
    // ---------------------------------------------------------------------
    wire pixel_clk;
    wire serial_clk;
    wire pll_lock;
    p1_hdmi_pll_50m_25_125 u_hdmi_pll (
        .refclk_50m(clk), .reset(1'b0), .lock(pll_lock),
        .pixel_clk(pixel_clk), .serial_clk(serial_clk));

    reg [19:0] hdmi_rst_cnt;
    reg hdmi_rst;
    initial begin
        hdmi_rst_cnt = 20'd0;
        hdmi_rst = 1'b1;
    end
    always @(posedge clk) begin
        if (!rst_n || !pll_lock) begin
            hdmi_rst_cnt <= 20'd0;
            hdmi_rst <= 1'b1;
        end else if (hdmi_rst_cnt < 20'd1000000) begin
            hdmi_rst_cnt <= hdmi_rst_cnt + 1'b1;
            hdmi_rst <= 1'b1;
        end else begin
            hdmi_rst <= 1'b0;
        end
    end
    wire pix_rst_n = ~hdmi_rst;

    // Official free-running cadence remains the timing owner.
    wire axis_user;
    wire axis_valid;
    wire axis_last;
    wire [23:0] axis_base_data;
    wire [23:0] axis_selected_data;
    wire axis_ready;

    hdmi_official_baseline_source u_video_source (
        .clk_pix(pixel_clk), .rst(hdmi_rst), .axis_user(axis_user),
        .axis_valid(axis_valid), .axis_last(axis_last), .axis_data(axis_base_data));

    // C line: frame-boundary configuration snapshot.
    wire [7:0] active_image_id_pix;
    wire config_applied_pulse;
    m1c_frame_config_cdc #(.WIDTH(8)) u_config_cdc (
        .src_clk(clk), .src_rst_n(core_rst_n),
        .src_value(display_image_id_sys),
        .src_update_toggle(display_update_toggle),
        .pix_clk(pixel_clk), .pix_rst_n(pix_rst_n),
        .frame_boundary(axis_user), .active_value(active_image_id_pix),
        .update_pulse(config_applied_pulse));

    reg link_sync1, link_sync2, fault_sync1, fault_sync2;
    always @(posedge pixel_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            link_sync1 <= 1'b0;
            link_sync2 <= 1'b0;
            fault_sync1 <= 1'b0;
            fault_sync2 <= 1'b0;
        end else begin
            link_sync1 <= link_seen;
            link_sync2 <= link_sync1;
            fault_sync1 <= bridge_fault | packet_test_fail;
            fault_sync2 <= fault_sync1;
        end
    end

    m1c_axis_pattern_mux #(.HACTIVE(640), .VACTIVE(480)) u_pattern_mux (
        .clk_pix(pixel_clk), .rst(hdmi_rst), .axis_user(axis_user),
        .axis_valid(axis_valid), .axis_last(axis_last), .base_data(axis_base_data),
        .pattern_id(active_image_id_pix[1:0]), .link_ok(link_sync2),
        .fault(fault_sync2), .axis_data(axis_selected_data));

    // Official EDID trigger timing from the board-proven P1-04C top.
    reg [16:0] edid_cnt;
    reg edid_trig;
    reg edid_done;
    always @(posedge pixel_clk or posedge hdmi_rst) begin
        if (hdmi_rst) begin
            edid_cnt  <= 17'd0;
            edid_trig <= 1'b0;
            edid_done <= 1'b0;
        end else begin
            edid_trig <= 1'b0;
            if (!edid_done) begin
                if (edid_cnt == 17'd100000) begin
                    edid_trig <= 1'b1;
                    edid_done <= 1'b1;
                end else begin
                    edid_cnt <= edid_cnt + 1'b1;
                end
            end
        end
    end

    wire edid_valid_unused;
    wire [7:0] edid_data_unused;
    wire video_locked_unused;
    apug092_tx_wrapper #(
        .HACTIVE(640), .HFP(16), .HSA(96), .HBP(48),
        .VACTIVE(480), .VFP(10), .VSA(2), .VBP(33),
        .VIDEO_VIC(1), .IIC_SCL_DIV(250)
    ) u_apug092_tx (
        .pixel_clk(pixel_clk), .serial_clk(serial_clk), .rst(hdmi_rst),
        .edid_read_trig(edid_trig), .edid_read_valid(edid_valid_unused),
        .edid_read_data(edid_data_unused),
        .axis_user(axis_user), .axis_valid(axis_valid), .axis_last(axis_last),
        .axis_data(axis_selected_data), .axis_ready(axis_ready),
        .audio_valid(1'b0), .audio_left_data(24'd0),
        .audio_right_data(24'd0), .acr_valid(1'b0),
        .acr_cts(20'd0), .acr_n(20'd0), .video_locked(video_locked_unused),
        .ddc_scl(HDMI_DDC_SCL), .ddc_sda(HDMI_DDC_SDA),
        .tmds_ch0_p(HDMI_D0_P), .tmds_ch1_p(HDMI_D1_P),
        .tmds_ch2_p(HDMI_D2_P), .tmds_clk_p(HDMI_CLK_P));

    // Board-visible status: command activity / control link / packet-contract
    // self-test / any fault.
    assign led[0] = command_toggle;
    assign led[1] = link_seen;
    assign led[2] = packet_test_done && packet_test_pass;
    assign led[3] = bridge_fault || packet_test_fail;

    wire _unused_diag = reply_toggle ^ catalog_valid ^ ^catalog_count ^
                        ^catalog_epoch ^ source_ready ^ source_busy ^ source_done ^
                        source_error ^ ^credit_level ^ media_valid ^ ^media_data ^
                        media_line_start ^ media_line_end ^ media_frame_end ^
                        ^media_frame_id ^ ^media_image_id ^ ^media_line_index ^
                        rx_activity ^ config_applied_pulse ^ ^packet_good_count ^
                        axis_ready ^ edid_valid_unused ^ ^edid_data_unused ^
                        video_locked_unused;
endmodule
