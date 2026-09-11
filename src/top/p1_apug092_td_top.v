// ================================================================
// Module  : p1_apug092_td_top
// Purpose : P1-03B TD-only APUG092 external-video integration harness.
//
// Resolution policy (2026-09-10):
//   VIDEO_MODE = 0 : 1280x720 baseline used for P1-03B verification.
//   VIDEO_MODE = 1 : 1920x1080 compile-time profile reserved for later
//                    feasibility experiments only.  Selecting it here does
//                    NOT claim that EG4S20 can close the required HDMI PHY
//                    clock; P&R/PLL/board evidence is mandatory first.
//
// Why 720p is now the baseline:
//   The supplied APUG092 reference design instantiates the transmitter core
//   with 1280x720 timing.  The project therefore must not regress to the old
//   640x480 transport baseline.  P0's existing 640x480 framebuffer tests stay
//   frozen; this isolated HDMI harness is intentionally independent of them.
//
// IMPORTANT: this is NOT the HX4S20C final board top.
// The official APUG092 documentation requires:
//   serial clock = 5 * pixel clock
// and all APUG092 application interfaces operate in the pixel-clock domain.
// The bundled APUG092 reference PLL is PH1A-specific, so it is not reused on
// EG4S20.  This harness takes both clocks as explicit top-level inputs and
// proves vendor/core/PHY compile integration only.  P1-04 will replace these
// injected clocks with a TD5.6.2 EG PLL generated from the HX4S20C 50 MHz
// oscillator and will bind the official HDMI/DDC board pins.
//
// Active video path:
//   hdmi_test_pattern_line_provider
//       -> hdmi_video_adapter
//       -> apug092_tx_wrapper
//       -> official protected APUG092 core
//       -> official hdmi_phy_wrapper(DEVICE="EG")
//       -> EG_LOGIC_ODDR / TMDS positive outputs
// ================================================================

module p1_apug092_td_top #(
    parameter integer VIDEO_MODE = 0
) (
    input  wire        P1_PIXEL_CLK,
    input  wire        P1_SERIAL_CLK,
    input  wire        P1_RST_N,

    output wire        P1_VIDEO_LOCKED,
    output wire        P1_FRAME_DONE,
    output wire        P1_ADAPTER_ERROR,
    output wire        P1_PROVIDER_ERROR,
    output wire [15:0] P1_LINE_DEBUG,
    output wire [15:0] P1_PIXEL_DEBUG,

    output wire        P1_DDC_SCL,
    inout  wire        P1_DDC_SDA,

    output wire        P1_TMDS_CH0_P,
    output wire        P1_TMDS_CH1_P,
    output wire        P1_TMDS_CH2_P,
    output wire        P1_TMDS_CLK_P
);

    localparam integer MODE_720P60  = 0;
    localparam integer MODE_1080P60 = 1;

    // Supplied APUG092 reference design: 1280x720 timing.
    localparam integer HACTIVE = (VIDEO_MODE == MODE_1080P60) ? 1920 : 1280;
    localparam integer HFP     = (VIDEO_MODE == MODE_1080P60) ?   88 :  110;
    localparam integer HSA     = (VIDEO_MODE == MODE_1080P60) ?   44 :   40;
    localparam integer HBP     = (VIDEO_MODE == MODE_1080P60) ?  148 :  220;
    localparam integer VACTIVE = (VIDEO_MODE == MODE_1080P60) ? 1080 :  720;
    localparam integer VFP     = (VIDEO_MODE == MODE_1080P60) ?    4 :    5;
    localparam integer VSA     = (VIDEO_MODE == MODE_1080P60) ?    5 :    5;
    localparam integer VBP     = (VIDEO_MODE == MODE_1080P60) ?   36 :   20;

    // APUG092 user guide default for 1080p is VIC 16.  The supplied reference
    // source uses VIC 69 for its 1280x720 instance.  Keep both at this wrapper
    // boundary rather than baking them into project-owned protocol logic.
    localparam integer VIDEO_VIC = (VIDEO_MODE == MODE_1080P60) ? 16 : 69;

    wire rst = ~P1_RST_N;

    wire        lb_read_start;
    wire [15:0] lb_read_line_index;
    wire [15:0] lb_read_width;
    wire        lb_pixel_valid;
    wire [23:0] lb_pixel_data;
    wire        lb_line_done;
    wire        provider_busy;

    wire        axis_user;
    wire        axis_valid;
    wire        axis_last;
    wire [23:0] axis_data;
    wire        axis_ready;

    wire        edid_read_valid;
    wire [7:0]  edid_read_data;

    hdmi_test_pattern_line_provider #(
        .ACTIVE_WIDTH (HACTIVE),
        .ACTIVE_HEIGHT(VACTIVE)
    ) u_pattern_provider (
        .clk_pix         (P1_PIXEL_CLK),
        .rst_n           (P1_RST_N),
        .read_start      (lb_read_start),
        .read_line_index (lb_read_line_index),
        .read_width      (lb_read_width),
        .pixel_valid     (lb_pixel_valid),
        .pixel_data      (lb_pixel_data),
        .line_done       (lb_line_done),
        .busy            (provider_busy),
        .protocol_error  (P1_PROVIDER_ERROR)
    );

    hdmi_video_adapter #(
        .ACTIVE_WIDTH (HACTIVE),
        .ACTIVE_HEIGHT(VACTIVE)
    ) u_video_adapter (
        .clk_pix           (P1_PIXEL_CLK),
        .rst_n             (P1_RST_N),
        .enable            (1'b1),
        .lb_read_start     (lb_read_start),
        .lb_read_line_index(lb_read_line_index),
        .lb_read_width     (lb_read_width),
        .lb_pixel_valid    (lb_pixel_valid),
        .lb_pixel_data     (lb_pixel_data),
        .lb_line_done      (lb_line_done),
        .axis_user         (axis_user),
        .axis_valid        (axis_valid),
        .axis_last         (axis_last),
        .axis_data         (axis_data),
        .axis_ready        (axis_ready),
        .frame_done_pulse  (P1_FRAME_DONE),
        .protocol_error    (P1_ADAPTER_ERROR),
        .current_line      (P1_LINE_DEBUG),
        .current_pixel     (P1_PIXEL_DEBUG)
    );

    apug092_tx_wrapper #(
        .HACTIVE    (HACTIVE),
        .HFP        (HFP),
        .HSA        (HSA),
        .HBP        (HBP),
        .VACTIVE    (VACTIVE),
        .VFP        (VFP),
        .VSA        (VSA),
        .VBP        (VBP),
        .VIDEO_VIC  (VIDEO_VIC),
        .IIC_SCL_DIV(125)
    ) u_apug092_tx (
        .pixel_clk        (P1_PIXEL_CLK),
        .serial_clk       (P1_SERIAL_CLK),
        .rst              (rst),
        .edid_read_trig   (1'b0),
        .edid_read_valid  (edid_read_valid),
        .edid_read_data   (edid_read_data),
        .axis_user        (axis_user),
        .axis_valid       (axis_valid),
        .axis_last        (axis_last),
        .axis_data        (axis_data),
        .axis_ready       (axis_ready),
        .audio_valid      (1'b0),
        .audio_left_data  (24'd0),
        .audio_right_data (24'd0),
        .acr_valid        (1'b0),
        .acr_cts          (20'd0),
        .acr_n            (20'd0),
        .video_locked     (P1_VIDEO_LOCKED),
        .ddc_scl          (P1_DDC_SCL),
        .ddc_sda          (P1_DDC_SDA),
        .tmds_ch0_p       (P1_TMDS_CH0_P),
        .tmds_ch1_p       (P1_TMDS_CH1_P),
        .tmds_ch2_p       (P1_TMDS_CH2_P),
        .tmds_clk_p       (P1_TMDS_CLK_P)
    );

endmodule
