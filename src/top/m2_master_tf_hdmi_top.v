// Master owns physical keys, UART coordinator, received frame storage and HDMI.
// TF/FAT32/BMP stay on the Slave. GPIO mailbox is a staged-image bring-up PHY.
module m2_master_tf_hdmi_top(
    input wire clk, rst_n, uart_rx,
    output wire uart_tx,
    input wire key_next_n, key_prev_n, key_play_n,
    input wire [6:0] link_data, input wire link_req,
    output wire link_ack, output wire display_published,
    output wire [3:0] led,
    output wire HDMI_D0_P, HDMI_D1_P, HDMI_D2_P, HDMI_CLK_P,
    output wire HDMI_DDC_SCL, inout wire HDMI_DDC_SDA);
    wire [3:0] ctrl_led, display_led;
    wire media_clk, media_rst_n, packet_valid, packet_ready;
    wire [31:0] packet_data;
    m2_master_media_control u_control(.clk(clk), .rst_n(rst_n),
        .uart_rx(uart_rx), .uart_tx(uart_tx),
        .key_next_n(key_next_n), .key_prev_n(key_prev_n), .key_play_n(key_play_n),
        .led(ctrl_led), .catalog_valid(), .catalog_count(),
        .selected_image_id(), .link_ok(), .fault());
    m2_gpio_mailbox_rx u_link_rx(.clk(media_clk), .rst_n(media_rst_n),
        .data(link_data), .req(link_req), .ack(link_ack),
        .out_valid(packet_valid), .out_data(packet_data), .out_ready(packet_ready));
    m2_frame_display_core #(.REMOTE_INPUT(1)) u_display(
        .clk(clk), .rst_n(rst_n), .uart_rx(1'b1), .uart_tx(), .led(display_led),
        .diag_led_n(), .diag_sel_n(), .sd_ncs(), .sd_sclk(), .sd_mosi(), .sd_miso(1'b1),
        .remote_valid(packet_valid), .remote_data(packet_data), .remote_ready(packet_ready),
        .remote_published(display_published), .media_clock(media_clk), .media_reset_n(media_rst_n),
        .HDMI_D0_P(HDMI_D0_P), .HDMI_D1_P(HDMI_D1_P), .HDMI_D2_P(HDMI_D2_P),
        .HDMI_CLK_P(HDMI_CLK_P), .HDMI_DDC_SCL(HDMI_DDC_SCL), .HDMI_DDC_SDA(HDMI_DDC_SDA));
    assign led={display_led[3] || ctrl_led[3],display_published,ctrl_led[1:0]};
endmodule
