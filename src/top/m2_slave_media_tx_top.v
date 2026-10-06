module m2_slave_media_tx_top(
    input wire clk, rst_n, uart_rx, sd_miso,
    output wire uart_tx, sd_ncs, sd_sclk, sd_mosi,
    output wire [3:0] led,
    output wire [7:0] diag_led_n, output wire [7:0] diag_sel_n,
    output wire [6:0] link_data, output wire link_req,
    input wire link_ack, input wire display_published);
    localparam HACTIVE=640, VACTIVE=480;
    wire pixel_clk;
    wire serial_clk;
    wire hdmi_pll_lock;

    p1_hdmi_pll_50m_25_125 u_hdmi_pll (
        .refclk_50m (clk),
        .reset      (1'b0),
        .lock       (hdmi_pll_lock),
        .pixel_clk  (pixel_clk),
        .serial_clk (serial_clk)
    );

    // ============================================================
    // P1-04C golden HDMI reset sequencing (~20 ms after PLL lock).
    // Release on the rising edge of the 50 MHz source clock.  This is the
    // board-proven phase used by the HDMI reference design and leaves the
    // required 4 ns recovery window before the 125 MHz serial clock.  Releasing
    // on the falling edge creates a 2 ns recovery window and fails the serial
    // PHY reset check in TD6.2.1.
    // ============================================================
    reg [19:0] hdmi_rst_cnt;
    reg        hdmi_rst;

    initial begin
        hdmi_rst_cnt = 20'd0;
        hdmi_rst     = 1'b1;
    end

    always @(posedge clk) begin
        if (!hdmi_pll_lock || !rst_n) begin
            hdmi_rst_cnt <= 20'd0;
            hdmi_rst     <= 1'b1;
        end else if (hdmi_rst_cnt < 20'd1000000) begin
            hdmi_rst_cnt <= hdmi_rst_cnt + 20'd1;
            hdmi_rst     <= 1'b1;
        end else begin
            hdmi_rst <= 1'b0;
        end
    end

    wire pix_rst_n = !hdmi_rst;


    wire media_rst_n=pix_rst_n && rst_n;
    wire media_cmd_valid, media_cmd_ready;
    wire [7:0] media_cmd_image_id;
    wire media_wr_valid, media_wr_ready, media_busy, media_done, media_error;
    wire [20:0] media_wr_addr;
    wire [31:0] media_wr_data;
    wire media_catalog_valid;
    wire [7:0] media_catalog_count, media_error_code, media_sector_error_detail;
    wire media_descriptor_valid;
    wire [87:0] media_descriptor_filename_83;
    wire [15:0] media_descriptor_width, media_descriptor_height;
    reg media_succeeded, media_failed;
    reg [7:0] media_failure_code, selected_image_id, active_image_id;
    reg media_scan_start;
    reg [24:0] retry_count;
    wire uart_byte_valid, uart_framing_error, uart_rx_activity;
    wire [7:0] uart_byte_data;
    wire ctrl_rx_frame_valid, ctrl_rx_frame_error;
    wire [7:0] ctrl_rx_frame_opcode;
    wire [2:0] ctrl_rx_frame_length;
    wire [31:0] ctrl_rx_frame_payload;
    wire uart_byte_ready, uart_byte_start;
    wire [7:0] uart_byte_tx_data;
    wire ctrl_tx_busy, ctrl_tx_request;
    wire [7:0] ctrl_tx_opcode;
    wire [2:0] ctrl_tx_length;
    wire [31:0] ctrl_tx_payload;
    wire remote_open_request;
    wire [7:0] remote_open_image_id;
    wire remote_open_prefetch;
    wire ctrl_link_seen, ctrl_fault, ctrl_command_toggle, ctrl_reply_toggle;
    wire tx_busy;
    reg published1, published2, observed_loading;
    // Transport-level recovery: if a complete frame was sent but the Master
    // never publishes it (for example because the Master reset mid-frame),
    // re-open the same image from TF and transmit a fresh framed copy.
    // 25,000,000 pixel clocks is ~1 s at the board-proven 25 MHz media clock.
    reg [24:0] publish_wait_count;
    reg transport_retry_request;
    reg transport_retry_active;
    // DISPLAY_PUBLISHED is asynchronous to this board's media clock.  Keep
    // the observed completion sticky so STATUS polling cannot miss a one-cycle
    // cache-fill publication on the Master.
    reg publish_seen_sticky;
    wire use_framebuffer=published2 && observed_loading && !tx_busy;
    db_uart_rx #(.CLKS_PER_BIT(217)) u_m2_uart_rx (
        .clk(pixel_clk), .rst_n(media_rst_n), .rx(uart_rx),
        .valid(uart_byte_valid), .data(uart_byte_data),
        .framing_error(uart_framing_error), .rx_activity(uart_rx_activity));
    db_ctrl_frame_parser u_m2_ctrl_rx (
        .clk(pixel_clk), .rst_n(media_rst_n), .byte_valid(uart_byte_valid),
        .byte_data(uart_byte_data), .frame_valid(ctrl_rx_frame_valid),
        .opcode(ctrl_rx_frame_opcode), .length(ctrl_rx_frame_length),
        .payload(ctrl_rx_frame_payload), .frame_error(ctrl_rx_frame_error));
    db_uart_tx #(.CLKS_PER_BIT(217)) u_m2_uart_tx (
        .clk(pixel_clk), .rst_n(media_rst_n), .start(uart_byte_start),
        .data(uart_byte_tx_data), .ready(uart_byte_ready), .tx(uart_tx));
    db_ctrl_frame_tx u_m2_ctrl_tx (
        .clk(pixel_clk), .rst_n(media_rst_n), .request(ctrl_tx_request),
        .opcode(ctrl_tx_opcode), .length(ctrl_tx_length), .payload(ctrl_tx_payload),
        .uart_ready(uart_byte_ready), .uart_start(uart_byte_start),
        .uart_data(uart_byte_tx_data), .busy(ctrl_tx_busy));
    wire       dispatch_cmd_valid;
    wire [7:0] dispatch_cmd_image_id;
    wire       dispatch_cmd_is_remote;
    wire       dispatch_cmd_is_prefetch;
    wire       dispatch_bootstrap_issued;
    wire       dispatch_remote_queued;
    wire       media_cmd_accept_ready;

    m2_real_media_uart_bridge u_m2_real_ctrl (
        .clk(pixel_clk), .rst_n(media_rst_n),
        .rx_frame_valid(ctrl_rx_frame_valid), .rx_frame_opcode(ctrl_rx_frame_opcode),
        .rx_frame_length(ctrl_rx_frame_length), .rx_frame_payload(ctrl_rx_frame_payload),
        .rx_frame_error(ctrl_rx_frame_error), .rx_framing_error(uart_framing_error),
        .frame_tx_busy(ctrl_tx_busy), .frame_tx_request(ctrl_tx_request),
        .frame_tx_opcode(ctrl_tx_opcode), .frame_tx_length(ctrl_tx_length),
        .frame_tx_payload(ctrl_tx_payload), .catalog_valid(media_catalog_valid),
        .catalog_count(media_catalog_count),
        .source_busy(media_busy || dispatch_cmd_valid || dispatch_remote_queued ||
                     (media_succeeded && !publish_seen_sticky)),
        .source_done(1'b0), .source_valid(media_succeeded && publish_seen_sticky),
        .source_error(media_failed),
        .source_error_code(media_failure_code), .selected_image_id(selected_image_id),
        .open_request(remote_open_request), .open_image_id(remote_open_image_id),
        .open_prefetch(remote_open_prefetch),
        .link_seen(ctrl_link_seen), .fault(ctrl_fault),
        .command_toggle(ctrl_command_toggle), .reply_toggle(ctrl_reply_toggle));

    // One-shot standalone bootstrap + Master-owned selection after startup.
    // This prevents the old behavior where every completed image immediately
    // triggered another automatic OPEN(0), which masked Master NEXT/PREV and
    // could produce a later 0x3B fault after an otherwise successful display.
    wire dispatcher_open_request = remote_open_request || transport_retry_request;
    wire [7:0] dispatcher_open_image_id = remote_open_request
                                                ? remote_open_image_id
                                                : selected_image_id;

    m2_open_dispatcher u_m2_open_dispatcher (
        .clk                  (pixel_clk),
        .rst_n                (media_rst_n),
        .catalog_valid        (media_catalog_valid),
        .catalog_count        (media_catalog_count),
        .cmd_ready            (media_cmd_accept_ready),
        .remote_open_request  (dispatcher_open_request),
        .remote_open_image_id (dispatcher_open_image_id),
        .remote_open_prefetch (remote_open_request && remote_open_prefetch),
        .catalog_restart      (media_scan_start),
        .cmd_valid            (dispatch_cmd_valid),
        .cmd_image_id         (dispatch_cmd_image_id),
        .cmd_is_remote        (dispatch_cmd_is_remote),
        .cmd_is_prefetch      (dispatch_cmd_is_prefetch),
        .bootstrap_issued     (dispatch_bootstrap_issued),
        .remote_queued        (dispatch_remote_queued)
    );

    assign media_cmd_accept_ready = media_cmd_ready &&
                                  (!media_succeeded || use_framebuffer || publish_seen_sticky ||
                                   dispatch_cmd_is_remote || transport_retry_active) &&
                                  !tx_busy;
    assign media_cmd_valid    = dispatch_cmd_valid && media_cmd_accept_ready;
    assign media_cmd_image_id = dispatch_cmd_image_id;
    wire dispatch_fire=dispatch_cmd_valid && media_cmd_accept_ready;
    m2_slave_tf_media_core #(.SPI_CLK_DIV(0), .SPI_INIT_CLK_DIV(32),
                             .SPI_MODE3(1),
                             .WIDTH(HACTIVE), .HEIGHT(VACTIVE)) u_media (
        .clk             (pixel_clk),
        .rst_n           (media_rst_n),
        .scan_start      (media_scan_start),
        .cmd_valid       (media_cmd_valid),
        .cmd_ready       (media_cmd_ready),
        .cmd_image_id    (media_cmd_image_id),
        .frame_base      (21'd0),
        .sd_ncs          (sd_ncs),
        .sd_sclk         (sd_sclk),
        .sd_mosi         (sd_mosi),
        .sd_miso         (sd_miso),
        .mem_wr_valid    (media_wr_valid),
        .mem_wr_addr     (media_wr_addr),
        .mem_wr_data     (media_wr_data),
        .mem_wr_ready    (media_wr_ready),
        .catalog_valid   (media_catalog_valid),
        .catalog_count   (media_catalog_count), .catalog_epoch (),
        .descriptor_valid(media_descriptor_valid), .descriptor_image_id(),
        .descriptor_width(media_descriptor_width), .descriptor_height(media_descriptor_height),
        .descriptor_filename_83(media_descriptor_filename_83),
        .source_ready    (), .source_busy(media_busy),
        .source_done     (media_done), .source_error(media_error),
        .error_code      (media_error_code),
        .sector_error_detail(media_sector_error_detail)
    );


    wire packet_valid, packet_ready;
    wire [31:0] packet_data;
    m2_remote_frame_tx #(.COMPACT_RGB888(1)) u_frame_tx(.clk(pixel_clk), .rst_n(media_rst_n),
        .frame_begin(dispatch_fire), .image_id(media_cmd_image_id),
        .wr_valid(media_wr_valid), .wr_addr(media_wr_addr), .wr_data(media_wr_data),
        .wr_ready(media_wr_ready), .frame_done(media_done), .frame_error(media_error),
        .filename_valid(media_descriptor_valid), .filename_83(media_descriptor_filename_83),
        .info_valid(media_descriptor_valid), .image_width(media_descriptor_width),
        .image_height(media_descriptor_height), .image_bpp(6'd24),
        .prefetch_frame(dispatch_cmd_is_prefetch),
        .out_valid(packet_valid), .out_data(packet_data), .out_ready(packet_ready), .busy(tx_busy));
    m2_gpio_mailbox_tx u_link_tx(.clk(pixel_clk), .rst_n(media_rst_n),
        .in_valid(packet_valid), .in_data(packet_data), .in_ready(packet_ready),
        .data(link_data), .req(link_req), .ack(link_ack));
    always @(posedge pixel_clk or negedge media_rst_n) begin
        if(!media_rst_n) begin
            published1<=0; published2<=0; observed_loading<=0;
            media_succeeded<=0; media_failed<=0; media_failure_code<=0;
            selected_image_id<=0; active_image_id<=0;
            media_scan_start<=0; retry_count<=0;
            publish_wait_count<=0; transport_retry_request<=0; transport_retry_active<=0;
            publish_seen_sticky<=0;
        end else begin
            published1<=display_published; published2<=published1;
            media_scan_start<=0;
            transport_retry_request<=0;

            // A one-sided Master reset can invalidate an in-flight remote
            // frame after the Slave has already consumed it from TF.  There is
            // no frame buffer on this Slave transport top, so recovery must
            // re-read and resend the selected image.  A genuine Master OPEN
            // always wins over this automatic retry.
            if (published2 || use_framebuffer || media_failed || media_busy || tx_busy ||
                remote_open_request || dispatch_cmd_valid || dispatch_remote_queued) begin
                publish_wait_count <= 0;
            end else if (media_succeeded && !transport_retry_active) begin
                if (publish_wait_count == 25'd24999999) begin
                    publish_wait_count <= 0;
                    transport_retry_request <= 1'b1;
                    transport_retry_active <= 1'b1;
                end else begin
                    publish_wait_count <= publish_wait_count + 1'b1;
                end
            end
            if(media_failed && !media_busy && !tx_busy) begin
                if(retry_count==25'd24999999) begin retry_count<=0; media_scan_start<=1; end
                else retry_count<=retry_count+1'b1;
            end else retry_count<=0;
            if(dispatch_fire) begin
                media_succeeded<=0; media_failed<=0; observed_loading<=0;
                publish_seen_sticky<=0;
                transport_retry_active<=0;
                publish_wait_count<=0;
                active_image_id<=media_cmd_image_id;
            end else if(!published2) observed_loading<=1;
            if (published2 && media_succeeded)
                publish_seen_sticky <= 1'b1;
            if(media_done) begin media_succeeded<=1; selected_image_id<=active_image_id; end
            if(media_error) begin media_failed<=1; media_failure_code<=((media_error_code==8'h11 || media_error_code==8'h14) && media_sector_error_detail[7:4]==4'h4) ? media_sector_error_detail : media_error_code; end
        end
    end
    assign led={media_failed,media_succeeded && use_framebuffer,media_busy || tx_busy,media_catalog_valid};

    // Eight-LED transport diagnostics, active-low board cathodes.  With SW6 in
    // LED mode, physical LED1..8 mean:
    //   1 catalog valid, 2 media reader busy, 3 remote TX busy,
    //   4 local media frame completed, 5 Master publish observed,
    //   6 end-to-end publish accepted, 7 automatic transport retry active,
    //   8 media/control fault.
    wire [7:0] slave_diag_byte = {media_failed || ctrl_fault, transport_retry_active,
                                  use_framebuffer, published2, media_succeeded,
                                  tx_busy, media_busy, media_catalog_valid};
    assign diag_led_n = ~slave_diag_byte;
    assign diag_sel_n = 8'hFF;
endmodule
