//============================================================
// P1-04C HX4S20C HDMI Board Baseline Top
//
// Board : HX4S20C / EG4S20BG256
// Output: HDMI_B
// Mode  : 640x480 @ 60Hz baseline
//
// Verified:
//   - TD5.6.2 synthesis/P&R/BitGen PASS
//   - Real board HDMI output PASS
//
// This module intentionally keeps the official HDMI baseline
// source. Later framebuffer integration replaces only u_source.
//============================================================

module p1_hx4s20c_hdmi_board_top (
    input  wire clk,

    output wire HDMI_D0_P,
    output wire HDMI_D1_P,
    output wire HDMI_D2_P,
    output wire HDMI_CLK_P,

    output wire HDMI_DDC_SCL,
    inout  wire HDMI_DDC_SDA
);

//------------------------------------------------------------
// Clock generation
// 50MHz -> 25MHz pixel clock
//        -> 125MHz serial clock
//------------------------------------------------------------

wire pixel_clk;
wire serial_clk;
wire pll_lock;

p1_hdmi_pll_50m_25_125 u_hdmi_pll (
    .refclk_50m (clk),
    .reset      (1'b0),
    .lock       (pll_lock),
    .pixel_clk  (pixel_clk),
    .serial_clk (serial_clk)
);


//------------------------------------------------------------
// HDMI reset sequencing
// Hold reset after PLL lock (~20ms)
//------------------------------------------------------------

reg [19:0] rst_cnt;
reg        rst_all;

initial begin
    rst_cnt = 20'd0;
    rst_all = 1'b1;
end

always @(posedge clk) begin
    if (!pll_lock) begin
        rst_cnt <= 20'd0;
        rst_all <= 1'b1;
    end
    else if (rst_cnt < 20'd1000000) begin
        rst_cnt <= rst_cnt + 1'b1;
        rst_all <= 1'b1;
    end
    else begin
        rst_all <= 1'b0;
    end
end


//------------------------------------------------------------
// RGB888 AXIS video source
//------------------------------------------------------------

wire        axis_user;
wire        axis_valid;
wire        axis_last;
wire        axis_ready;
wire [23:0] axis_data;

hdmi_official_baseline_source u_video_source (
    .clk_pix    (pixel_clk),
    .rst        (rst_all),

    .axis_user  (axis_user),
    .axis_valid (axis_valid),
    .axis_last  (axis_last),
    .axis_data  (axis_data)
);


//------------------------------------------------------------
// EDID trigger
// Match official lab_ex4_tf startup behavior
//------------------------------------------------------------

reg [16:0] edid_cnt;
reg        edid_trig;
reg        edid_done;

always @(posedge pixel_clk or posedge rst_all) begin
    if (rst_all) begin
        edid_cnt  <= 17'd0;
        edid_trig <= 1'b0;
        edid_done <= 1'b0;
    end
    else begin
        edid_trig <= 1'b0;

        if (!edid_done) begin
            if (edid_cnt == 17'd100000) begin
                edid_trig <= 1'b1;
                edid_done <= 1'b1;
            end
            else begin
                edid_cnt <= edid_cnt + 1'b1;
            end
        end
    end
end


//------------------------------------------------------------
// APUG092 HDMI transmitter + EG PHY
//------------------------------------------------------------

wire       edid_valid_unused;
wire [7:0] edid_data_unused;
wire       video_locked_unused;

apug092_tx_wrapper #(
    .HACTIVE   (640),
    .HFP       (16),
    .HSA       (96),
    .HBP       (48),

    .VACTIVE   (480),
    .VFP       (10),
    .VSA       (2),
    .VBP       (33),

    .VIDEO_VIC (1),
    .IIC_SCL_DIV(250)
)
u_apug092_tx (
    .pixel_clk(pixel_clk),
    .serial_clk(serial_clk),
    .rst(rst_all),

    .edid_read_trig (edid_trig),
    .edid_read_valid(edid_valid_unused),
    .edid_read_data (edid_data_unused),

    .axis_user (axis_user),
    .axis_valid(axis_valid),
    .axis_last (axis_last),
    .axis_data (axis_data),
    .axis_ready(axis_ready),

    .audio_valid    (1'b0),
    .audio_left_data(24'd0),
    .audio_right_data(24'd0),
    .acr_valid      (1'b0),
    .acr_cts        (20'd0),
    .acr_n          (20'd0),

    .video_locked(video_locked_unused),

    .ddc_scl(HDMI_DDC_SCL),
    .ddc_sda(HDMI_DDC_SDA),

    .tmds_ch0_p(HDMI_D0_P),
    .tmds_ch1_p(HDMI_D1_P),
    .tmds_ch2_p(HDMI_D2_P),
    .tmds_clk_p(HDMI_CLK_P)
);

endmodule
