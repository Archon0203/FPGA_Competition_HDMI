// ================================================================
// Module  : p1_media_framebuffer_loader
// Purpose : P1-05B media-file -> abstract SDRAM write bridge.
//
// This module reuses the frozen P0 media contracts in the SDRAM/write clock
// domain:
//
//   FAT32 file metadata + sector provider
//       -> fat32_file_reader
//       -> bmp_parser + bmp_pixel_stream
//       -> framebuffer_writer
//       -> sdram_arbiter -> p1_sdram_cached_adapter -> APUG011
//
// Scope intentionally stops at the abstract write interface.  P1-05A HDMI,
// read CDC, prefetch, scanout and all APUG092 wiring remain untouched.  The
// TF/SD physical reader must cross into this clock domain through an explicit
// CDC/provider wrapper before it is connected here; raw signals from another
// clock domain are not legal inputs to this module.
//
// Baseline policy:
//   * 24-bit BI_RGB, positive-height BMP (enforced by existing P0 parser);
//   * exact EXPECTED_WIDTH x EXPECTED_HEIGHT, no implicit scaler;
//   * one 32-bit SDRAM word per pixel, 0x00RRGGBB;
//   * frame_base must remain 4-word aligned.
//
// Completion semantics:
//   done is a one-cycle pulse only after the FAT reader, BMP pixel decoder,
//   and framebuffer writer all reach terminal states.  A file that ends before
//   the writer was armed (invalid/unsupported BMP) reports failure instead of
//   silently leaving a partial frame eligible for display.
// ================================================================

module p1_media_framebuffer_loader #(
    parameter integer EXPECTED_WIDTH       = 640,
    parameter integer EXPECTED_HEIGHT      = 480,
    parameter integer FRAME_STRIDE_WORDS   = 640,
    parameter integer PIXEL_FIFO_DEPTH     = 32,
    parameter integer SECTOR_BYTES         = 512,
    parameter integer STALL_TIMEOUT_CYCLES = 200000
) (
    input  wire         clk,
    input  wire         rst_n,

    // One-cycle request to load one BMP into frame_base.
    input  wire         start,
    input  wire [20:0]  frame_base,
    output wire         ready,

    // FAT32 file metadata supplied by the directory/BPB layer.
    input  wire [31:0]  start_cluster,
    input  wire [31:0]  file_size,
    input  wire [31:0]  fat_lba_base,
    input  wire [31:0]  data_lba_base,
    input  wire [7:0]   sectors_per_cluster,

    // Same-clock-domain sector provider transaction interface.
    output wire         sector_req,
    output wire [31:0]  sector_lba,
    input  wire         sector_ready,
    input  wire         sector_din_valid,
    input  wire [7:0]   sector_din,

    // Frozen abstract write interface toward sdram_arbiter.
    output wire         mem_wr_valid,
    output wire [20:0]  mem_wr_addr,
    output wire [31:0]  mem_wr_data,
    input  wire         mem_wr_ready,

    output reg          busy,
    output reg          done,
    output reg          ok,
    output reg          protocol_error,
    output reg          source_error,
    output reg          overflow,

    // Transaction diagnostics, not used by the P1-05A display path.
    output wire [15:0]  bmp_width,
    output wire [15:0]  bmp_height,
    output wire [23:0]  bmp_data_offset,
    output wire         file_done,
    output wire         file_ok,
    output wire         pixels_done,
    output wire         pixels_ok
);

    localparam integer FRAME_PIXELS = EXPECTED_WIDTH * EXPECTED_HEIGHT;

    reg         file_start;
    reg         writer_start;
    reg [20:0]  frame_base_latched;
    reg         writer_issued;
    reg         writer_finished;
    reg         writer_result_ok;
    reg         bad_metadata;
    reg         terminal_reported;

    wire        parser_done;
    wire        parser_ok;
    wire [5:0]  bmp_bpp;

    wire        file_byte_valid;
    wire [7:0]  file_byte;

    wire        pixel_valid;
    wire [7:0]  pixel_r;
    wire [7:0]  pixel_g;
    wire [7:0]  pixel_b;
    wire [15:0] pixel_x;
    wire [15:0] pixel_y;

    wire        pixel_ready;
    wire        writer_busy;
    wire        writer_done;
    wire        writer_ok;
    wire        writer_overflow;

    // The fixed P1-05B baseline must fit within the 21-bit word address map.
    // frame_base is checked at start; the writer independently rechecks it.
    // Use a 22-bit endpoint calculation.  2^21 itself is not representable
    // as a 21-bit literal; using 21'd2097152 would truncate to zero and reject
    // every otherwise legal frame base.
    wire start_config_valid = (frame_base[1:0] == 2'b00) &&
                              (FRAME_STRIDE_WORDS >= EXPECTED_WIDTH) &&
                              (EXPECTED_WIDTH > 0) &&
                              (EXPECTED_HEIGHT > 0) &&
                              (FRAME_PIXELS > 0) &&
                              (({1'b0, frame_base} + FRAME_PIXELS) <= 22'd2097152);

    assign ready = !busy;

    fat32_file_reader #(
        .SECTOR_BYTES(SECTOR_BYTES),
        .STALL_TIMEOUT_CYCLES(STALL_TIMEOUT_CYCLES)
    ) u_file_reader (
        .clk                (clk),
        .rst_n              (rst_n),
        .start              (file_start),
        .start_cluster      (start_cluster),
        .file_size          (file_size),
        .fat_lba_base       (fat_lba_base),
        .data_lba_base      (data_lba_base),
        .sectors_per_cluster(sectors_per_cluster),
        .sector_req         (sector_req),
        .sector_lba         (sector_lba),
        .sector_ready       (sector_ready),
        .din_valid          (sector_din_valid),
        .din                (sector_din),
        .byte_valid         (file_byte_valid),
        .byte_data          (file_byte),
        .done               (file_done),
        .ok                 (file_ok)
    );

    bmp_parser u_bmp_parser (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (file_start),
        .din        (file_byte),
        .din_valid  (file_byte_valid),
        .done       (parser_done),
        .bmp_ok     (parser_ok),
        .width      (bmp_width),
        .height     (bmp_height),
        .bpp        (bmp_bpp),
        .data_offset(bmp_data_offset)
    );

    bmp_pixel_stream u_bmp_pixels (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (file_start),
        .din        (file_byte),
        .din_valid  (file_byte_valid),
        .header_done(parser_done),
        .bmp_ok     (parser_ok),
        .width      (bmp_width),
        .height     (bmp_height),
        .file_done  (file_done),
        .file_ok    (file_ok),
        .pixel_valid(pixel_valid),
        .pixel_r    (pixel_r),
        .pixel_g    (pixel_g),
        .pixel_b    (pixel_b),
        .pixel_x    (pixel_x),
        .pixel_y    (pixel_y),
        .done       (pixels_done),
        .ok         (pixels_ok)
    );

    framebuffer_writer #(
        .PIXEL_FIFO_DEPTH(PIXEL_FIFO_DEPTH)
    ) u_framebuffer_writer (
        .clk               (clk),
        .rst_n             (rst_n),
        .start             (writer_start),
        .frame_base        (frame_base_latched),
        .frame_width       (EXPECTED_WIDTH[15:0]),
        .frame_height      (EXPECTED_HEIGHT[15:0]),
        .frame_stride_words(FRAME_STRIDE_WORDS[15:0]),
        .pixel_valid       (pixel_valid),
        .pixel_r           (pixel_r),
        .pixel_g           (pixel_g),
        .pixel_b           (pixel_b),
        .pixel_x           (pixel_x),
        .pixel_y           (pixel_y),
        .pixel_ready       (pixel_ready),
        .source_done       (pixels_done),
        .source_ok         (pixels_ok),
        .mem_wr_valid      (mem_wr_valid),
        .mem_wr_addr       (mem_wr_addr),
        .mem_wr_data       (mem_wr_data),
        .mem_wr_ready      (mem_wr_ready),
        .busy              (writer_busy),
        .done              (writer_done),
        .ok                (writer_ok),
        .overflow          (writer_overflow)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            file_start          <= 1'b0;
            writer_start        <= 1'b0;
            frame_base_latched  <= 21'd0;
            writer_issued       <= 1'b0;
            writer_finished     <= 1'b0;
            writer_result_ok    <= 1'b0;
            bad_metadata        <= 1'b0;
            terminal_reported   <= 1'b0;
            busy                <= 1'b0;
            done                <= 1'b0;
            ok                  <= 1'b0;
            protocol_error      <= 1'b0;
            source_error        <= 1'b0;
            overflow            <= 1'b0;
        end else begin
            file_start   <= 1'b0;
            writer_start <= 1'b0;
            done         <= 1'b0;

            if (start && busy)
                protocol_error <= 1'b1;

            if (start && !busy) begin
                frame_base_latched <= frame_base;
                writer_issued      <= 1'b0;
                writer_finished    <= 1'b0;
                writer_result_ok   <= 1'b0;
                bad_metadata       <= !start_config_valid;
                terminal_reported  <= 1'b0;
                ok                 <= 1'b0;
                source_error       <= 1'b0;
                overflow           <= 1'b0;

                if (start_config_valid) begin
                    file_start <= 1'b1;
                    busy       <= 1'b1;
                end else begin
                    busy           <= 1'b0;
                    done           <= 1'b1;
                    ok             <= 1'b0;
                    protocol_error <= 1'b1;
                    source_error   <= 1'b1;
                    terminal_reported <= 1'b1;
                end
            end

            if (busy) begin
                // Arm the valid-only writer before the first pixel byte.  The
                // P0 contract guarantees data_offset >= 54 for this baseline.
                if (!writer_issued && parser_ok &&
                    (bmp_width == EXPECTED_WIDTH[15:0]) &&
                    (bmp_height == EXPECTED_HEIGHT[15:0]) &&
                    (bmp_bpp == 6'd24) &&
                    (bmp_data_offset >= 24'd54)) begin
                    writer_start  <= 1'b1;
                    writer_issued <= 1'b1;
                end else if (parser_done && !writer_issued) begin
                    // parser_done is the latest safe point before pixels.
                    // Any other legal BMP size would need scaler/layout work;
                    // do not silently write it into the 640x480 baseline.
                    bad_metadata <= 1'b1;
                    source_error <= 1'b1;
                end

                if (pixel_valid && (!writer_issued || !pixel_ready)) begin
                    source_error   <= 1'b1;
                    protocol_error <= 1'b1;
                end

                if (writer_overflow) begin
                    overflow     <= 1'b1;
                    source_error <= 1'b1;
                end

                // writer_done is a one-cycle pulse and can precede file_done:
                // the FAT reader must still consume/release the physical final
                // sector after the BMP payload ends.  Preserve its terminal
                // result until the whole media transaction can be reported.
                if (writer_done) begin
                    writer_finished  <= 1'b1;
                    writer_result_ok <= writer_ok;
                end

                // A valid file can end one physical sector after the BMP
                // decoder finishes; wait for both terminal states and for all
                // queued SDRAM writes to be accepted by the frozen writer.
                if (!terminal_reported && file_done &&
                    ((!writer_issued) || writer_finished || writer_done)) begin
                    terminal_reported <= 1'b1;
                    busy              <= 1'b0;
                    done              <= 1'b1;
                    ok                <= file_ok && pixels_ok && writer_issued &&
                                         (writer_finished ? writer_result_ok : writer_ok) && !bad_metadata &&
                                         !source_error && !writer_overflow;
                    if (!(file_ok && pixels_ok && writer_issued &&
                          (writer_finished ? writer_result_ok : writer_ok) &&
                          !bad_metadata && !source_error && !writer_overflow))
                        source_error <= 1'b1;
                end
            end
        end
    end

endmodule
