// ================================================================
// Module  : p1_hx4s20c_hdmi_smoke_top
// Purpose : P1-04A board-oriented 1280x720 HDMI smoke-test top.
//
// This is the first project top that starts from the HX4S20C 50 MHz board
// oscillator instead of injected pixel/serial clocks. It intentionally uses
// the synthesizable vertical-color-bar line provider, not SDRAM/TF, so first
// HDMI bring-up isolates clock/core/PHY/pin issues from the media pipeline.
//
// Active path:
//   50 MHz board clock
//        -> p1_hdmi_pll_50m (75 MHz pixel, 375 MHz serial@90deg)
//        -> hdmi_test_pattern_line_provider
//        -> hdmi_video_adapter
//        -> APUG092 protected transmitter
//        -> official hdmi_phy_wrapper(DEVICE="EG")
//        -> HX4S20C HDMI outputs (pins bound only in P1-04B ADC)
//
// No push-button reset is used in this smoke top. This is deliberate: the
// currently available conversation artifacts do not contain the HX4S20C
// official lab_ex4_tf ADC/pin file, and the user has observed KEY1/KEY2 may
// be swapped in that sample. Reset release is therefore driven only by PLL
// lock, avoiding an unverified key assignment during first HDMI bring-up.
// ================================================================

module p1_hx4s20c_hdmi_smoke_top (
    input  wire I_CLK_50M,

    output wire O_DDC_SCL,
    inout  wire IO_DDC_SDA,

    output wire O_TMDS_CH0_P,
    output wire O_TMDS_CH1_P,
    output wire O_TMDS_CH2_P,
    output wire O_TMDS_CLK_P,

    // Debug/status. P1-04B may map these to board LEDs after importing the
    // official board ADC. They are intentionally kept visible for TD reports.
    output wire O_PLL_LOCK,
    output wire O_VIDEO_LOCKED,
    output wire O_ADAPTER_ERROR,
    output wire O_PROVIDER_ERROR,
    output wire O_FRAME_HEARTBEAT
);

    localparam integer HACTIVE = 1280;
    localparam integer HFP     = 110;
    localparam integer HSA     = 40;
    localparam integer HBP     = 220;
    localparam integer VACTIVE = 720;
    localparam integer VFP     = 5;
    localparam integer VSA     = 5;
    localparam integer VBP     = 20;
    localparam integer VIDEO_VIC = 69;

    wire pixel_clk;
    wire serial_clk;
    wire pll_lock;

    // Do not hold the PLL itself in reset. This follows the vendor reference
    // top's power-up style; its lock output becomes our asynchronous reset
    // qualification for project-owned pixel-domain logic.
    p1_hdmi_pll_50m u_hdmi_pll (
        .refclk_50m(I_CLK_50M),
        .reset     (1'b0),
        .lock      (pll_lock),
        .pixel_clk (pixel_clk),
        .serial_clk(serial_clk)
    );

    // Project-owned logic gets a delayed, synchronous release in pixel_clk.
    // The protected APUG092/PHY reset below remains directly lock-qualified,
    // matching the vendor reference behavior more closely.
    wire logic_rst_n;
    reset_gen #(
        .RST_CLKS(256)
    ) u_pixel_reset (
        .clk        (pixel_clk),
        .async_rst_n(pll_lock),
        .sync_rst_n (logic_rst_n)
    );

    wire vendor_rst = ~pll_lock;

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

    wire        frame_done;
    wire [15:0] line_debug;
    wire [15:0] pixel_debug;

    wire        edid_read_valid;
    wire [7:0]  edid_read_data;

    hdmi_test_pattern_line_provider #(
        .ACTIVE_WIDTH (HACTIVE),
        .ACTIVE_HEIGHT(VACTIVE)
    ) u_pattern_provider (
        .clk_pix        (pixel_clk),
        .rst_n          (logic_rst_n),
        .read_start     (lb_read_start),
        .read_line_index(lb_read_line_index),
        .read_width     (lb_read_width),
        .pixel_valid    (lb_pixel_valid),
        .pixel_data     (lb_pixel_data),
        .line_done      (lb_line_done),
        .busy           (provider_busy),
        .protocol_error (O_PROVIDER_ERROR)
    );

    hdmi_video_adapter #(
        .ACTIVE_WIDTH (HACTIVE),
        .ACTIVE_HEIGHT(VACTIVE)
    ) u_video_adapter (
        .clk_pix           (pixel_clk),
        .rst_n             (logic_rst_n),
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
        .frame_done_pulse  (frame_done),
        .protocol_error    (O_ADAPTER_ERROR),
        .current_line      (line_debug),
        .current_pixel     (pixel_debug)
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
        .pixel_clk        (pixel_clk),
        .serial_clk       (serial_clk),
        .rst              (vendor_rst),
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
        .video_locked     (O_VIDEO_LOCKED),
        .ddc_scl          (O_DDC_SCL),
        .ddc_sda          (IO_DDC_SDA),
        .tmds_ch0_p       (O_TMDS_CH0_P),
        .tmds_ch1_p       (O_TMDS_CH1_P),
        .tmds_ch2_p       (O_TMDS_CH2_P),
        .tmds_clk_p       (O_TMDS_CLK_P)
    );

    reg frame_heartbeat;
    always @(posedge pixel_clk or negedge logic_rst_n) begin
        if (!logic_rst_n)
            frame_heartbeat <= 1'b0;
        else if (frame_done)
            frame_heartbeat <= ~frame_heartbeat;
    end

    assign O_PLL_LOCK        = pll_lock;
    assign O_FRAME_HEARTBEAT = frame_heartbeat;

endmodule
