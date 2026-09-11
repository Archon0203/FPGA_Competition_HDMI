// ================================================================
// Module  : apug092_core_wrapper
// Purpose : Project-owned stable wrapper around the official protected
//           APUG092 HDMI1.4b transmitter core.
//
// Vendor source is kept read-only under src/vendor/anlogic/apug092/.
// This wrapper contains no self-written HDMI/TMDS protocol logic; it only
// binds parameters and presents a stable project interface for P1/P2.
// ================================================================

module apug092_core_wrapper #(
    parameter integer HACTIVE   = 1280,
    parameter integer HFP       = 110,
    parameter integer HSA       = 40,
    parameter integer HBP       = 220,
    parameter integer VACTIVE   = 720,
    parameter integer VFP       = 5,
    parameter integer VSA       = 5,
    parameter integer VBP       = 20,
    // The supplied APUG092 reference design uses VIC 69 together with its
    // 1280x720 timing instance.  Keep this project-side and configurable;
    // the vendor user guide says VIC is defined by CTA-861.
    parameter integer VIDEO_VIC = 69,
    parameter integer IIC_SCL_DIV = 125
) (
    input  wire        pixel_clk,
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

    output wire [9:0]  ch0_tmds_data,
    output wire [9:0]  ch1_tmds_data,
    output wire [9:0]  ch2_tmds_data,
    output wire [9:0]  clk_tmds_data
);

    localparam integer HTOTAL = HACTIVE + HFP + HSA + HBP;
    localparam integer VTOTAL = VACTIVE + VFP + VSA + VBP;

    hdmi_1_4b_transmitter_core_wrapper #(
        .DEVICE            ("EG"),
        .HTOTAL            (HTOTAL),
        .HSA               (HSA),
        .HFP               (HFP),
        .HBP               (HBP),
        .HACTIVE           (HACTIVE),
        .VTOTAL            (VTOTAL),
        .VSA               (VSA),
        .VFP               (VFP),
        .VBP               (VBP),
        .VACTIVE           (VACTIVE),
        .VIDEO_TPG         ("Disable"),
        .VIDEO_FORMAT      ("RGB"),
        .VIDEO_VIC         (VIDEO_VIC),
        .AUDIO_SAMPLE_RATE ("48K"),
        .IIC_SCL_DIV       (IIC_SCL_DIV)
    ) u_apug092_core (
        .I_pixel_clk        (pixel_clk),
        .I_rst              (rst),
        .I_edid_read_trig   (edid_read_trig),
        .O_edid_read_valid  (edid_read_valid),
        .O_edid_read_data   (edid_read_data),
        .I_axis_s_user      (axis_user),
        .I_axis_s_valid     (axis_valid),
        .I_axis_s_last      (axis_last),
        .I_axis_s_data      (axis_data),
        .O_axis_s_ready     (axis_ready),
        .I_audio_valid      (audio_valid),
        .I_audio_left_data  (audio_left_data),
        .I_audio_right_data (audio_right_data),
        .I_acr_valid        (acr_valid),
        .I_acr_cts          (acr_cts),
        .I_acr_n            (acr_n),
        .O_video_locked     (video_locked),
        .O_ddc_scl          (ddc_scl),
        .IO_ddc_sda         (ddc_sda),
        .O_ch0_tmds_data    (ch0_tmds_data),
        .O_ch1_tmds_data    (ch1_tmds_data),
        .O_ch2_tmds_data    (ch2_tmds_data),
        .O_clk_tmds_data    (clk_tmds_data)
    );

endmodule
