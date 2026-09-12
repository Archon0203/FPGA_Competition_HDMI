// ================================================================
// P1-05A HX4S20C SDRAM -> HDMI board top
//
// Goal:
//   Prove the real EG4S20 internal SDRAM framebuffer can feed the already
//   board-proven P1-04C HDMI_B golden boundary without changing its PLL, ADC,
//   APUG092/PHY, reset hold, EDID trigger, or 640x480 timing.
//
// Bring-up behavior:
//   1) P1-04C eight-color bars remain active as a safe fallback.
//   2) APUG011 initializes the internal 2M x 32 SDRAM at 150 MHz.
//   3) A deterministic 640x480 test frame is written into SDRAM.
//   4) line_prefetcher + ping-pong line buffer read it through an explicit
//      25 MHz <-> 150 MHz CDC bridge.
//   5) At a frame boundary, RGB data switches to SDRAM only after two lines
//      have successfully prefetched. APUG092 user/valid/last continue to come
//      from the P1-04C official free-running source.
//
// Expected SDRAM image:
//   white border;
//   TL red, TR green, BL blue, BR yellow;
//   magenta vertical center bar + cyan horizontal center bar.
// ================================================================

module p1_hx4s20c_sdram_hdmi_top (
    input  wire clk,

    output wire HDMI_D0_P,
    output wire HDMI_D1_P,
    output wire HDMI_D2_P,
    output wire HDMI_CLK_P,

    output wire HDMI_DDC_SCL,
    inout  wire HDMI_DDC_SDA
);

    localparam integer HACTIVE = 640;
    localparam integer HFP     = 16;
    localparam integer HSA     = 96;
    localparam integer HBP     = 48;
    localparam integer VACTIVE = 480;
    localparam integer VFP     = 10;
    localparam integer VSA     = 2;
    localparam integer VBP     = 33;

    // ============================================================
    // P1-04C golden HDMI clocks: 50 MHz -> 25 MHz / 125 MHz
    // ============================================================
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
    // P1-04C golden HDMI reset sequencing (~20 ms after PLL lock)
    // ============================================================
    reg [19:0] hdmi_rst_cnt;
    reg        hdmi_rst;

    initial begin
        hdmi_rst_cnt = 20'd0;
        hdmi_rst     = 1'b1;
    end

    always @(posedge clk) begin
        if (!hdmi_pll_lock) begin
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

    // ============================================================
    // APUG011 SDRAM clocks: reuse the already-closed official P1-02 PLL
    // 25 MHz pixel clock -> 150 MHz 0 deg / 150 MHz 180 deg
    // ============================================================
    wire sdr_clk_unused_12m5;
    wire sdr_clk_150m;
    wire sdr_clk_150m_shift;
    wire sdr_pll_lock;

    clk_pll u_sdram_pll (
        .refclk  (pixel_clk),
        .reset   (!hdmi_pll_lock),
        .extlock (sdr_pll_lock),
        .clk0_out(sdr_clk_unused_12m5),
        .clk1_out(sdr_clk_150m),
        .clk2_out(sdr_clk_150m_shift)
    );

    wire sdr_rst_n = sdr_pll_lock && hdmi_pll_lock;

    // ============================================================
    // Fixed framebuffer pattern writer (SDRAM domain)
    // ============================================================
    reg  pattern_start;
    reg  pattern_started;
    reg  frame_ready_sdr;
    reg  frame_write_error;

    wire        pattern_wr_valid;
    wire [20:0] pattern_wr_addr;
    wire [31:0] pattern_wr_data;
    wire        pattern_wr_ready;
    wire        pattern_busy;
    wire        pattern_done;
    wire        pattern_ok;
    wire        pattern_protocol_error;

    p1_framebuffer_pattern_writer #(
        .FRAME_WIDTH        (HACTIVE),
        .FRAME_HEIGHT       (VACTIVE),
        .FRAME_STRIDE_WORDS (HACTIVE),
        .FRAME_BASE         (21'd0),
        .BORDER_PIXELS      (8),
        .CENTER_BAR_PIXELS  (16)
    ) u_pattern_writer (
        .clk            (sdr_clk_150m),
        .rst_n          (sdr_rst_n),
        .start          (pattern_start),
        .mem_wr_valid   (pattern_wr_valid),
        .mem_wr_addr    (pattern_wr_addr),
        .mem_wr_data    (pattern_wr_data),
        .mem_wr_ready   (pattern_wr_ready),
        .busy           (pattern_busy),
        .done           (pattern_done),
        .ok             (pattern_ok),
        .protocol_error (pattern_protocol_error),
        .x_debug        (),
        .y_debug        ()
    );

    // ============================================================
    // P1-05A framebuffer read pipeline (25 MHz display domain)
    // ============================================================
    wire        pipeline_rd_valid;
    wire [20:0] pipeline_rd_addr;
    wire        pipeline_rd_ready;
    wire        pipeline_rvalid;
    wire [31:0] pipeline_rdata;

    wire        fb_pixel_valid;
    wire [23:0] fb_pixel_data;
    wire        fb_frame_boundary;
    wire        fb_warm_ready;
    wire        frame_ready_pix;
    wire        fb_underflow_sticky;
    wire        pipeline_protocol_error;

    p1_sdram_hdmi_pipeline #(
        .FRAME_WIDTH     (HACTIVE),
        .FRAME_HEIGHT    (VACTIVE),
        .FRAME_STRIDE    (HACTIVE),
        .FRAME_BASE      (21'd0),
        .MAX_OUTSTANDING (8),
        .HFP             (HFP),
        .HSA             (HSA),
        .HBP             (HBP),
        .VFP             (VFP),
        .VSA             (VSA),
        .VBP             (VBP)
    ) u_sdram_hdmi_pipeline (
        .pix_clk          (pixel_clk),
        .pix_rst_n        (pix_rst_n),
        .sdr_clk          (sdr_clk_150m),
        .sdr_rst_n        (sdr_rst_n),
        .frame_ready_sdr  (frame_ready_sdr),
        .sdr_mem_rd_valid (pipeline_rd_valid),
        .sdr_mem_rd_addr  (pipeline_rd_addr),
        .sdr_mem_rd_ready (pipeline_rd_ready),
        .sdr_mem_rvalid   (pipeline_rvalid),
        .sdr_mem_rdata    (pipeline_rdata),
        .fb_pixel_valid   (fb_pixel_valid),
        .fb_pixel_data    (fb_pixel_data),
        .frame_boundary   (fb_frame_boundary),
        .warm_ready       (fb_warm_ready),
        .frame_ready_pix  (frame_ready_pix),
        .underflow_sticky (fb_underflow_sticky),
        .protocol_error   (pipeline_protocol_error)
    );

    // ============================================================
    // SDRAM arbiter -> adapter -> official APUG011 -> internal SDRAM
    // ============================================================
    wire        mem_wr_valid;
    wire [20:0] mem_wr_addr;
    wire [31:0] mem_wr_data;
    wire        mem_wr_ready;
    wire        mem_rd_valid;
    wire [20:0] mem_rd_addr;
    wire        mem_rd_ready;
    wire        mem_rvalid;
    wire [31:0] mem_rdata;

    wire        arb_protocol_error;

    sdram_arbiter #(
        .MAX_READ_OUTSTANDING(8)
    ) u_sdram_arbiter (
        .clk                     (sdr_clk_150m),
        .rst_n                   (sdr_rst_n),

        .wr_valid                (pattern_wr_valid),
        .wr_addr                 (pattern_wr_addr),
        .wr_data                 (pattern_wr_data),
        .wr_ready                (pattern_wr_ready),

        .rd_valid                (pipeline_rd_valid),
        .rd_addr                 (pipeline_rd_addr),
        .rd_ready                (pipeline_rd_ready),
        .rd_rvalid               (pipeline_rvalid),
        .rd_rdata                (pipeline_rdata),

        .mem_wr_valid            (mem_wr_valid),
        .mem_wr_addr             (mem_wr_addr),
        .mem_wr_data             (mem_wr_data),
        .mem_wr_ready            (mem_wr_ready),
        .mem_rd_valid            (mem_rd_valid),
        .mem_rd_addr             (mem_rd_addr),
        .mem_rd_ready            (mem_rd_ready),
        .mem_rvalid              (mem_rvalid),
        .mem_rdata               (mem_rdata),

        .protocol_error          (arb_protocol_error),
        .contention_seen         (),
        .rd_outstanding_debug    (),
        .read_accept_count_debug (),
        .write_accept_count_debug()
    );

    wire        sdram_init_done;
    wire        sdram_init_ref_vld;
    wire        sdram_busy;
    wire        app_ref_req;
    wire        app_wr_en;
    wire [20:0] app_wr_addr;
    wire [31:0] app_wr_din;
    wire [3:0]  app_wr_dm;
    wire        app_rd_en;
    wire [20:0] app_rd_addr;
    wire        sdr_rd_en;
    wire [31:0] sdr_rd_dout;
    wire        sdram_ready_for_traffic;
    wire        adapter_protocol_error;
    wire        adapter_provider_fault;

    // P1-05A uses a sequential-read optimized adapter here.  The frozen
    // P1-02 sdram_adapter remains in the repository and keeps its regression
    // status; it is intentionally not modified for framebuffer bandwidth.
    p1_sdram_cached_adapter u_sdram_adapter (
        .clk                     (sdr_clk_150m),
        .rst_n                   (sdr_rst_n),
        .mem_wr_valid            (mem_wr_valid),
        .mem_wr_addr             (mem_wr_addr),
        .mem_wr_data             (mem_wr_data),
        .mem_wr_ready            (mem_wr_ready),
        .mem_rd_valid            (mem_rd_valid),
        .mem_rd_addr             (mem_rd_addr),
        .mem_rd_ready            (mem_rd_ready),
        .mem_rvalid              (mem_rvalid),
        .mem_rdata               (mem_rdata),
        .App_wr_en               (app_wr_en),
        .App_wr_addr             (app_wr_addr),
        .App_wr_din              (app_wr_din),
        .App_wr_dm               (app_wr_dm),
        .App_rd_en               (app_rd_en),
        .App_rd_addr             (app_rd_addr),
        .Sdr_rd_en               (sdr_rd_en),
        .Sdr_rd_dout             (sdr_rd_dout),
        .Sdr_init_done           (sdram_init_done),
        .Sdr_init_ref_vld        (sdram_init_ref_vld),
        .Sdr_busy                (sdram_busy),
        .App_ref_req             (app_ref_req),
        .ready_for_traffic       (sdram_ready_for_traffic),
        .protocol_error          (adapter_protocol_error),
        .provider_fault          (adapter_provider_fault),
        .contention_seen         (),
        .read_outstanding_debug  (),
        .read_accept_count_debug (),
        .write_accept_count_debug(),
        .app_read_word_count_debug (),
        .app_write_word_count_debug()
    );

    wire        SDRAM_CLK;
    wire        SDR_RAS;
    wire        SDR_CAS;
    wire        SDR_WE;
    wire [1:0]  SDR_BA;
    wire [10:0] SDR_ADDR;
    wire [3:0]  SDR_DM;
    wire [31:0] SDR_DQ;

    apug011_core_wrapper u_apug011 (
        .Sdr_clk          (sdr_clk_150m),
        .Sdr_clk_sft      (sdr_clk_150m_shift),
        .rst_n            (sdr_rst_n),
        .Sdr_init_done    (sdram_init_done),
        .Sdr_init_ref_vld (sdram_init_ref_vld),
        .Sdr_busy         (sdram_busy),
        .App_ref_req      (app_ref_req),
        .App_wr_en        (app_wr_en),
        .App_wr_addr      (app_wr_addr),
        .App_wr_dm        (app_wr_dm),
        .App_wr_din       (app_wr_din),
        .App_rd_en        (app_rd_en),
        .App_rd_addr      (app_rd_addr),
        .Sdr_rd_en        (sdr_rd_en),
        .Sdr_rd_dout      (sdr_rd_dout),
        .SDRAM_CLK        (SDRAM_CLK),
        .SDR_RAS          (SDR_RAS),
        .SDR_CAS          (SDR_CAS),
        .SDR_WE           (SDR_WE),
        .SDR_BA           (SDR_BA),
        .SDR_ADDR         (SDR_ADDR),
        .SDR_DM           (SDR_DM),
        .SDR_DQ           (SDR_DQ)
    );

    EG_PHY_SDRAM_2M_32 u_internal_sdram (
        .clk   (SDRAM_CLK),
        .ras_n (SDR_RAS),
        .cas_n (SDR_CAS),
        .we_n  (SDR_WE),
        .addr  (SDR_ADDR),
        .ba    (SDR_BA),
        .dq    (SDR_DQ),
        .cs_n  (1'b0),
        .dm0   (SDR_DM[0]),
        .dm1   (SDR_DM[1]),
        .dm2   (SDR_DM[2]),
        .dm3   (SDR_DM[3]),
        .cke   (1'b1)
    );

    // Launch the framebuffer initialization once APUG011 is ready.  A failed
    // write intentionally does not retry silently; the P1-04C bars remain on
    // screen and the failure stays observable through implementation/debug.
    always @(posedge sdr_clk_150m or negedge sdr_rst_n) begin
        if (!sdr_rst_n) begin
            pattern_start    <= 1'b0;
            pattern_started  <= 1'b0;
            frame_ready_sdr  <= 1'b0;
            frame_write_error<= 1'b0;
        end else begin
            pattern_start <= 1'b0;

            if (!pattern_started && sdram_ready_for_traffic) begin
                pattern_start   <= 1'b1;
                pattern_started <= 1'b1;
            end

            if (pattern_done) begin
                if (pattern_ok)
                    frame_ready_sdr <= 1'b1;
                else
                    frame_write_error <= 1'b1;
            end

            if (pattern_protocol_error ||
                arb_protocol_error ||
                adapter_protocol_error ||
                adapter_provider_fault)
                frame_write_error <= 1'b1;
        end
    end

    // ============================================================
    // P1-04C free-running AXIS timing source remains the APUG092 authority.
    // Only RGB data is switched to SDRAM at a frame boundary.
    // ============================================================
    wire        baseline_axis_user;
    wire        baseline_axis_valid;
    wire        baseline_axis_last;
    wire [23:0] baseline_axis_data;
    wire        axis_ready;

    hdmi_official_baseline_source #(
        .HACTIVE(HACTIVE),
        .HFP    (HFP),
        .HSA    (HSA),
        .HBP    (HBP),
        .VACTIVE(VACTIVE),
        .VFP    (VFP),
        .VSA    (VSA),
        .VBP    (VBP)
    ) u_golden_video_timing (
        .clk_pix    (pixel_clk),
        .rst        (hdmi_rst),
        .axis_user  (baseline_axis_user),
        .axis_valid (baseline_axis_valid),
        .axis_last  (baseline_axis_last),
        .axis_data  (baseline_axis_data)
    );

    // ============================================================
    // P1-05A board bring-up diagnostics
    //
    // P1-04C proved that the HDMI boundary itself is good.  If the board does
    // not switch away from the fallback image, the most useful next question
    // is therefore which SDRAM/framebuffer milestone was never reached.
    //
    // Synchronize the sticky/monotonic SDR-domain milestones into pixel_clk
    // and encode the current startup stage as a full-screen color until the
    // framebuffer is enabled.  This adds no board pins and does not modify
    // PLL/APUG092/PHY/ADC behavior.
    //
    //   WHITE   : SDRAM PLL has not locked
    //   ORANGE  : SDRAM PLL locked; APUG011 has not started framebuffer write
    //   YELLOW  : framebuffer write started but has not completed
    //   RED     : SDRAM writer/backend sticky error
    //   CYAN    : frame written; frame_ready CDC has not arrived in pixel domain
    //   MAGENTA : display pipeline protocol error
    //   BLUE    : frame ready; waiting for two prefetched warm-up lines
    //   GREEN   : all prerequisites ready; waiting for safe frame boundary
    //   FB DATA : framebuffer scanout active
    // ============================================================
    reg sdr_pll_lock_pix_ff1;
    reg sdr_pll_lock_pix_ff2;
    reg pattern_started_pix_ff1;
    reg pattern_started_pix_ff2;
    reg frame_ready_sdr_pix_ff1;
    reg frame_ready_sdr_pix_ff2;
    reg frame_write_error_pix_ff1;
    reg frame_write_error_pix_ff2;

    always @(posedge pixel_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            sdr_pll_lock_pix_ff1        <= 1'b0;
            sdr_pll_lock_pix_ff2        <= 1'b0;
            pattern_started_pix_ff1     <= 1'b0;
            pattern_started_pix_ff2     <= 1'b0;
            frame_ready_sdr_pix_ff1     <= 1'b0;
            frame_ready_sdr_pix_ff2     <= 1'b0;
            frame_write_error_pix_ff1   <= 1'b0;
            frame_write_error_pix_ff2   <= 1'b0;
        end else begin
            sdr_pll_lock_pix_ff1        <= sdr_pll_lock;
            sdr_pll_lock_pix_ff2        <= sdr_pll_lock_pix_ff1;
            pattern_started_pix_ff1     <= pattern_started;
            pattern_started_pix_ff2     <= pattern_started_pix_ff1;
            frame_ready_sdr_pix_ff1     <= frame_ready_sdr;
            frame_ready_sdr_pix_ff2     <= frame_ready_sdr_pix_ff1;
            frame_write_error_pix_ff1   <= frame_write_error;
            frame_write_error_pix_ff2   <= frame_write_error_pix_ff1;
        end
    end

    reg use_framebuffer;

    always @(posedge pixel_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            use_framebuffer <= 1'b0;
        end else if (fb_frame_boundary &&
                     frame_ready_pix &&
                     fb_warm_ready &&
                     !pipeline_protocol_error &&
                     !frame_write_error_pix_ff2) begin
            use_framebuffer <= 1'b1;
        end
    end

    // Gray is a deliberate post-switch diagnostic: use_framebuffer has latched
    // high but the line-buffer pixel cadence is missing.  Keeping this color
    // distinct from the ORANGE pre-switch state makes the board result
    // unambiguous.
    wire [23:0] framebuffer_axis_data = fb_pixel_valid
                                      ? fb_pixel_data
                                      : 24'h808080;

    reg [23:0] startup_diag_data;

    always @(*) begin
        if (!sdr_pll_lock_pix_ff2)
            startup_diag_data = 24'hFFFFFF; // white: SDR PLL not locked
        else if (!pattern_started_pix_ff2)
            startup_diag_data = 24'hFF8000; // orange: APUG011/write not started
        else if (frame_write_error_pix_ff2)
            startup_diag_data = 24'hFF0000; // red: write/backend error
        else if (!frame_ready_sdr_pix_ff2)
            startup_diag_data = 24'hFFFF00; // yellow: framebuffer write in progress
        else if (!frame_ready_pix)
            startup_diag_data = 24'h00FFFF; // cyan: frame_ready CDC pending
        else if (pipeline_protocol_error)
            startup_diag_data = 24'hFF00FF; // magenta: read/display protocol error
        else if (!fb_warm_ready)
            startup_diag_data = 24'h0000FF; // blue: line warm-up pending
        else
            startup_diag_data = 24'h00FF00; // green: waiting safe frame boundary
    end

    wire [23:0] axis_data = use_framebuffer
                          ? framebuffer_axis_data
                          : startup_diag_data;

    // ============================================================
    // P1-04C EDID trigger: unchanged
    // ============================================================
    reg [16:0] edid_cnt;
    reg        edid_trig;
    reg        edid_done;

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
                    edid_cnt <= edid_cnt + 17'd1;
                end
            end
        end
    end

    // ============================================================
    // P1-04C APUG092 transmitter / EG PHY: unchanged
    // ============================================================
    wire       edid_valid_unused;
    wire [7:0] edid_data_unused;
    wire       video_locked_unused;

    apug092_tx_wrapper #(
        .HACTIVE    (HACTIVE),
        .HFP        (HFP),
        .HSA        (HSA),
        .HBP        (HBP),
        .VACTIVE    (VACTIVE),
        .VFP        (VFP),
        .VSA        (VSA),
        .VBP        (VBP),
        .VIDEO_VIC  (1),
        .IIC_SCL_DIV(250)
    ) u_apug092_tx (
        .pixel_clk       (pixel_clk),
        .serial_clk      (serial_clk),
        .rst             (hdmi_rst),
        .edid_read_trig  (edid_trig),
        .edid_read_valid (edid_valid_unused),
        .edid_read_data  (edid_data_unused),
        .axis_user       (baseline_axis_user),
        .axis_valid      (baseline_axis_valid),
        .axis_last       (baseline_axis_last),
        .axis_data       (axis_data),
        .axis_ready      (axis_ready),
        .audio_valid     (1'b0),
        .audio_left_data (24'd0),
        .audio_right_data(24'd0),
        .acr_valid       (1'b0),
        .acr_cts         (20'd0),
        .acr_n           (20'd0),
        .video_locked    (video_locked_unused),
        .ddc_scl         (HDMI_DDC_SCL),
        .ddc_sda         (HDMI_DDC_SDA),
        .tmds_ch0_p      (HDMI_D0_P),
        .tmds_ch1_p      (HDMI_D1_P),
        .tmds_ch2_p      (HDMI_D2_P),
        .tmds_clk_p      (HDMI_CLK_P)
    );

    // Keep these diagnostics live in the design even though P1-05A does not
    // bind extra board pins yet. TD reports/netlists can inspect them.
    wire p1_05a_error = frame_write_error ||
                        pipeline_protocol_error ||
                        (use_framebuffer && fb_underflow_sticky);
    wire p1_05a_active = use_framebuffer && !p1_05a_error;

endmodule
