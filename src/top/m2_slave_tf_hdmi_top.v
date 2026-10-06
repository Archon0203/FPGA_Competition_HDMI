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
    m2_frame_display_core u_display (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .led(led),
        .diag_led_n(diag_led_n),
        .diag_sel_n(diag_sel_n),
        .sd_ncs(sd_ncs),
        .sd_sclk(sd_sclk),
        .sd_mosi(sd_mosi),
        .sd_miso(sd_miso),
        .HDMI_D0_P(HDMI_D0_P),
        .HDMI_D1_P(HDMI_D1_P),
        .HDMI_D2_P(HDMI_D2_P),
        .HDMI_CLK_P(HDMI_CLK_P),
        .HDMI_DDC_SCL(HDMI_DDC_SCL),
        .HDMI_DDC_SDA(HDMI_DDC_SDA),
        .remote_valid(1'b0), .remote_data(32'd0), .remote_ready(),
        .remote_published(), .media_clock(), .media_reset_n(),
        .cache_query_valid(1'b0), .cache_query_image_id(8'd0), .cache_query_ready(),
        .cache_reply_valid(), .cache_reply_hit(), .cache_reply_ready(1'b1), .card_missing(1'b0));
endmodule

module m2_frame_display_core #(parameter REMOTE_INPUT=0) (
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
    input wire remote_valid,
    input wire [31:0] remote_data,
    output wire remote_ready, remote_published, media_clock, media_reset_n,
    input wire cache_query_valid,
    input wire [7:0] cache_query_image_id,
    output wire cache_query_ready,
    output reg cache_reply_valid,
    output reg cache_reply_hit,
    input wire cache_reply_ready,
    input wire card_missing,
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
    localparam [20:0] FRAME_BUFFER_WORDS = 21'd307200;

    // ============================================================
    // P1-04C golden HDMI clocks: 50 MHz -> 25 MHz / 125 MHz
    // ============================================================
    wire pixel_clk;
    wire serial_clk;
    wire hdmi_pll_lock;
    wire video_locked_unused;

    p1_hdmi_pll_50m_25_125 u_hdmi_pll (
        .refclk_50m (clk),
        .reset      (1'b0),
        .lock       (hdmi_pll_lock),
        .pixel_clk  (pixel_clk),
        .serial_clk (serial_clk)
    );

    // ============================================================
    // HDMI reset + APUG092 lock recovery.
    //
    // The board-proven 20 ms reset hold remains unchanged, but the Master now
    // verifies APUG092 O_video_locked before it can report a frame as published.
    // If power-on sequencing leaves the transmitter unlocked, or lock is lost
    // later, the supervisor re-runs the reset sequence automatically instead of
    // leaving the monitor at its blue/no-signal screen until KEY1 is pressed.
    // ============================================================
    wire hdmi_video_locked_sync;
    wire hdmi_video_ready;
    wire hdmi_video_ready_async;
    reg hdmi_ready_pix_ff1, hdmi_ready_pix_ff2;
    wire hdmi_recovery_pulse;
    wire hdmi_rst;

    m2_hdmi_lock_supervisor #(.RESET_HOLD_CYCLES(1_000_000),
                              .LOCK_WAIT_CYCLES(10_000_000),
                              .UNLOCK_FILTER_CYCLES(1_000_000)) u_hdmi_supervisor (
        .clk                (clk),
        .ext_rst_n          (rst_n),
        .pll_lock           (hdmi_pll_lock),
        .video_locked_async (video_locked_unused),
        .hdmi_rst           (hdmi_rst),
        .video_locked_sync  (hdmi_video_locked_sync),
        .video_ready        (hdmi_video_ready_async),
        .recovery_pulse     (hdmi_recovery_pulse)
    );

    wire pix_rst_n = !hdmi_rst;
    // Supervisor owns 50 MHz; publication and raster own 25 MHz. All status
    // crossings remain synchronized under the control/pixel clock exception.
    always @(posedge pixel_clk or negedge pix_rst_n) begin
        if(!pix_rst_n) begin hdmi_ready_pix_ff1<=0; hdmi_ready_pix_ff2<=0; end
        else begin hdmi_ready_pix_ff1<=hdmi_video_ready_async; hdmi_ready_pix_ff2<=hdmi_ready_pix_ff1; end
    end
    assign hdmi_video_ready=hdmi_ready_pix_ff2;

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

    // HDMI automatic recovery resets both sides of every display/media CDC.
    // Keeping the SDRAM side alive while pix/media reset would one-side-reset
    // the async FIFOs and can leave stale pointer state.  Reinitialize the
    // whole display data plane together; the Slave retry path then resends the
    // current image after DISPLAY_PUBLISHED drops.
    wire sdr_rst_n = sdr_pll_lock && hdmi_pll_lock && rst_n && pix_rst_n;

    // ============================================================
    // TF media service and framebuffer writer (25 MHz media domain)
    // ============================================================
    wire media_cmd_valid;
    wire [7:0] media_cmd_image_id;
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
    wire        sdram_adapter_idle;
    wire        media_rst_n = pix_rst_n && rst_n;
    reg         media_started;
    reg         media_failed;
    reg  [7:0]  media_failure_code;
    reg  [7:0]  media_sector_failure_detail;
    reg         media_succeeded;
    reg         media_scan_start;
    reg         media_retrying;
    reg  [24:0] media_retry_count;

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
    wire remote_open_prefetch;
    reg  frame_ready_media_ff1;
    reg  frame_ready_media_ff2;
    wire ctrl_link_seen, ctrl_fault, ctrl_command_toggle, ctrl_reply_toggle;
    reg  [7:0] selected_image_id;
    reg [7:0] active_image_id;
    // Caption metadata follows the same commit boundary as the A/B framebuffer.
    wire [7:0] displayed_caption_image_id;
    wire [87:0] displayed_caption_filename_83;
    wire [15:0] displayed_image_width, displayed_image_height;
    wire [5:0] displayed_image_bpp;
    wire remote_filename_valid;
    wire [87:0] remote_filename_83;
    wire remote_info_valid;
    wire [15:0] remote_image_width, remote_image_height;
    wire [5:0] remote_image_bpp;
    wire local_descriptor_valid;
    wire [15:0] local_descriptor_width, local_descriptor_height;
    wire [87:0] local_descriptor_filename_83;
    reg use_framebuffer;
    reg front_valid;
    reg [2:0] display_bank;
    reg [2:0] load_bank;
    reg loading_active;
    wire pipeline_protocol_error, framebuffer_switch_pulse;
    reg frame_write_error_pix_ff2;
    reg cache_switch_pending;
    reg [2:0] cache_target_slot;
    reg prefetch_active, prefetch_stored;
    reg prefetch_publish_pulse;
    // A speculative frame is complete when it has been fenced and committed
    // to a non-front cache bank.  Keep that fact stable until the next OPEN;
    // the UART STATUS poll is much slower than this pixel-domain pulse.
    reg prefetch_publish_sticky;
    reg [7:0] prefetch_publish_image_id;
    wire cache_hit;
    wire [2:0] cache_slot;
    wire [5:0] cache_valid;
    reg [2:0] next_load_slot;
    integer slot_search;
    always @(*) begin
        next_load_slot=(display_bank==5) ? 0 : display_bank+1'b1;
        for(slot_search=5;slot_search>=0;slot_search=slot_search-1)
            if(!cache_valid[slot_search] && (!front_valid || slot_search!=display_bank))
                next_load_slot=slot_search;
    end
    function [20:0] bank_base;
        input [2:0] slot;
        begin
            case(slot)
                1:bank_base=307200; 2:bank_base=614400; 3:bank_base=921600;
                4:bank_base=1228800; 5:bank_base=1536000; default:bank_base=0;
            endcase
        end
    endfunction
    assign cache_query_ready=REMOTE_INPUT && !loading_active &&
                             !cache_switch_pending && !cache_reply_valid &&
                             !pipeline_protocol_error && !frame_write_error_pix_ff2;
    wire cached_commit=cache_switch_pending && framebuffer_switch_pulse;
    always @(posedge pixel_clk or negedge pix_rst_n) begin
        if(!pix_rst_n) begin
            cache_reply_valid<=0; cache_reply_hit<=0;
            cache_switch_pending<=0; cache_target_slot<=0;
        end else begin
            if(cache_reply_valid && cache_reply_ready) cache_reply_valid<=0;
            if(cache_query_valid && cache_query_ready) begin
                if(front_valid && cache_hit && cache_slot!=display_bank) begin
                    cache_target_slot<=cache_slot; cache_switch_pending<=1;
                end else begin
                    cache_reply_valid<=1; cache_reply_hit<=cache_hit;
                end
            end
            if(cached_commit) begin
                cache_switch_pending<=0; cache_reply_valid<=1; cache_reply_hit<=1;
            end
        end
    end
    reg fenced_toggle_sdr;
    reg fenced_sync1, fenced_sync2, fenced_seen;
    reg frame_fenced_media;
    reg publish_wait_frame;
    wire current_frame_published;

    // Synchronize the SDRAM-domain publish state back into the media domain.
    // After a successful media transaction, the next OPEN is held until the
    // previous frame is fully fenced in SDRAM.
    always @(posedge pixel_clk or negedge media_rst_n) begin
        if (!media_rst_n) begin
            frame_ready_media_ff1 <= 1'b0;
            frame_ready_media_ff2 <= 1'b0;
        end else begin
            frame_ready_media_ff1 <= frame_ready_sdr;
            frame_ready_media_ff2 <= frame_ready_media_ff1;
        end
    end

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
                     (media_succeeded && !current_frame_published &&
                      !prefetch_publish_sticky)),
        .source_done(1'b0),
        .source_valid(current_frame_published ||
                      (prefetch_publish_sticky &&
                       (selected_image_id == prefetch_publish_image_id))),
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
    m2_open_dispatcher u_m2_open_dispatcher (
        .clk                  (pixel_clk),
        .rst_n                (media_rst_n),
        .catalog_valid        (media_catalog_valid),
        .catalog_count        (media_catalog_count),
        .cmd_ready            (media_cmd_accept_ready),
        .remote_open_request  (remote_open_request),
        .remote_open_image_id (remote_open_image_id),
        .remote_open_prefetch (remote_open_prefetch),
        .catalog_restart      (media_scan_start),
        .cmd_valid            (dispatch_cmd_valid),
        .cmd_image_id         (dispatch_cmd_image_id),
        .cmd_is_remote        (dispatch_cmd_is_remote),
        .cmd_is_prefetch      (dispatch_cmd_is_prefetch),
        .bootstrap_issued     (dispatch_bootstrap_issued),
        .remote_queued        (dispatch_remote_queued)
    );

    assign media_cmd_accept_ready = media_cmd_ready &&
                                  (!media_succeeded || current_frame_published ||
                                   prefetch_publish_sticky);
    assign media_cmd_valid    = dispatch_cmd_valid && media_cmd_accept_ready;
    assign media_cmd_image_id = dispatch_cmd_image_id;
    wire remote_begin;
    wire [7:0] remote_image;
    wire remote_prefetch;
    wire dispatch_fire = REMOTE_INPUT ? remote_begin : (dispatch_cmd_valid && media_cmd_accept_ready);

    // Remote-path sticky milestones.  These are intentionally kept in the
    // pixel/media clock domain so the board's 8-LED group can expose exactly
    // how far a received frame progressed without ChipWatcher.
    reg remote_begin_seen;
    reg remote_done_seen;
    reg remote_error_seen;

    always @(posedge pixel_clk or negedge media_rst_n) begin
        if (!media_rst_n) begin
            remote_begin_seen <= 1'b0;
            remote_done_seen  <= 1'b0;
            remote_error_seen <= 1'b0;
        end else begin
            if (remote_begin) remote_begin_seen <= 1'b1;
            if (media_done)   remote_done_seen  <= 1'b1;
            if (media_error)  remote_error_seen <= 1'b1;
        end
    end
    // DISPLAY_PUBLISHED is assigned after the HDMI/display health signals are
    // available.  It must mean "actually displayable", not merely "framebuffer
    // state machine reached use_framebuffer".
    assign media_clock = pixel_clk;
    assign media_reset_n = media_rst_n;

    generate if (REMOTE_INPUT) begin : g_remote
        m2_remote_frame_rx u_frame_rx(.clk(pixel_clk), .rst_n(media_rst_n),
            .in_valid(remote_valid), .in_data(remote_data), .in_ready(remote_ready),
            .frame_begin(remote_begin), .frame_done(media_done), .frame_error(media_error),
            .image_id(remote_image), .frame_prefetch(remote_prefetch),
            .wr_valid(media_wr_valid), .wr_addr(media_wr_addr),
            .wr_data(media_wr_data), .wr_ready(media_wr_ready), .busy(media_busy),
            .filename_valid(remote_filename_valid), .filename_83(remote_filename_83),
            .info_valid(remote_info_valid), .image_width(remote_image_width),
            .image_height(remote_image_height), .image_bpp(remote_image_bpp));
        assign local_descriptor_valid = 1'b0;
        assign local_descriptor_width = 16'd0;
        assign local_descriptor_height = 16'd0;
        assign local_descriptor_filename_83 = {11{8'h20}};
        assign media_cmd_ready=0;
        assign media_catalog_valid=1;
        assign media_catalog_count=1;
        assign media_error_code=8'h31;
        assign media_sector_error_detail=0;
        assign sd_ncs=1; assign sd_sclk=0; assign sd_mosi=1;
    end else begin : g_local
        assign remote_begin=0; assign remote_image=0; assign remote_ready=0;
        assign remote_prefetch=0;
        assign remote_filename_valid=1'b0;
        assign remote_filename_83={11{8'h20}};
        assign remote_info_valid=1'b0;
        assign remote_image_width=16'd0;
        assign remote_image_height=16'd0;
        assign remote_image_bpp=6'd0;
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
        .descriptor_valid(local_descriptor_valid), .descriptor_image_id(),
        .descriptor_width(local_descriptor_width), .descriptor_height(local_descriptor_height),
        .descriptor_filename_83(local_descriptor_filename_83),
        .source_ready    (), .source_busy(media_busy),
        .source_done     (media_done), .source_error(media_error),
        .error_code      (media_error_code),
        .sector_error_detail(media_sector_error_detail)
    );

    end endgenerate

    // Keep the currently displayed frame immutable while the next image is
    // transferred.  Incoming media addresses are always 0..307199; translate
    // them into the selected back-buffer bank before crossing into SDRAM.
    wire [20:0] media_wr_addr_banked = media_wr_addr +
                                       bank_base(load_bank);

    m2_media_write_cdc u_media_write_cdc (
        .media_clk      (pixel_clk),
        .media_rst_n    (media_rst_n),
        .media_wr_valid (media_wr_valid),
        .media_wr_addr  (media_wr_addr_banked),
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
        .sdr_adapter_idle(sdram_adapter_idle));

    always @(posedge pixel_clk or negedge media_rst_n) begin
        if (!media_rst_n) begin
            media_load_toggle <= 0;
            selected_image_id <= 0;
            active_image_id <= 0;
            media_started <= 0;
            media_failed <= 0;
            media_failure_code <= 0;
            media_sector_failure_detail <= 0;
            media_succeeded <= 0;
            media_scan_start <= 0;
            media_retrying <= 0;
            media_retry_count <= 0;
        end else begin
            media_scan_start <= 0;

            if (media_busy || media_catalog_valid)
                media_started <= 1'b1;

            // No-card / media-failure recovery remains autonomous.  A retry
            // rebuilds the catalog and re-arms exactly one bootstrap OPEN(0)
            // through m2_open_dispatcher.
            if (media_failed && !media_busy && !media_succeeded) begin
                if (media_retry_count == 25'd24999999) begin
                    media_retry_count <= 0;
                    media_scan_start <= 1'b1;
                    media_retrying <= 1'b1;
                end else begin
                    media_retry_count <= media_retry_count + 1'b1;
                end
            end else begin
                media_retry_count <= 0;
            end

            // The dispatcher is the only normal source of OPEN commands.
            // Before a Master is attached it emits one bootstrap OPEN(0); after
            // that, only queued remote OPEN requests can generate new loads.
            if (dispatch_fire) begin
                active_image_id <= REMOTE_INPUT ? remote_image : media_cmd_image_id;
                media_load_toggle <= ~media_load_toggle;
                media_succeeded <= 1'b0;
                media_failed <= 1'b0;
                media_failure_code <= 0;
                media_sector_failure_detail <= 0;
            end

            if (media_catalog_valid && (media_catalog_count == 0)) begin
                media_failed <= 1'b1;
                media_failure_code <= 8'h20;
            end

            if (media_error) begin
                media_failed <= 1'b1;
                media_retrying <= 1'b0;
                media_failure_code <= media_error_code;
                // Capture physical-SD detail in the same cycle as the
                // service-level 0x11/0x14 error before the sector provider
                // returns to IDLE and starts a later retry.
                if (media_error_code == 8'h11 || media_error_code == 8'h14)
                    media_sector_failure_detail <= media_sector_error_detail;
            end

            if (media_done) begin
                selected_image_id <= active_image_id;
                media_succeeded <= 1'b1;
                media_failed <= 1'b0;
                media_retrying <= 1'b0;
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
    // led[3] is assigned with the complete display/HDMI fault set below.

    // The full-byte diagnostic assignment is made near the end of this module,
    // after the framebuffer/HDMI milestones are available.

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
    wire [20:0] pending_frame_base;
    wire        framebuffer_swap_request;

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
        .next_frame_valid (framebuffer_swap_request),
        .next_frame_base  (pending_frame_base),
        .frame_switch_pulse(framebuffer_switch_pulse),
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
        .adapter_idle            (sdram_adapter_idle),
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

    // New media transactions leave the current front buffer published.  The
    // toggle only starts a fresh SDRAM-write health epoch; pixel writes are
    // redirected to the opposite A/B bank above.
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
            fenced_toggle_sdr <= 1'b0;
        end else begin
            if (media_load_begin_sdr) begin
                media_load_sdr_seen <= media_load_sdr_ff2;
                // This P1 pipeline expects a monotonic frame_ready. Keep
                // scanout draining from the front bank while the back bank is
                // reloaded; dropping ready would unnecessarily stall prefetch.
                frame_write_error <= 1'b0;
            end else if (sdr_fenced) begin
                frame_ready_sdr <= 1'b1;
                fenced_toggle_sdr <= ~fenced_toggle_sdr;
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

    assign pending_frame_base = bank_base(cache_switch_pending ? cache_target_slot : load_bank);
    assign framebuffer_swap_request = cache_switch_pending || (front_valid && loading_active &&
                                      media_succeeded && frame_fenced_media &&
                                      frame_ready_pix && fb_warm_ready &&
                                      !pipeline_protocol_error &&
                                      !frame_write_error_pix_ff2);

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

    always @(posedge pixel_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            fenced_sync1 <= 0;
            fenced_sync2 <= 0;
            fenced_seen <= 0;
            frame_fenced_media <= 0;
        end else begin
            fenced_sync1 <= fenced_toggle_sdr;
            fenced_sync2 <= fenced_sync1;
            if (dispatch_fire)
                frame_fenced_media <= 0;
            else if (fenced_sync2 != fenced_seen) begin
                fenced_seen <= fenced_sync2;
                frame_fenced_media <= 1;
            end
        end
    end

    reg fb_data_seen;

    // Capture metadata for the image being loaded, but do not expose it to
    // the subtitle until the same safe frame boundary that commits its pixels.
    wire caption_filename_valid = REMOTE_INPUT ? remote_filename_valid : local_descriptor_valid;
    wire [87:0] caption_filename_value = REMOTE_INPUT ? remote_filename_83 : local_descriptor_filename_83;
    wire caption_info_valid = REMOTE_INPUT ? remote_info_valid : local_descriptor_valid;
    wire [15:0] caption_image_width = REMOTE_INPUT ? remote_image_width : local_descriptor_width;
    wire [15:0] caption_image_height = REMOTE_INPUT ? remote_image_height : local_descriptor_height;
    wire [5:0] caption_image_bpp = REMOTE_INPUT ? remote_image_bpp : 6'd24;
    wire dispatch_prefetch = REMOTE_INPUT && remote_prefetch;
    wire prefetch_store_safe = prefetch_active && !prefetch_stored && front_valid &&
                               media_succeeded && frame_fenced_media && frame_ready_pix &&
                               !pipeline_protocol_error && !frame_write_error_pix_ff2 &&
                               !media_failed;
    wire bootstrap_publish_commit = !front_valid && fb_frame_boundary &&
                     media_succeeded && frame_fenced_media &&
                     frame_ready_pix && fb_warm_ready && fb_data_seen &&
                     !pipeline_protocol_error &&
                     !frame_write_error_pix_ff2 && publish_wait_frame;
    wire caption_commit_pulse = (front_valid && framebuffer_switch_pulse) ||
                                bootstrap_publish_commit;

    m2_caption_commit u_caption_commit(
        .clk(pixel_clk), .rst_n(pix_rst_n),
        .load_begin(dispatch_fire),
        .load_image_id(REMOTE_INPUT ? remote_image : media_cmd_image_id),
        .filename_valid(caption_filename_valid),
        .filename_83(caption_filename_value),
        .image_info_valid(caption_info_valid),
        .image_width(caption_image_width), .image_height(caption_image_height),
        .image_bpp(caption_image_bpp),
        .commit_pulse(caption_commit_pulse && !cached_commit),
        .cache_store_pulse(prefetch_store_safe),
        .load_slot(dispatch_fire ? next_load_slot : load_bank),
        .cached_commit(cached_commit), .cached_slot(cache_target_slot),
        .query_image_id(cache_query_image_id), .cache_hit(cache_hit),
        .cache_slot(cache_slot), .cache_valid(cache_valid),
        .displayed_image_id(displayed_caption_image_id),
        .displayed_filename_83(displayed_caption_filename_83),
        .displayed_image_width(displayed_image_width),
        .displayed_image_height(displayed_image_height),
        .displayed_image_bpp(displayed_image_bpp));

    // Publication proof: the line-buffer/scanout path must have produced real
    // framebuffer pixels *after the current frame has fenced*.  Previously the
    // Master could raise DISPLAY_PUBLISHED from state-machine milestones alone,
    // allowing the Slave to stop retrying even when scanout had never emitted a
    // framebuffer pixel on hardware.  Keep the Loading UI visible until this
    // proof exists.
    always @(posedge pixel_clk or negedge pix_rst_n) begin
        if (!pix_rst_n)
            fb_data_seen <= 1'b0;
        else if (dispatch_fire || framebuffer_switch_pulse)
            fb_data_seen <= 1'b0;
        else if (frame_fenced_media && fb_pixel_valid &&
                 (!front_valid || !loading_active))
            // For reloads, pixels seen before the bank handoff still belong to
            // the previous frame and must not satisfy DISPLAY_PUBLISHED.
            fb_data_seen <= 1'b1;
    end

    // Display ownership for six 640x480 framebuffer slots (1843200 words).  The first image
    // keeps the proven startup path.  Every later transaction writes the other
    // bank while the current front buffer remains visible; only the pipeline's
    // safe frame-boundary pulse commits the new bank.
    always @(posedge pixel_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            use_framebuffer    <= 1'b0;
            front_valid        <= 1'b0;
            display_bank       <= 1'b0;
            load_bank          <= 1'b0;
            loading_active     <= 1'b0;
            publish_wait_frame <= 1'b0;
            prefetch_active    <= 1'b0;
            prefetch_stored    <= 1'b0;
            prefetch_publish_pulse <= 1'b0;
            prefetch_publish_sticky <= 1'b0;
            prefetch_publish_image_id <= 8'd0;
        end else begin
            prefetch_publish_pulse <= 1'b0;
            if (dispatch_fire) begin
                prefetch_active <= dispatch_prefetch;
                prefetch_stored <= 1'b0;
                // A new OPEN supersedes the previous completion report.  The
                // bridge will report ACCEPTED until this transaction finishes.
                prefetch_publish_sticky <= 1'b0;
            end else if (prefetch_store_safe) begin
                prefetch_stored <= 1'b1;
                prefetch_active <= 1'b0;
                prefetch_publish_pulse <= 1'b1;
                prefetch_publish_sticky <= 1'b1;
                prefetch_publish_image_id <= active_image_id;
            end
            if (dispatch_fire && dispatch_prefetch) begin
                load_bank <= next_load_slot;
                // Keep scanning the current front bank during the background fill.
                loading_active <= 1'b0;
                publish_wait_frame <= 1'b0;
            end else if (dispatch_fire) begin
                load_bank      <= next_load_slot;
                loading_active <= 1'b1;
                publish_wait_frame <= 1'b0;
                if (!front_valid)
                    use_framebuffer <= 1'b0;
            end else if (media_failed) begin
                loading_active<=0;
                prefetch_active<=0;
            end else if (front_valid && framebuffer_switch_pulse) begin
                display_bank       <= cache_switch_pending ? cache_target_slot : load_bank;
                loading_active     <= 1'b0;
                use_framebuffer    <= 1'b1;
                publish_wait_frame <= 1'b0;
            end else if (!front_valid && fb_frame_boundary &&
                         media_succeeded && frame_fenced_media &&
                         frame_ready_pix && fb_warm_ready && fb_data_seen &&
                         !pipeline_protocol_error &&
                         !frame_write_error_pix_ff2) begin
                publish_wait_frame <= 1'b1;
                if (publish_wait_frame) begin
                    use_framebuffer <= 1'b1;
                    front_valid     <= 1'b1;
                    display_bank    <= load_bank;
                    loading_active  <= 1'b0;
                end
            end
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

    wire [23:0] loading_rgb;
    m2_loading_card u_loading_card(.clk(pixel_clk), .rst_n(pix_rst_n),
        .axis_valid(baseline_axis_valid), .axis_user(baseline_axis_user),
        .axis_last(baseline_axis_last),
        .background_rgb(framebuffer_axis_data),
        .overlay_only(1'b0), .card_missing(card_missing),
        .rgb(loading_rgb));
    wire loading_healthy = sdr_pll_lock_pix_ff2 && !frame_write_error_pix_ff2 &&
                           !media_failed && !pipeline_protocol_error;
    // Loading is startup-only. A reload, including a failed back-buffer load,
    // leaves the previously committed picture on screen.
    wire [23:0] axis_data_pre_subtitle = (card_missing === 1'b1) ? loading_rgb :
                          (use_framebuffer && front_valid ? framebuffer_axis_data : loading_rgb);
    wire [23:0] axis_data_with_subtitle;
    m2_image_subtitle u_image_subtitle(
        .clk(pixel_clk), .rst_n(pix_rst_n),
        .axis_valid(baseline_axis_valid), .axis_user(baseline_axis_user),
        .axis_last(baseline_axis_last),
        .background_rgb(axis_data_pre_subtitle),
        .enable(use_framebuffer && front_valid && !(card_missing === 1'b1)),
        .image_id(displayed_caption_image_id),
        .filename_83(displayed_caption_filename_83),
        .rgb(axis_data_with_subtitle));

    // Top-left translucent info box follows the committed image, while subtitles are
    // geographically disjoint and therefore preserved unchanged.
    wire [23:0] axis_data;
    m2_image_info_overlay #(.FALLBACK_WIDTH(HACTIVE), .FALLBACK_HEIGHT(VACTIVE)) u_image_info_overlay(
        .clk(pixel_clk), .rst_n(pix_rst_n),
        .axis_valid(baseline_axis_valid), .axis_user(baseline_axis_user),
        .axis_last(baseline_axis_last),
        .background_rgb(axis_data_with_subtitle),
        .enable(use_framebuffer && front_valid && !(card_missing === 1'b1)),
        .image_width(displayed_image_width), .image_height(displayed_image_height),
        .image_bpp(displayed_image_bpp), .rgb(axis_data));

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
    // bind extra board pins yet.  HDMI lock is part of the publication contract:
    // the Slave must never receive DISPLAY_PUBLISHED while APUG092 is unlocked.
    wire p1_05a_error = frame_write_error ||
                        pipeline_protocol_error ||
                        (use_framebuffer && fb_underflow_sticky);
    wire display_runtime_fault = p1_05a_error || media_failed ||
                                 (pix_rst_n && !hdmi_video_ready);
    wire p1_05a_active = use_framebuffer && !display_runtime_fault;

    assign current_frame_published = use_framebuffer && front_valid &&
                                     !loading_active && fb_data_seen &&
                                     media_succeeded && frame_fenced_media &&
                                     hdmi_video_ready && !p1_05a_error &&
                                     !media_failed;
    // Keep the completion indication asserted until the next OPEN.  The
    // transport board runs on an independent clock and may sample this after
    // several mailbox/CDC cycles; a one-cycle prefetch pulse is unsafe.
    assign remote_published = current_frame_published || prefetch_publish_sticky;

    // 8-bit LED diagnostic.  On the Master (REMOTE_INPUT=1), LEDs 1..8 form a
    // left-to-right milestone chain; once a stage succeeds it stays visible:
    //   D1 HDMI video lock, D2 remote header seen, D3 CRC/frame done,
    //   D4 SDRAM write fenced, D5 frame_ready reached pixel domain,
    //   D6 line buffers warm, D7 real framebuffer pixel observed after fence,
    //   D8 framebuffer mux published.
    // In local mode retain the compact media/error byte used by P1 bring-up.
    wire [7:0] remote_diag_byte = {current_frame_published, fb_data_seen, fb_warm_ready,
                                   frame_ready_pix, frame_fenced_media,
                                   remote_done_seen, remote_begin_seen,
                                   hdmi_video_ready};
    wire [7:0] local_diag_byte = frame_write_error ? 8'hF0 :
                                 media_failed      ?
                                   (((media_failure_code == 8'h11) ||
                                     (media_failure_code == 8'h14)) &&
                                    (media_sector_failure_detail != 8'h00)
                                      ? media_sector_failure_detail
                                      : media_failure_code) :
                                                     8'h81;
    wire [7:0] board_diag_byte = REMOTE_INPUT ? remote_diag_byte : local_diag_byte;
    assign diag_led_n = ~board_diag_byte;
    assign diag_sel_n = 8'hFF; // select the DIG/LED color only (active-low cathodes)

    // LED4 on the display core now includes HDMI lock/recovery status.  In the
    // Master wrapper this is ORed with the independent UART-control fault.
    // Thus a blue/no-signal monitor can no longer coexist with a falsely clean
    // display status.  The other LED meanings are unchanged.
    assign led[3] = media_failed || (REMOTE_INPUT && remote_error_seen) || frame_write_error || pipeline_protocol_error ||
                    (use_framebuffer && fb_underflow_sticky) ||
                    (pix_rst_n && !hdmi_video_ready);

    wire _unused_ctrl = ctrl_link_seen ^ ctrl_fault ^ ctrl_command_toggle ^
                        ctrl_reply_toggle ^ uart_rx_activity ^ hdmi_recovery_pulse ^
                        hdmi_video_locked_sync;

endmodule
