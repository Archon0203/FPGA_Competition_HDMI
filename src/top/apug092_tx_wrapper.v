// ================================================================
// Module  : apug092_tx_wrapper
// Purpose : APUG092 protected core + official EG HDMI PHY wrapper.
//
// Official APUG092 requires serial_clk = 5 * pixel_clk; lane_lvds_10_1 then
// uses DDR to emit the 10 TMDS bits per pixel.  Clock generation and board pin
// binding are intentionally outside this module and belong to P1-04.
// ================================================================

module apug092_tx_wrapper #(
    parameter integer HACTIVE   = 1280,
    parameter integer HFP       = 110,
    parameter integer HSA       = 40,
    parameter integer HBP       = 220,
    parameter integer VACTIVE   = 720,
    parameter integer VFP       = 5,
    parameter integer VSA       = 5,
    parameter integer VBP       = 20,
    parameter integer VIDEO_VIC = 69,
    parameter integer IIC_SCL_DIV = 125
) (
    input  wire        pixel_clk,
    input  wire        serial_clk,
    input  wire        rst,

    input  wire        edid_read_trig,
    output wire        edid_read_valid,
    output wire [7:0]  edid_read_data,

    input  wire        axis_user,
    input  wire        axis_valid,
    input  wire        axis_last,
    input  wire [23:0] axis_data,
    output wire        axis_ready,

    input  wire        audio_valid,
    input  wire [23:0] audio_left_data,
    input  wire [23:0] audio_right_data,
    input  wire        acr_valid,
    input  wire [19:0] acr_cts,
    input  wire [19:0] acr_n,

    output wire        video_locked,
    output wire        ddc_scl,
    inout  wire        ddc_sda,

    output wire        tmds_ch0_p,
    output wire        tmds_ch1_p,
    output wire        tmds_ch2_p,
    output wire        tmds_clk_p
);

    wire [9:0] ch0_tmds_data;
    wire [9:0] ch1_tmds_data;
    wire [9:0] ch2_tmds_data;
    wire [9:0] clk_tmds_data;

    apug092_core_wrapper #(
        .HACTIVE    (HACTIVE),
        .HFP        (HFP),
        .HSA        (HSA),
        .HBP        (HBP),
        .VACTIVE    (VACTIVE),
        .VFP        (VFP),
        .VSA        (VSA),
        .VBP        (VBP),
        .VIDEO_VIC  (VIDEO_VIC),
        .IIC_SCL_DIV(IIC_SCL_DIV)
    ) u_core_wrapper (
        .pixel_clk        (pixel_clk),
        .rst              (rst),
        .edid_read_trig   (edid_read_trig),
        .edid_read_valid  (edid_read_valid),
        .edid_read_data   (edid_read_data),
        .axis_user        (axis_user),
        .axis_valid       (axis_valid),
        .axis_last        (axis_last),
        .axis_data        (axis_data),
        .axis_ready       (axis_ready),
        .audio_valid      (audio_valid),
        .audio_left_data  (audio_left_data),
        .audio_right_data (audio_right_data),
        .acr_valid        (acr_valid),
        .acr_cts          (acr_cts),
        .acr_n            (acr_n),
        .video_locked     (video_locked),
        .ddc_scl          (ddc_scl),
        .ddc_sda          (ddc_sda),
        .ch0_tmds_data    (ch0_tmds_data),
        .ch1_tmds_data    (ch1_tmds_data),
        .ch2_tmds_data    (ch2_tmds_data),
        .clk_tmds_data    (clk_tmds_data)
    );

    hdmi_phy_wrapper #(
        .DEVICE("EG")
    ) u_eg_hdmi_phy (
        .I_pixel_clk        (pixel_clk),
        .I_serial_clk       (serial_clk),
        .I_rst              (rst),
        .I_tmds_channel_0   (ch0_tmds_data),
        .I_tmds_channel_1   (ch1_tmds_data),
        .I_tmds_channel_2   (ch2_tmds_data),
        .I_tmds_channel_clk (clk_tmds_data),
        .O_tmds_ch0_p       (tmds_ch0_p),
        .O_tmds_ch1_p       (tmds_ch1_p),
        .O_tmds_ch2_p       (tmds_ch2_p),
        .O_tmds_clk_p       (tmds_clk_p)
    );

endmodule
