// Master owns physical keys, UART coordinator, received frame storage and HDMI.
// TF/FAT32/BMP stay on the Slave. GPIO mailbox is a staged-image bring-up PHY.
module m2_master_tf_hdmi_top(
    input wire clk, rst_n, uart_rx,
    output wire uart_tx,
    input wire key_next_n, key_prev_n, key_play_n,
    input wire [6:0] link_data, input wire link_req,
    output wire link_ack, output wire display_published,
    output wire [3:0] led,
    output wire [7:0] diag_led_n, output wire [7:0] diag_sel_n,
    output wire HDMI_D0_P, HDMI_D1_P, HDMI_D2_P, HDMI_CLK_P,
    output wire HDMI_DDC_SCL, inout wire HDMI_DDC_SDA);
    wire [3:0] ctrl_led, display_led;
    wire media_clk, media_rst_n, packet_valid, packet_ready;
    wire [31:0] packet_data;
    wire ctrl_query_valid, ctrl_query_ready, ctrl_reply_valid, ctrl_reply_hit, ctrl_reply_ready;
    wire [7:0] ctrl_query_id, media_query_id;
    wire media_query_valid, media_query_ready, media_reply_valid, media_reply_hit, media_reply_ready;
    wire card_missing_ctrl;
    reg card_missing_ff1, card_missing_ff2;
    always @(posedge media_clk or negedge media_rst_n) begin
        if(!media_rst_n) begin card_missing_ff1<=0; card_missing_ff2<=0; end
        else begin card_missing_ff1<=card_missing_ctrl; card_missing_ff2<=card_missing_ff1; end
    end
    m2_cache_command_cdc u_cache_cdc(
        .ctrl_clk(clk), .media_clk(media_clk), .rst_n(rst_n && media_rst_n),
        .ctrl_query_valid(ctrl_query_valid), .ctrl_query_id(ctrl_query_id), .ctrl_query_ready(ctrl_query_ready),
        .ctrl_reply_valid(ctrl_reply_valid), .ctrl_reply_hit(ctrl_reply_hit), .ctrl_reply_ready(ctrl_reply_ready),
        .media_query_valid(media_query_valid), .media_query_id(media_query_id), .media_query_ready(media_query_ready),
        .media_reply_valid(media_reply_valid), .media_reply_hit(media_reply_hit), .media_reply_ready(media_reply_ready));
    m2_master_media_control #(.ENABLE_LOCAL_CACHE(1)) u_control(.clk(clk), .rst_n(rst_n && media_rst_n),
        .cache_query_valid(ctrl_query_valid), .cache_query_id(ctrl_query_id), .cache_query_ready(ctrl_query_ready),
        .cache_reply_valid(ctrl_reply_valid), .cache_reply_hit(ctrl_reply_hit), .cache_reply_ready(ctrl_reply_ready),
        .card_missing(card_missing_ctrl),
        .uart_rx(uart_rx), .uart_tx(uart_tx),
        .key_next_n(key_next_n), .key_prev_n(key_prev_n), .key_play_n(key_play_n),
        .led(ctrl_led), .catalog_valid(), .catalog_count(),
        .selected_image_id(), .link_ok(), .fault());
    m2_gpio_mailbox_rx u_link_rx(.clk(media_clk), .rst_n(media_rst_n),
        .data(link_data), .req(link_req), .ack(link_ack),
        .out_valid(packet_valid), .out_data(packet_data), .out_ready(packet_ready));
    m2_frame_display_core #(.REMOTE_INPUT(1)) u_display(
        .clk(clk), .rst_n(rst_n), .uart_rx(1'b1), .uart_tx(), .led(display_led),
        .diag_led_n(diag_led_n), .diag_sel_n(diag_sel_n),
        .sd_ncs(), .sd_sclk(), .sd_mosi(), .sd_miso(1'b1),
        .remote_valid(packet_valid), .remote_data(packet_data), .remote_ready(packet_ready),
        .cache_query_valid(media_query_valid), .cache_query_image_id(media_query_id), .cache_query_ready(media_query_ready),
        .cache_reply_valid(media_reply_valid), .cache_reply_hit(media_reply_hit), .cache_reply_ready(media_reply_ready),
        .card_missing(card_missing_ff2),
        .remote_published(display_published), .media_clock(media_clk), .media_reset_n(media_rst_n),
        .HDMI_D0_P(HDMI_D0_P), .HDMI_D1_P(HDMI_D1_P), .HDMI_D2_P(HDMI_D2_P),
        .HDMI_CLK_P(HDMI_CLK_P), .HDMI_DDC_SCL(HDMI_DDC_SCL), .HDMI_DDC_SDA(HDMI_DDC_SDA));
    assign led={display_led[3] || ctrl_led[3],display_published,ctrl_led[1:0]};
endmodule
