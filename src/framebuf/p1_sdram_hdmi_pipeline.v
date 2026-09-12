// ================================================================
// Module  : p1_sdram_hdmi_pipeline
// Purpose : P1-05A display-side integration:
//             SDRAM-domain ordered reads
//               -> explicit async CDC
//               -> line_prefetcher
//               -> line_buffer_pingpong
//               -> free-running framebuffer scanout
//
// APUG092 itself is intentionally outside this module so the P1-04C golden
// HDMI reset/EDID/PHY boundary remains unchanged.
// ================================================================

module p1_sdram_hdmi_pipeline #(
    parameter integer FRAME_WIDTH  = 640,
    parameter integer FRAME_HEIGHT = 480,
    parameter integer FRAME_STRIDE = 640,
    parameter [20:0]  FRAME_BASE   = 21'd0,
    parameter integer MAX_OUTSTANDING = 8,

    parameter integer HFP = 16,
    parameter integer HSA = 96,
    parameter integer HBP = 48,
    parameter integer VFP = 10,
    parameter integer VSA = 2,
    parameter integer VBP = 33
) (
    input  wire        pix_clk,
    input  wire        pix_rst_n,
    input  wire        sdr_clk,
    input  wire        sdr_rst_n,

    // Sticky high after the fixed framebuffer has been fully written.
    input  wire        frame_ready_sdr,

    // Ordered abstract read interface in SDRAM domain.
    output wire        sdr_mem_rd_valid,
    output wire [20:0] sdr_mem_rd_addr,
    input  wire        sdr_mem_rd_ready,
    input  wire        sdr_mem_rvalid,
    input  wire [31:0] sdr_mem_rdata,

    // Pixel-domain framebuffer data aligned to P1-04C raster timing.
    output wire        fb_pixel_valid,
    output wire [23:0] fb_pixel_data,
    output wire        frame_boundary,
    output wire        warm_ready,
    output wire        frame_ready_pix,

    output wire        underflow_sticky,
    output wire        protocol_error
);

    // Keep integer top-level geometry parameters for convenient project-level
    // configuration, but present explicit 16-bit values to line_prefetcher.
    // This avoids simulator/elaborator port-width warnings while preserving
    // the existing P0 interface contract.
    localparam [15:0] FRAME_WIDTH_CFG  = FRAME_WIDTH;
    localparam [15:0] FRAME_HEIGHT_CFG = FRAME_HEIGHT;
    localparam [15:0] FRAME_STRIDE_CFG = FRAME_STRIDE;

    // ------------------------------------------------------------
    // frame_ready CDC: sticky level, 2-flop synchronization.
    // ------------------------------------------------------------
    reg frame_ready_sync1;
    reg frame_ready_sync2;

    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            frame_ready_sync1 <= 1'b0;
            frame_ready_sync2 <= 1'b0;
        end else begin
            frame_ready_sync1 <= frame_ready_sdr;
            frame_ready_sync2 <= frame_ready_sync1;
        end
    end

    assign frame_ready_pix = frame_ready_sync2;

    // ------------------------------------------------------------
    // Read request/response CDC.
    // ------------------------------------------------------------
    // The CDC bridge status is generated in the SDR/pixel transaction logic.
    // It is diagnostic only and must not form a combinational path from the
    // CDC machinery into the HDMI pixel output domain.
    wire        pix_mem_rd_valid;
    wire [20:0] pix_mem_rd_addr;
    wire        pix_mem_rd_ready;
    wire        pix_mem_rvalid;
    wire [31:0] pix_mem_rdata;
    wire        cdc_protocol_error;

    p1_sdram_read_cdc_bridge #(
        .REQ_FIFO_ADDR_WIDTH (4),
        .RESP_FIFO_ADDR_WIDTH(4)
    ) u_read_cdc (
        .pix_clk          (pix_clk),
        .pix_rst_n        (pix_rst_n),
        .pix_mem_rd_valid (pix_mem_rd_valid),
        .pix_mem_rd_addr  (pix_mem_rd_addr),
        .pix_mem_rd_ready (pix_mem_rd_ready),
        .pix_mem_rvalid   (pix_mem_rvalid),
        .pix_mem_rdata    (pix_mem_rdata),

        .sdr_clk          (sdr_clk),
        .sdr_rst_n        (sdr_rst_n),
        .sdr_mem_rd_valid (sdr_mem_rd_valid),
        .sdr_mem_rd_addr  (sdr_mem_rd_addr),
        .sdr_mem_rd_ready (sdr_mem_rd_ready),
        .sdr_mem_rvalid   (sdr_mem_rvalid),
        .sdr_mem_rdata    (sdr_mem_rdata),

        .protocol_error   (cdc_protocol_error)
    );

    // ------------------------------------------------------------
    // line_prefetcher -> line_buffer_pingpong
    // ------------------------------------------------------------
    reg  [15:0] prefetch_line;
    reg         prefetch_start;
    reg  [1:0]  warm_count;
    reg         scheduler_error;

    wire prefetch_busy;
    wire prefetch_done;
    wire prefetch_ok;
    wire prefetch_timeout_error;
    wire prefetch_protocol_error;
    wire prefetch_recovery_required;

    wire        lb_fill_ready;
    wire        lb_fill_start;
    wire [15:0] lb_fill_line_index;
    wire [15:0] lb_fill_width;
    wire        lb_fill_valid;
    wire [23:0] lb_fill_data;
    wire        lb_fill_done;
    wire        lb_fill_ok;

    line_prefetcher #(
        .MAX_OUTSTANDING    (MAX_OUTSTANDING),
        .STALL_TIMEOUT_CYCLES(8192)
    ) u_prefetcher (
        .clk                  (pix_clk),
        .rst_n                (pix_rst_n),
        .start                (prefetch_start),
        .frame_base           (FRAME_BASE),
        .frame_width          (FRAME_WIDTH_CFG),
        .frame_height         (FRAME_HEIGHT_CFG),
        .frame_stride_words   (FRAME_STRIDE_CFG),
        .line_index           (prefetch_line),

        .mem_rd_valid         (pix_mem_rd_valid),
        .mem_rd_addr          (pix_mem_rd_addr),
        .mem_rd_ready         (pix_mem_rd_ready),
        .mem_rvalid           (pix_mem_rvalid),
        .mem_rdata            (pix_mem_rdata),

        .lb_fill_ready        (lb_fill_ready),
        .lb_fill_start        (lb_fill_start),
        .lb_fill_line_index   (lb_fill_line_index),
        .lb_fill_width        (lb_fill_width),
        .lb_fill_valid        (lb_fill_valid),
        .lb_fill_data         (lb_fill_data),
        .lb_fill_done         (lb_fill_done),
        .lb_fill_ok           (lb_fill_ok),

        .busy                 (prefetch_busy),
        .done                 (prefetch_done),
        .ok                   (prefetch_ok),
        .timeout_error        (prefetch_timeout_error),
        .protocol_error       (prefetch_protocol_error),
        .recovery_required    (prefetch_recovery_required),
        .issued_count_debug   (),
        .received_count_debug ()
    );

    wire        lb_read_start;
    wire [15:0] lb_read_line_index;
    wire [15:0] lb_read_width;
    wire        lb_pixel_valid;
    wire [23:0] lb_pixel_data;
    wire        lb_line_done;
    wire        lb_underflow_pulse;
    wire        lb_protocol_error;

    line_buffer_pingpong #(
        .MAX_LINE_PIXELS(FRAME_WIDTH)
    ) u_line_buffer (
        .clk               (pix_clk),
        .rst_n             (pix_rst_n),

        .fill_start        (lb_fill_start),
        .fill_line_index   (lb_fill_line_index),
        .fill_width        (lb_fill_width),
        .fill_ready        (lb_fill_ready),
        .fill_accept       (),
        .fill_valid        (lb_fill_valid),
        .fill_data         (lb_fill_data),
        .fill_done         (lb_fill_done),
        .fill_ok           (lb_fill_ok),
        .fill_commit_pulse (),
        .fill_fail_pulse   (),

        .read_start        (lb_read_start),
        .read_line_index   (lb_read_line_index),
        .read_width        (lb_read_width),
        .pixel_valid       (lb_pixel_valid),
        .pixel_data        (lb_pixel_data),
        .line_done         (lb_line_done),
        .underflow_pulse   (lb_underflow_pulse),
        .underflow_sticky  (underflow_sticky),

        .protocol_error    (lb_protocol_error),
        .fill_active       (),
        .read_active       (),
        .bank0_ready       (),
        .bank1_ready       ()
    );

    // Sequentially prefetch lines forever once the initialized frame is ready.
    // If both banks are occupied, line_prefetcher safely waits in WAIT_BUFFER.
    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            prefetch_line  <= 16'd0;
            prefetch_start <= 1'b0;
            warm_count     <= 2'd0;
            scheduler_error<= 1'b0;
        end else begin
            prefetch_start <= 1'b0;

            if (prefetch_done) begin
                if (prefetch_ok) begin
                    if (prefetch_line == FRAME_HEIGHT - 1)
                        prefetch_line <= 16'd0;
                    else
                        prefetch_line <= prefetch_line + 16'd1;

                    if (warm_count < 2)
                        warm_count <= warm_count + 2'd1;
                end else begin
                    scheduler_error <= 1'b1;
                end
            end

            // Only launch a new line transaction when a line-buffer bank is
            // actually available.  After the two startup lines are warm both
            // banks are intentionally occupied until scanout begins at the next
            // safe frame boundary.  Starting line 2 during that interval would
            // leave line_prefetcher in S_WAIT_BUFFER long enough to hit its
            // watchdog on a real 640x480 raster (~16.8 ms/frame), even though
            // no memory protocol error has occurred.
            if (frame_ready_pix &&
                lb_fill_ready &&
                !prefetch_busy &&
                !prefetch_done &&
                !prefetch_start &&
                !prefetch_recovery_required &&
                !scheduler_error) begin
                prefetch_start <= 1'b1;
            end
        end
    end

    assign warm_ready = (warm_count >= 2);

    // ------------------------------------------------------------
    // Free-running scanout scheduler.
    // ------------------------------------------------------------
    wire scanout_timing_error;
    reg  scanout_enable;

    // Do not request display lines during startup.  Wait until line 0/1 are
    // both warm, then arm scanout exactly at a raster frame boundary.  This
    // prevents expected startup misses from polluting underflow_sticky and
    // gives the board test a meaningful underflow diagnostic.
    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            scanout_enable <= 1'b0;
        end else if (!scanout_enable && frame_ready_pix && warm_ready &&
                     frame_boundary) begin
            scanout_enable <= 1'b1;
        end
    end

    hdmi_framebuffer_scanout #(
        .HACTIVE(FRAME_WIDTH),
        .HFP    (HFP),
        .HSA    (HSA),
        .HBP    (HBP),
        .VACTIVE(FRAME_HEIGHT),
        .VFP    (VFP),
        .VSA    (VSA),
        .VBP    (VBP)
    ) u_scanout (
        .clk_pix            (pix_clk),
        .rst_n              (pix_rst_n),
        .enable             (scanout_enable),
        .lb_read_start      (lb_read_start),
        .lb_read_line_index (lb_read_line_index),
        .lb_read_width      (lb_read_width),
        .lb_pixel_valid     (lb_pixel_valid),
        .lb_pixel_data      (lb_pixel_data),
        .lb_line_done       (lb_line_done),
        .pixel_valid        (fb_pixel_valid),
        .pixel_data         (fb_pixel_data),
        .frame_boundary     (frame_boundary),
        .active_expected    (),
        .timing_error       (scanout_timing_error),
        .h_count_debug      (),
        .v_count_debug      ()
    );

    // ------------------------------------------------------------
    // Pixel-domain diagnostic synchronization.
    // Keep error reporting CDC-safe. This signal is not part of the pixel
    // generation datapath.
    // ------------------------------------------------------------
    reg cdc_error_pix_ff1;
    reg cdc_error_pix_ff2;
    reg status_error_pix;

    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            cdc_error_pix_ff1 <= 1'b0;
            cdc_error_pix_ff2 <= 1'b0;
            status_error_pix   <= 1'b0;
        end else begin
            cdc_error_pix_ff1 <= cdc_protocol_error;
            cdc_error_pix_ff2 <= cdc_error_pix_ff1;
            status_error_pix   <= cdc_error_pix_ff2 ||
                                  scheduler_error ||
                                  prefetch_timeout_error ||
                                  prefetch_protocol_error ||
                                  prefetch_recovery_required ||
                                  lb_protocol_error ||
                                  scanout_timing_error;
        end
    end

    assign protocol_error = status_error_pix;

endmodule
