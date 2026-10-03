// ================================================================
// M2 Slave TF -> SDRAM -> HDMI board candidate
//
// The 25 MHz TF/FAT32/BMP service writes a 640x480 frame through an
// asynchronous FIFO into the 150 MHz APUG011 SDRAM adapter. HDMI switches
// at a frame boundary after the final write completes and line prefetch
// warms up. PLL, APUG092 PHY and timing follow the proven P1-05A path.
// ================================================================

module m2_slave_tf_hdmi_top (
    input  wire clk,
    input  wire rst_n,
    input  wire uart_rx,
    output wire uart_tx,
    output wire [3:0] led,

    // Eight dual-color LED group / nixie shared nets.  The board schematic
    // powers the LED group from LEDVCC through 470-ohm resistors, so DIG/SEL
    // are active-low LED cathodes.  Keep SEL high (off) and use DIG0..7 as
    // a full-byte diagnostic display.
    output wire [7:0] diag_led_n,
    output wire [7:0] diag_sel_n,

    output wire sd_ncs,
    output wire sd_sclk,
    output wire sd_mosi,
    input  wire sd_miso,

    output wire HDMI_D0_P,
    output wire HDMI_D1_P,
    output wire HDMI_D2_P,
    output wire HDMI_CLK_P,

    output wire HDMI_DDC_SCL,
    inout  wire HDMI_DDC_SDA
);

    // M2 keeps the board-proven framed UART as the control/status plane.
    // Raw pixels never use this 115200-baud link.

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

    wire sdr_rst_n = sdr_pll_lock && hdmi_pll_lock && rst_n;

    // ============================================================
    // TF media service and framebuffer writer (25 MHz media domain)
    // ============================================================
    reg  media_cmd_valid;
    reg  [7:0] media_cmd_image_id;
    reg        media_load_toggle;
    reg  frame_ready_sdr;
    reg  frame_write_error;

    wire        media_wr_valid;
    wire [20:0] media_wr_addr;
    wire [31:0] media_wr_data;
    wire        media_wr_ready;
    wire        media_busy;
    wire        media_done;
    wire        media_error;
    wire [7:0]  media_error_code;
    wire [7:0]  media_sector_error_detail;
    wire        media_cmd_ready;
    wire        media_catalog_valid;
    wire [7:0]  media_catalog_count;
    wire        sdr_fenced;
    wire        sdr_media_wr_valid;
    wire [20:0] sdr_media_wr_addr;
    wire [31:0] sdr_media_wr_data;
    wire        sdr_media_wr_ready;
    wire        mem_wr_ready;
    wire        media_rst_n = pix_rst_n && rst_n;
    reg         media_started;
    reg         media_load_requested;
    reg         media_failed;
    reg  [7:0]  media_failure_code;
    reg  [7:0]  media_sector_failure_detail;
    reg         media_succeeded;
    reg         media_scan_start;
    reg         media_retrying;
    reg  [24:0] media_retry_count;
    // Standalone fallback is intentionally one-shot.  It gets image 0 onto
    // HDMI when no Master is connected, but must never re-open image 0 after
    // a completed load and fight the remote NEXT/PREV/slideshow controller.
    reg         standalone_boot_load_done;

    // ============================================================
    // M2 C/A control integration over the already-proven UART link.
    // The Master sees the real TF catalog and may queue OPEN(image_id).
    // ============================================================
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
    wire ctrl_link_seen, ctrl_fault, ctrl_command_toggle, ctrl_reply_toggle;
    reg  [7:0] selected_image_id;
    reg        queued_open_valid;
    reg  [7:0] queued_open_image_id;

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
    m2_real_media_uart_bridge u_m2_real_ctrl (
        .clk(pixel_clk), .rst_n(media_rst_n),
        .rx_frame_valid(ctrl_rx_frame_valid), .rx_frame_opcode(ctrl_rx_frame_opcode),
        .rx_frame_length(ctrl_rx_frame_length), .rx_frame_payload(ctrl_rx_frame_payload),
        .rx_frame_error(ctrl_rx_frame_error), .rx_framing_error(uart_framing_error),
        .frame_tx_busy(ctrl_tx_busy), .frame_tx_request(ctrl_tx_request),
        .frame_tx_opcode(ctrl_tx_opcode), .frame_tx_length(ctrl_tx_length),
        .frame_tx_payload(ctrl_tx_payload), .catalog_valid(media_catalog_valid),
        .catalog_count(media_catalog_count), .source_busy(media_busy),
        .source_done(media_done), .source_valid(media_succeeded),
        .source_error(media_failed), .source_error_code(media_failure_code),
        .selected_image_id(selected_image_id),
        .open_request(remote_open_request), .open_image_id(remote_open_image_id),
        .link_seen(ctrl_link_seen), .fault(ctrl_fault),
        .command_toggle(ctrl_command_toggle), .reply_toggle(ctrl_reply_toggle));

    m2_slave_tf_media_core #(.SPI_CLK_DIV(4), .SPI_INIT_CLK_DIV(32),
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
        .descriptor_valid(), .descriptor_image_id(),
        .descriptor_width(), .descriptor_height(),
        .source_ready    (), .source_busy(media_busy),
        .source_done     (media_done), .source_error(media_error),
        .error_code      (media_error_code),
        .sector_error_detail(media_sector_error_detail)
    );

    m2_media_write_cdc u_media_write_cdc (
        .media_clk      (pixel_clk),
        .media_rst_n    (media_rst_n),
        .media_wr_valid (media_wr_valid),
        .media_wr_addr  (media_wr_addr),
        .media_wr_data  (media_wr_data),
        .media_wr_ready (media_wr_ready),
        .media_done     (media_done),
        .sdr_fenced     (sdr_fenced),
        .sdr_clk        (sdr_clk_150m),
        .sdr_rst_n      (sdr_rst_n),
        .sdr_wr_valid   (sdr_media_wr_valid),
        .sdr_wr_addr    (sdr_media_wr_addr),
        .sdr_wr_data    (sdr_media_wr_data),
        .sdr_wr_ready   (sdr_media_wr_ready),
        .sdr_adapter_idle(mem_wr_ready));

    always @(posedge pixel_clk or negedge media_rst_n) begin
        if (!media_rst_n) begin
            media_cmd_valid <= 0;
            media_cmd_image_id <= 0;
            media_load_toggle <= 0;
            selected_image_id <= 0;
            queued_open_valid <= 0;
            queued_open_image_id <= 0;
            media_started <= 0;
            media_load_requested <= 0;
            media_failed <= 0;
            media_failure_code <= 0;
            media_sector_failure_detail <= 0;
            media_succeeded <= 0;
            media_scan_start <= 0;
            media_retrying <= 0;
            media_retry_count <= 0;
            standalone_boot_load_done <= 1'b0;
        end else begin
            media_cmd_valid <= 0;
            media_scan_start <= 0;

            // Keep one remote OPEN queued while TF/FAT/BMP is busy. The UART
            // response is immediate, so the Master never blocks on card I/O.
            // Seeing the real control plane permanently disables the one-shot
            // standalone autoload until the next board reset.
            if (ctrl_link_seen)
                standalone_boot_load_done <= 1'b1;
            if (remote_open_request) begin
                queued_open_valid <= 1'b1;
                queued_open_image_id <= remote_open_image_id;
                standalone_boot_load_done <= 1'b1;
            end

            if (media_busy || media_catalog_valid) media_started <= 1;
            if (media_failed && !media_busy && !media_succeeded) begin
                if (media_retry_count == 25'd24999999) begin
                    media_retry_count <= 0;
                    media_scan_start <= 1;
                    media_retrying <= 1;
                    media_load_requested <= 0;
                end else media_retry_count <= media_retry_count + 1'b1;
            end else media_retry_count <= 0;

            if (media_cmd_ready) begin
                if (queued_open_valid) begin
                    media_cmd_image_id <= queued_open_image_id;
                    media_cmd_valid <= 1'b1;
                    media_load_toggle <= ~media_load_toggle;
                    queued_open_valid <= 1'b0;
                    media_load_requested <= 1'b1;
                    media_succeeded <= 1'b0;
                    media_failed <= 1'b0;
                    media_failure_code <= 0;
                    media_sector_failure_detail <= 0;
                end else if (!media_scan_start && (!media_failed || media_retrying) &&
                             !media_load_requested && !standalone_boot_load_done &&
                             !ctrl_link_seen) begin
                    if (media_catalog_count != 0) begin
                        // Standalone board behavior: load image 0 exactly once
                        // after reset/card recovery.  After that, keep the current
                        // framebuffer until a Master OPEN arrives.
                        media_cmd_image_id <= 8'd0;
                        media_cmd_valid <= 1'b1;
                        media_load_toggle <= ~media_load_toggle;
                        media_load_requested <= 1'b1;
                        standalone_boot_load_done <= 1'b1;
                    end else if (media_catalog_valid) begin
                        media_failed <= 1;
                        media_failure_code <= 8'h20;
                    end
                end
            end
            if (media_error) begin
                media_failed <= 1;
                media_retrying <= 0;
                media_load_requested <= 0;
                // With no Master present, a failed standalone transaction may
                // retry scan and then perform one new boot load after recovery.
                if (!ctrl_link_seen)
                    standalone_boot_load_done <= 1'b0;
                media_failure_code <= media_error_code;
                // Capture physical-SD detail in the same cycle as the
                // service-level 0x11/0x14 error before the sector provider
                // returns to IDLE and starts a later retry.
                if (media_error_code == 8'h11 || media_error_code == 8'h14)
                    media_sector_failure_detail <= media_sector_error_detail;
            end
            if (media_done) begin
                selected_image_id <= media_cmd_image_id;
                media_succeeded <= 1;
                media_failed <= 0;
                media_retrying <= 0;
                media_load_requested <= 0;
                media_failure_code <= 0;
                media_sector_failure_detail <= 0;
            end
        end
    end

    // Board diagnostics (DIAG5): do not overload the four independent LEDs
    // with a binary error nibble.  Each physical LED now has one fixed meaning:
    //   LED1 / led[0] = catalog_valid
    //   LED2 / led[1] = media_busy
    //   LED3 / led[2] = completed media transaction AND frame_ready_sdr
    //   LED4 / led[3] = any media/SDRAM fault
    // The separate eight-LED group carries the complete 8-bit diagnostic byte.
    // This avoids wide counters and consumes only output routing.
    assign led[0] = media_catalog_valid;
    assign led[1] = media_busy;
    assign led[2] = media_succeeded && frame_ready_sdr;
    assign led[3] = media_failed || frame_write_error;

    // Full-byte diagnostic on the board's 8-bit LED group.
    //   no fault          : 0x81 build marker (two end LEDs on)
    //   media fault       : exact media_failure_code
    //   SDRAM/write fault : 0xF0
    // DIG0..7 are active-low on the schematic, hence the inversion.
    wire [7:0] board_diag_byte = frame_write_error ? 8'hF0 :
                                 media_failed      ?
                                   (((media_failure_code == 8'h11) ||
                                     (media_failure_code == 8'h14)) &&
                                    (media_sector_failure_detail != 8'h00)
                                      ? media_sector_failure_detail
                                      : media_failure_code) :
                                                     8'h81;
    assign diag_led_n = ~board_diag_byte;
    assign diag_sel_n = 8'hFF; // disable the alternate-color/nixie select path

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

        .wr_valid                (sdr_media_wr_valid),
        .wr_addr                 (sdr_media_wr_addr),
        .wr_data                 (sdr_media_wr_data),
        .wr_ready                (sdr_media_wr_ready),

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
    p1_sdram_cached_adapter #(
        // ChipWatcher/unit regressions retain the module default diagnostics;
        // the board build removes those counters/assertions from the 150 MHz
        // timing cone because they are not part of the framebuffer data path.
        .ENABLE_RUNTIME_DIAGNOSTICS(0)
    ) u_sdram_adapter (
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

    // New media transactions explicitly invalidate the previously published
    // single-buffer image. This prevents a second OPEN from being treated as
    // already-ready while the same SDRAM address range is being overwritten.
    reg media_load_sdr_ff1, media_load_sdr_ff2, media_load_sdr_seen;
    wire media_load_begin_sdr = (media_load_sdr_ff2 != media_load_sdr_seen);
    always @(posedge sdr_clk_150m or negedge sdr_rst_n) begin
        if (!sdr_rst_n) begin
            media_load_sdr_ff1 <= 1'b0;
            media_load_sdr_ff2 <= 1'b0;
        end else begin
            media_load_sdr_ff1 <= media_load_toggle;
            media_load_sdr_ff2 <= media_load_sdr_ff1;
        end
    end

    // Publish a complete frame only after all writes leave the SDRAM adapter.
    always @(posedge sdr_clk_150m or negedge sdr_rst_n) begin
        if (!sdr_rst_n) begin
            frame_ready_sdr   <= 1'b0;
            frame_write_error <= 1'b0;
            media_load_sdr_seen <= 1'b0;
        end else begin
            if (media_load_begin_sdr) begin
                media_load_sdr_seen <= media_load_sdr_ff2;
                frame_ready_sdr <= 1'b0;
                frame_write_error <= 1'b0;
            end else if (sdr_fenced) begin
                frame_ready_sdr <= 1'b1;
            end

            if (arb_protocol_error ||
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
    reg media_started_pix_ff1;
    reg media_started_pix_ff2;
    reg frame_ready_sdr_pix_ff1;
    reg frame_ready_sdr_pix_ff2;
    reg frame_write_error_pix_ff1;
    reg frame_write_error_pix_ff2;

    always @(posedge pixel_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            sdr_pll_lock_pix_ff1        <= 1'b0;
            sdr_pll_lock_pix_ff2        <= 1'b0;
            media_started_pix_ff1       <= 1'b0;
            media_started_pix_ff2       <= 1'b0;
            frame_ready_sdr_pix_ff1     <= 1'b0;
            frame_ready_sdr_pix_ff2     <= 1'b0;
            frame_write_error_pix_ff1   <= 1'b0;
            frame_write_error_pix_ff2   <= 1'b0;
        end else begin
            sdr_pll_lock_pix_ff1        <= sdr_pll_lock;
            sdr_pll_lock_pix_ff2        <= sdr_pll_lock_pix_ff1;
            media_started_pix_ff1       <= media_started;
            media_started_pix_ff2       <= media_started_pix_ff1;
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
        end else if (media_cmd_valid && media_cmd_ready) begin
            // Hide the single buffer while it is being replaced. The display
            // remains on the deterministic diagnostic page until a complete
            // write has fenced and scanout has warmed again.
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
        else if (!media_started_pix_ff2)
            startup_diag_data = 24'hFF8000; // orange: APUG011/write not started
        else if (frame_write_error_pix_ff2)
            startup_diag_data = 24'hFFFFFF; // white + LED F: SDRAM backend fault
        else if (media_failed) begin
            case (media_failure_code[7:4])
                4'h1: startup_diag_data = 24'hFF0000; // red: 0x1n service/sector/file
                4'h2: startup_diag_data = 24'hFF00FF; // magenta: 0x2n catalog/selection
                4'h3: startup_diag_data = 24'h00FFFF; // cyan: 0x3n loader/writer detail
                4'h4: startup_diag_data = 24'hFF0000; // red: physical SD command detail
                default: startup_diag_data = 24'hFF8000; // orange: unexpected family
            endcase
        end else if (!frame_ready_sdr_pix_ff2)
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
    wire _unused_ctrl = ctrl_link_seen ^ ctrl_fault ^ ctrl_command_toggle ^
                        ctrl_reply_toggle ^ uart_rx_activity;

endmodule
