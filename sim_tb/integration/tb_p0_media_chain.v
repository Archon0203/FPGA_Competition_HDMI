`timescale 1ns/1ps

// ================================================================
// Testbench : tb_p0_media_chain
// P0 final end-to-end integration candidate:
//
//   fragmented FAT32 sectors
//        -> fat32_file_reader
//        -> bmp_parser + bmp_pixel_stream
//        -> frame_buffer_manager + framebuffer_writer
//        -> sdram_arbiter -> mock_sdram
//        -> line_prefetcher -> line_buffer_pingpong
//        -> display-order RGB888 -> independent golden
//
// Goals:
//   * prove real file bytes, including FAT-chain jumps, reach final display RGB;
//   * prove BMP BGR/bottom-up/padding semantics survive framebuffer round-trip;
//   * prove 640-wide baseline produces a continuous line from line buffer;
//   * exercise multiple media loads without global reset;
//   * keep storage-side sector stalls and SDRAM-side stalls independent.
// ================================================================
module tb_p0_media_chain;
    localparam integer SECTOR_BYTES = 512;
    localparam integer FAT_LBA      = 1;
    localparam integer DATA_LBA     = 8;
    localparam integer MAX_SECT     = 64;
    localparam integer MAX_FILE     = 8192;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    integer errors = 0;
    integer checks = 0;

    // ---------------- Storage / FAT32 fixture ----------------
    reg media_start = 1'b0;
    reg [31:0] start_cluster = 32'd0;
    reg [31:0] file_size = 32'd0;
    reg [7:0] sectors_per_cluster = 8'd1;

    wire sector_req;
    wire [31:0] sector_lba;
    reg sector_ready = 1'b0;
    reg sector_din_valid = 1'b0;
    reg [7:0] sector_din = 8'd0;

    wire file_byte_valid;
    wire [7:0] file_byte;
    wire fat_done;
    wire fat_ok;

    reg [7:0] disk [0:MAX_SECT-1][0:SECTOR_BYTES-1];
    reg [7:0] file_mem [0:MAX_FILE-1];
    integer file_len;
    integer chain [0:15];
    integer chain_len;

    integer sd_transactions = 0;
    integer sd_fat_transactions = 0;
    integer sd_data_transactions = 0;

    // ---------------- BMP parser / pixel stream ----------------
    wire bmp_header_done;
    wire bmp_ok;
    wire [15:0] bmp_width;
    wire [15:0] bmp_height;
    wire [5:0]  bmp_bpp;
    wire [23:0] bmp_data_offset;

    wire bmp_pixel_valid;
    wire [7:0] bmp_pixel_r;
    wire [7:0] bmp_pixel_g;
    wire [7:0] bmp_pixel_b;
    wire [15:0] bmp_pixel_x;
    wire [15:0] bmp_pixel_y;
    wire bmp_pixels_done;
    wire bmp_pixels_ok;

    // Integration glue: start framebuffer load as soon as the validated
    // BITMAPINFOHEADER fields are available, well before data_offset>=54.
    reg load_start = 1'b0;
    reg [15:0] load_width = 16'd0;
    reg [15:0] load_height = 16'd0;
    reg [15:0] load_stride_words = 16'd0;
    reg load_issued = 1'b0;

    wire load_ready;
    wire load_accept;
    wire manager_writer_start;
    wire [20:0] write_base;
    wire [15:0] write_width;
    wire [15:0] write_height;
    wire [15:0] write_stride_words;
    reg display_frame_boundary = 1'b0;
    wire [20:0] read_base;
    wire [15:0] read_width;
    wire [15:0] read_height;
    wire [15:0] read_stride_words;
    wire read_frame_valid;
    wire write_in_progress;
    wire pending_swap;
    wire swap_pulse;
    wire load_fail_pulse;
    wire read_buffer_sel;
    wire write_buffer_sel;
    wire manager_config_error;

    // ---------------- framebuffer_writer ----------------
    wire pixel_ready;
    wire writer_mem_valid;
    wire [20:0] writer_mem_addr;
    wire [31:0] writer_mem_data;
    wire writer_mem_ready;
    wire writer_busy;
    wire writer_done;
    wire writer_ok;
    wire writer_overflow;

    // ---------------- line_prefetcher ----------------
    reg prefetch_start = 1'b0;
    reg [15:0] prefetch_line_index = 16'd0;
    wire prefetch_mem_valid;
    wire [20:0] prefetch_mem_addr;
    wire prefetch_mem_ready;
    wire prefetch_rvalid;
    wire [31:0] prefetch_rdata;
    wire prefetch_busy;
    wire prefetch_done;
    wire prefetch_ok;
    wire prefetch_timeout_error;
    wire prefetch_protocol_error;
    wire prefetch_recovery_required;
    wire [15:0] prefetch_issued_debug;
    wire [15:0] prefetch_received_debug;

    // ---------------- line buffer ----------------
    wire lb_fill_ready;
    wire lb_fill_start;
    wire [15:0] lb_fill_line_index;
    wire [15:0] lb_fill_width;
    wire lb_fill_valid;
    wire [23:0] lb_fill_data;
    wire lb_fill_done;
    wire lb_fill_ok;
    wire lb_fill_accept;
    wire lb_fill_commit_pulse;
    wire lb_fill_fail_pulse;

    reg lb_read_start = 1'b0;
    reg [15:0] lb_read_line_index = 16'd0;
    reg [15:0] lb_read_width = 16'd0;
    wire lb_pixel_valid;
    wire [23:0] lb_pixel_data;
    wire lb_line_done;
    wire lb_underflow_pulse;
    wire lb_underflow_sticky;
    wire lb_protocol_error;
    wire lb_fill_active;
    wire lb_read_active;
    wire lb_bank0_ready;
    wire lb_bank1_ready;

    // ---------------- arbiter + mock SDRAM ----------------
    wire mem_wr_valid;
    wire [20:0] mem_wr_addr;
    wire [31:0] mem_wr_data;
    wire mem_wr_ready;
    wire mem_rd_valid;
    wire [20:0] mem_rd_addr;
    wire mem_rd_ready;
    wire mem_rvalid;
    wire [31:0] mem_rdata;

    wire arb_protocol_error;
    wire arb_contention_seen;
    wire [15:0] arb_outstanding;
    wire [31:0] arb_read_count;
    wire [31:0] arb_write_count;

    reg random_sdram_stalls_enable = 1'b1;
    wire mock_range_error;
    wire mock_queue_error;
    wire mock_write_commit_pulse;
    wire [20:0] mock_write_commit_addr;
    wire [31:0] mock_write_commit_data;
    wire mock_read_response_pulse;
    wire [20:0] mock_read_response_addr;
    wire [15:0] mock_pending_reads;

    // ---------------- DUT chain ----------------
    fat32_file_reader #(
        .SECTOR_BYTES(SECTOR_BYTES),
        .STALL_TIMEOUT_CYCLES(10000)
    ) u_file_reader (
        .clk(clk), .rst_n(rst_n), .start(media_start),
        .start_cluster(start_cluster), .file_size(file_size),
        .fat_lba_base(FAT_LBA), .data_lba_base(DATA_LBA),
        .sectors_per_cluster(sectors_per_cluster),
        .sector_req(sector_req), .sector_lba(sector_lba),
        .sector_ready(sector_ready), .din_valid(sector_din_valid), .din(sector_din),
        .byte_valid(file_byte_valid), .byte_data(file_byte),
        .done(fat_done), .ok(fat_ok)
    );

    bmp_parser u_bmp_parser (
        .clk(clk), .rst_n(rst_n), .start(media_start),
        .din(file_byte), .din_valid(file_byte_valid),
        .done(bmp_header_done), .bmp_ok(bmp_ok),
        .width(bmp_width), .height(bmp_height),
        .bpp(bmp_bpp), .data_offset(bmp_data_offset)
    );

    bmp_pixel_stream u_bmp_pixels (
        .clk(clk), .rst_n(rst_n), .start(media_start),
        .din(file_byte), .din_valid(file_byte_valid),
        .header_done(bmp_header_done), .bmp_ok(bmp_ok),
        .width(bmp_width), .height(bmp_height),
        .file_done(fat_done), .file_ok(fat_ok),
        .pixel_valid(bmp_pixel_valid),
        .pixel_r(bmp_pixel_r), .pixel_g(bmp_pixel_g), .pixel_b(bmp_pixel_b),
        .pixel_x(bmp_pixel_x), .pixel_y(bmp_pixel_y),
        .done(bmp_pixels_done), .ok(bmp_pixels_ok)
    );

    frame_buffer_manager u_manager (
        .clk(clk), .rst_n(rst_n),
        .load_start(load_start), .load_width(load_width), .load_height(load_height),
        .load_stride_words(load_stride_words), .load_ready(load_ready),
        .load_accept(load_accept), .writer_start(manager_writer_start),
        .write_base(write_base), .write_width(write_width), .write_height(write_height),
        .write_stride_words(write_stride_words),
        .writer_done(writer_done), .writer_ok(writer_ok),
        .display_frame_boundary(display_frame_boundary),
        .read_base(read_base), .read_width(read_width), .read_height(read_height),
        .read_stride_words(read_stride_words), .read_frame_valid(read_frame_valid),
        .write_in_progress(write_in_progress), .pending_swap(pending_swap),
        .swap_pulse(swap_pulse), .load_fail_pulse(load_fail_pulse),
        .read_buffer_sel(read_buffer_sel), .write_buffer_sel(write_buffer_sel),
        .config_error(manager_config_error)
    );

    framebuffer_writer #(.PIXEL_FIFO_DEPTH(16)) u_writer (
        .clk(clk), .rst_n(rst_n), .start(manager_writer_start),
        .frame_base(write_base), .frame_width(write_width), .frame_height(write_height),
        .frame_stride_words(write_stride_words),
        .pixel_valid(bmp_pixel_valid),
        .pixel_r(bmp_pixel_r), .pixel_g(bmp_pixel_g), .pixel_b(bmp_pixel_b),
        .pixel_x(bmp_pixel_x), .pixel_y(bmp_pixel_y), .pixel_ready(pixel_ready),
        .source_done(bmp_pixels_done), .source_ok(bmp_pixels_ok),
        .mem_wr_valid(writer_mem_valid), .mem_wr_addr(writer_mem_addr),
        .mem_wr_data(writer_mem_data), .mem_wr_ready(writer_mem_ready),
        .busy(writer_busy), .done(writer_done), .ok(writer_ok), .overflow(writer_overflow)
    );

    sdram_arbiter #(.MAX_READ_OUTSTANDING(16)) u_arbiter (
        .clk(clk), .rst_n(rst_n),
        .wr_valid(writer_mem_valid), .wr_addr(writer_mem_addr), .wr_data(writer_mem_data),
        .wr_ready(writer_mem_ready),
        .rd_valid(prefetch_mem_valid), .rd_addr(prefetch_mem_addr), .rd_ready(prefetch_mem_ready),
        .rd_rvalid(prefetch_rvalid), .rd_rdata(prefetch_rdata),
        .mem_wr_valid(mem_wr_valid), .mem_wr_addr(mem_wr_addr), .mem_wr_data(mem_wr_data),
        .mem_wr_ready(mem_wr_ready),
        .mem_rd_valid(mem_rd_valid), .mem_rd_addr(mem_rd_addr), .mem_rd_ready(mem_rd_ready),
        .mem_rvalid(mem_rvalid), .mem_rdata(mem_rdata),
        .protocol_error(arb_protocol_error), .contention_seen(arb_contention_seen),
        .rd_outstanding_debug(arb_outstanding),
        .read_accept_count_debug(arb_read_count), .write_accept_count_debug(arb_write_count)
    );

    mock_sdram #(
        .DEPTH_WORDS(400000), .MAX_PENDING_READS(32),
        .MIN_READ_LATENCY(1), .MAX_READ_LATENCY(7)
    ) u_mock (
        .clk(clk), .rst_n(rst_n),
        .wr_valid(mem_wr_valid), .wr_addr(mem_wr_addr), .wr_data(mem_wr_data), .wr_ready(mem_wr_ready),
        .rd_valid(mem_rd_valid), .rd_addr(mem_rd_addr), .rd_ready(mem_rd_ready),
        .rvalid(mem_rvalid), .rdata(mem_rdata),
        .random_stalls_enable(random_sdram_stalls_enable),
        .force_wr_stall(1'b0), .force_rd_stall(1'b0), .force_resp_stall(1'b0),
        .range_error(mock_range_error), .queue_error(mock_queue_error),
        .write_commit_pulse(mock_write_commit_pulse), .write_commit_addr(mock_write_commit_addr),
        .write_commit_data(mock_write_commit_data),
        .read_response_pulse(mock_read_response_pulse), .read_response_addr(mock_read_response_addr),
        .pending_reads_debug(mock_pending_reads)
    );

    line_prefetcher #(.MAX_OUTSTANDING(8), .STALL_TIMEOUT_CYCLES(5000)) u_prefetch (
        .clk(clk), .rst_n(rst_n), .start(prefetch_start),
        .frame_base(read_base), .frame_width(read_width), .frame_height(read_height),
        .frame_stride_words(read_stride_words), .line_index(prefetch_line_index),
        .mem_rd_valid(prefetch_mem_valid), .mem_rd_addr(prefetch_mem_addr),
        .mem_rd_ready(prefetch_mem_ready), .mem_rvalid(prefetch_rvalid), .mem_rdata(prefetch_rdata),
        .lb_fill_ready(lb_fill_ready), .lb_fill_start(lb_fill_start),
        .lb_fill_line_index(lb_fill_line_index), .lb_fill_width(lb_fill_width),
        .lb_fill_valid(lb_fill_valid), .lb_fill_data(lb_fill_data),
        .lb_fill_done(lb_fill_done), .lb_fill_ok(lb_fill_ok),
        .busy(prefetch_busy), .done(prefetch_done), .ok(prefetch_ok),
        .timeout_error(prefetch_timeout_error), .protocol_error(prefetch_protocol_error),
        .recovery_required(prefetch_recovery_required),
        .issued_count_debug(prefetch_issued_debug), .received_count_debug(prefetch_received_debug)
    );

    line_buffer_pingpong #(.MAX_LINE_PIXELS(640)) u_linebuf (
        .clk(clk), .rst_n(rst_n),
        .fill_ready(lb_fill_ready), .fill_start(lb_fill_start),
        .fill_line_index(lb_fill_line_index), .fill_width(lb_fill_width), .fill_accept(lb_fill_accept),
        .fill_valid(lb_fill_valid), .fill_data(lb_fill_data),
        .fill_done(lb_fill_done), .fill_ok(lb_fill_ok),
        .fill_commit_pulse(lb_fill_commit_pulse), .fill_fail_pulse(lb_fill_fail_pulse),
        .read_start(lb_read_start), .read_line_index(lb_read_line_index), .read_width(lb_read_width),
        .pixel_valid(lb_pixel_valid), .pixel_data(lb_pixel_data), .line_done(lb_line_done),
        .underflow_pulse(lb_underflow_pulse), .underflow_sticky(lb_underflow_sticky),
        .protocol_error(lb_protocol_error), .fill_active(lb_fill_active), .read_active(lb_read_active),
        .bank0_ready(lb_bank0_ready), .bank1_ready(lb_bank1_ready)
    );

    // ---------------- Early-header -> manager load glue ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            load_start        <= 1'b0;
            load_width        <= 16'd0;
            load_height       <= 16'd0;
            load_stride_words <= 16'd0;
            load_issued       <= 1'b0;
        end else begin
            load_start <= 1'b0;
            if (media_start)
                load_issued <= 1'b0;

            // bmp_ok becomes true after compression byte 33 has been captured.
            // Baseline BITMAPINFOHEADER data starts no earlier than byte 54,
            // leaving ample cycles to arm the framebuffer writer.
            if (!load_issued && bmp_ok &&
                (bmp_width != 16'd0) && (bmp_height != 16'd0) &&
                !bmp_height[15] && (bmp_bpp == 6'd24) &&
                (bmp_data_offset >= 24'd54) && load_ready) begin
                load_width        <= bmp_width;
                load_height       <= bmp_height;
                load_stride_words <= bmp_width;
                load_start        <= 1'b1;
                load_issued       <= 1'b1;
            end
        end
    end

    // Catch a real integration failure: valid pixels must never arrive before
    // the writer has been armed by parsed metadata.
    always @(posedge clk) begin
        if (rst_n && bmp_pixel_valid && !writer_busy) begin
            $display("ERROR: BMP pixel arrived before framebuffer_writer was busy");
            errors = errors + 1;
        end
        if (rst_n && bmp_pixel_valid && !pixel_ready) begin
            $display("ERROR: BMP valid-only stream outran framebuffer_writer FIFO");
            errors = errors + 1;
        end
    end

    // ---------------- Independent RGB source/golden ----------------
    function [7:0] build_r;
        input [7:0] seed; input integer x; input integer y; integer v;
        begin v = seed + x*5 + y*3; build_r = v[7:0]; end
    endfunction
    function [7:0] build_g;
        input [7:0] seed; input integer x; input integer y; integer v;
        begin v = 8'h30 + seed*2 + x*3 + y*7; build_g = v[7:0]; end
    endfunction
    function [7:0] build_b;
        input [7:0] seed; input integer x; input integer y; integer v;
        begin v = 8'h80 + seed + x*11 + y; build_b = v[7:0]; end
    endfunction

    // Deliberately separate scoreboard math from BMP builder helpers.
    function [23:0] expected_rgb;
        input [7:0] seed; input integer x; input integer y;
        integer vr, vg, vb;
        reg [7:0] er, eg, eb;
        begin
            vr = seed + (5*x) + (3*y);
            vg = 48 + (2*seed) + (3*x) + (7*y);
            vb = 128 + seed + (11*x) + y;
            er = vr[7:0]; eg = vg[7:0]; eb = vb[7:0];
            expected_rgb = {er,eg,eb};
        end
    endfunction

    task check_int;
        input integer got;
        input integer exp;
        input [8*120-1:0] msg;
        begin
            checks = checks + 1;
            if (got !== exp) begin
                $display("ERROR: %s got=%0d exp=%0d", msg, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    task check_rgb;
        input [23:0] got;
        input [23:0] exp;
        input [8*120-1:0] msg;
        begin
            checks = checks + 1;
            if (got !== exp) begin
                $display("ERROR: %s got=%06x exp=%06x", msg, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    task clear_disk;
        integer s, b;
        begin
            for (s = 0; s < MAX_SECT; s = s + 1)
                for (b = 0; b < SECTOR_BYTES; b = b + 1)
                    disk[s][b] = 8'h00;
        end
    endtask

    task set_fat_entry;
        input integer cluster;
        input [31:0] value;
        integer lba, off;
        begin
            lba = FAT_LBA + (cluster * 4) / SECTOR_BYTES;
            off = (cluster * 4) % SECTOR_BYTES;
            disk[lba][off+0] = value[7:0];
            disk[lba][off+1] = value[15:8];
            disk[lba][off+2] = value[23:16];
            disk[lba][off+3] = value[31:24];
        end
    endtask

    task build_bmp;
        input integer w;
        input integer h;
        input integer data_off;
        input [7:0] seed;
        integer i, row, x, y_disp, row_bytes, pad, idx, fsize;
        begin
            for (i = 0; i < MAX_FILE; i = i + 1)
                file_mem[i] = 8'h00;

            row_bytes = w * 3;
            pad = (4 - (row_bytes & 3)) & 3;
            fsize = data_off + (row_bytes + pad) * h;

            file_mem[0] = 8'h42; file_mem[1] = 8'h4D;
            file_mem[2] = fsize[7:0];
            file_mem[3] = (fsize >> 8) & 8'hFF;
            file_mem[4] = (fsize >> 16) & 8'hFF;
            file_mem[5] = (fsize >> 24) & 8'hFF;
            file_mem[6] = 0; file_mem[7] = 0; file_mem[8] = 0; file_mem[9] = 0;
            file_mem[10] = data_off[7:0];
            file_mem[11] = (data_off >> 8) & 8'hFF;
            file_mem[12] = (data_off >> 16) & 8'hFF;
            file_mem[13] = (data_off >> 24) & 8'hFF;
            file_mem[14] = 8'h28; file_mem[15] = 0; file_mem[16] = 0; file_mem[17] = 0;
            file_mem[18] = w[7:0];
            file_mem[19] = (w >> 8) & 8'hFF;
            file_mem[20] = (w >> 16) & 8'hFF;
            file_mem[21] = (w >> 24) & 8'hFF;
            file_mem[22] = h[7:0];
            file_mem[23] = (h >> 8) & 8'hFF;
            file_mem[24] = (h >> 16) & 8'hFF;
            file_mem[25] = (h >> 24) & 8'hFF;
            file_mem[26] = 8'h01; file_mem[27] = 8'h00;
            file_mem[28] = 8'h18; file_mem[29] = 8'h00;
            file_mem[30] = 0; file_mem[31] = 0; file_mem[32] = 0; file_mem[33] = 0;
            for (i = 34; i < data_off; i = i + 1)
                file_mem[i] = 8'hEE;

            idx = data_off;
            for (row = 0; row < h; row = row + 1) begin
                y_disp = h - 1 - row;
                for (x = 0; x < w; x = x + 1) begin
                    file_mem[idx] = build_b(seed,x,y_disp); idx = idx + 1;
                    file_mem[idx] = build_g(seed,x,y_disp); idx = idx + 1;
                    file_mem[idx] = build_r(seed,x,y_disp); idx = idx + 1;
                end
                if (pad > 0) begin file_mem[idx] = 8'hA5; idx = idx + 1; end
                if (pad > 1) begin file_mem[idx] = 8'h5A; idx = idx + 1; end
                if (pad > 2) begin file_mem[idx] = 8'hC3; idx = idx + 1; end
            end
            file_len = idx;
        end
    endtask

    task install_file_on_chain;
        integer ci, i, lba, off;
        begin
            clear_disk;
            for (ci = 0; ci < chain_len; ci = ci + 1) begin
                if (ci == chain_len-1)
                    set_fat_entry(chain[ci], 32'h0FFFFFFF);
                else
                    set_fat_entry(chain[ci], chain[ci+1]);
            end

            for (i = 0; i < file_len; i = i + 1) begin
                ci = i / SECTOR_BYTES;
                if (ci >= chain_len) begin
                    $display("ERROR: file needs more clusters than supplied chain");
                    errors = errors + 1;
                end else begin
                    lba = DATA_LBA + (chain[ci] - 2);
                    off = i % SECTOR_BYTES;
                    disk[lba][off] = file_mem[i];
                end
            end
        end
    endtask

    // ---------------- randomized SD sector model ----------------
    reg block_busy = 1'b0;
    reg [31:0] active_lba = 32'd0;
    reg [8:0] rd_index = 9'd0;
    reg [3:0] startup_delay = 4'd0;
    reg release_cycle = 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            block_busy <= 1'b0;
            active_lba <= 32'd0;
            rd_index <= 9'd0;
            startup_delay <= 4'd0;
            release_cycle <= 1'b0;
            sector_ready <= 1'b0;
            sector_din_valid <= 1'b0;
            sector_din <= 8'hFF;
            sd_transactions <= 0;
            sd_fat_transactions <= 0;
            sd_data_transactions <= 0;
        end else begin
            sector_din_valid <= 1'b0;
            if (release_cycle) begin
                sector_ready <= 1'b0;
                release_cycle <= 1'b0;
            end else if (!block_busy) begin
                sector_ready <= 1'b0;
                if (sector_req) begin
                    block_busy <= 1'b1;
                    active_lba <= sector_lba;
                    rd_index <= 9'd0;
                    startup_delay <= ($random & 4'h3);
                    sector_ready <= 1'b1;
                    sd_transactions <= sd_transactions + 1;
                    if (sector_lba == FAT_LBA)
                        sd_fat_transactions <= sd_fat_transactions + 1;
                    else
                        sd_data_transactions <= sd_data_transactions + 1;
                end
            end else begin
                sector_ready <= 1'b1;
                if (startup_delay != 0) begin
                    startup_delay <= startup_delay - 1'b1;
                end else if (($random & 32'h3) != 0) begin
                    sector_din_valid <= 1'b1;
                    if (active_lba < MAX_SECT)
                        sector_din <= disk[active_lba][rd_index];
                    else begin
                        sector_din <= 8'hE1;
                        $display("ERROR: SD model LBA out of fixture range: %0d", active_lba);
                        errors = errors + 1;
                    end

                    if (rd_index == SECTOR_BYTES-1) begin
                        block_busy <= 1'b0;
                        rd_index <= 9'd0;
                        sector_ready <= 1'b1;
                        release_cycle <= 1'b1;
                    end else begin
                        rd_index <= rd_index + 1'b1;
                    end
                end
            end
        end
    end

    task pulse_media_start;
        input integer first_cluster;
        begin
            while (!load_ready) @(negedge clk);
            start_cluster = first_cluster;
            file_size = file_len;
            sectors_per_cluster = 1;
            @(negedge clk);
            media_start = 1'b1;
            @(negedge clk);
            media_start = 1'b0;
        end
    endtask

    task wait_media_load_complete;
        input integer max_cycles;
        integer c;
        begin
            c = 0;
            // writer_done is a one-cycle event and can occur before fat_done
            // (fat reader still finishes the physical 512-byte transaction).
            // pending_swap is the persistent proof that writer_done/ok was consumed.
            while ((!fat_done || !bmp_pixels_done || !pending_swap) && c < max_cycles) begin
                @(negedge clk);
                c = c + 1;
            end
            if (c >= max_cycles) begin
                $display("ERROR: timeout waiting media load completion");
                errors = errors + 1;
            end
            check_int(fat_ok, 1, "fat32 file reader success");
            check_int(bmp_ok, 1, "BMP header valid");
            check_int(bmp_pixels_ok, 1, "BMP pixel stream success");
            check_int(writer_ok, 1, "framebuffer writer success");
            check_int(writer_overflow, 0, "writer no overflow");
            check_int(load_issued, 1, "header metadata armed writer");
        end
    endtask

    task wait_swap;
        begin
            while (!pending_swap) @(negedge clk);
            @(negedge clk);
            display_frame_boundary = 1'b1;
            @(negedge clk);
            display_frame_boundary = 1'b0;
            repeat (2) @(negedge clk);
            check_int(read_frame_valid, 1, "front frame valid after swap");
            check_int(pending_swap, 0, "pending swap cleared");
        end
    endtask

    task prefetch_and_check_line;
        input [7:0] seed;
        input integer line_no;
        integer count;
        integer gaps;
        reg started;
        reg [23:0] exp;
        begin
            while (prefetch_busy) @(negedge clk);
            @(negedge clk);
            prefetch_line_index = line_no;
            prefetch_start = 1'b1;
            @(negedge clk);
            prefetch_start = 1'b0;

            while (!prefetch_done) @(negedge clk);
            check_int(prefetch_ok, 1, "prefetch success");
            check_int(prefetch_timeout_error, 0, "prefetch no timeout");
            check_int(prefetch_protocol_error, 0, "prefetch no protocol error");
            check_int(prefetch_recovery_required, 0, "prefetch no quarantine");

            @(negedge clk);
            lb_read_line_index = line_no;
            lb_read_width = read_width;
            lb_read_start = 1'b1;
            @(negedge clk);
            lb_read_start = 1'b0;

            count = 0;
            gaps = 0;
            started = 1'b0;
            while (count < read_width) begin
                @(negedge clk);
                if (lb_pixel_valid) begin
                    if (started && gaps != 0) begin
                        $display("ERROR: active-line pixel_valid gap, line=%0d x=%0d", line_no, count);
                        errors = errors + 1;
                    end
                    gaps = 0;
                    started = 1'b1;
                    exp = expected_rgb(seed, count, line_no);
                    check_rgb(lb_pixel_data, exp, "end-to-end display RGB");
                    count = count + 1;
                end else if (started) begin
                    gaps = gaps + 1;
                end
            end
            check_int(lb_line_done, 1, "line done at final pixel");
            check_int(lb_underflow_pulse, 0, "no underflow pulse");
        end
    endtask

    task check_all_lines;
        input [7:0] seed;
        integer y;
        begin
            for (y = 0; y < read_height; y = y + 1)
                prefetch_and_check_line(seed, y);
        end
    endtask

    integer tx0, fat0, data0;

    initial begin
        clear_disk;
        media_start = 0;
        prefetch_start = 0;
        lb_read_start = 0;
        display_frame_boundary = 0;
        random_sdram_stalls_enable = 1;

        @(negedge clk); rst_n = 1'b0;
        repeat (5) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        repeat (4) @(posedge clk);

        $display("CASE-GOLDEN fixed RGB sanity");
        check_rgb(expected_rgb(8'h12,0,0), 24'h125492, "golden seed12 x0 y0");
        check_rgb(expected_rgb(8'h12,1,2), 24'h1D659F, "golden seed12 x1 y2");
        check_int(manager_config_error, 0, "manager map valid");

        // ------------------------------------------------------------------
        // CASE0: fragmented 17x12 BMP. File >512B, chain jumps 3 -> 7.
        // width=17 also exercises 1-byte BMP row padding.
        // ------------------------------------------------------------------
        $display("CASE0 fragmented FAT32 17x12 BMP -> full display RGB");
        build_bmp(17, 12, 54, 8'h12);
        chain_len = 2; chain[0] = 3; chain[1] = 7;
        install_file_on_chain;
        tx0 = sd_transactions; fat0 = sd_fat_transactions; data0 = sd_data_transactions;
        pulse_media_start(chain[0]);
        wait_media_load_complete(120000);
        check_int(bmp_width, 17, "case0 parsed width");
        check_int(bmp_height, 12, "case0 parsed height");
        check_int((sd_fat_transactions-fat0) >= 1, 1, "case0 FAT traversal occurred");
        check_int((sd_data_transactions-data0) >= 2, 1, "case0 two fragmented data sectors read");
        wait_swap;
        check_int(read_buffer_sel, 1, "case0 Image B front");
        check_int(read_width, 17, "case0 front width");
        check_int(read_height, 12, "case0 front height");
        check_all_lines(8'h12);

        // ------------------------------------------------------------------
        // CASE1: 640x2 baseline, 3894-byte file over 8 deliberately
        // non-contiguous clusters. Validates width=640 active-line continuity.
        // ------------------------------------------------------------------
        $display("CASE1 fragmented FAT32 640x2 baseline -> full display RGB");
        build_bmp(640, 2, 54, 8'h25);
        chain_len = 8;
        chain[0]=3; chain[1]=7; chain[2]=5; chain[3]=12;
        chain[4]=9; chain[5]=20; chain[6]=4; chain[7]=15;
        install_file_on_chain;
        tx0 = sd_transactions; fat0 = sd_fat_transactions; data0 = sd_data_transactions;
        pulse_media_start(chain[0]);
        wait_media_load_complete(300000);
        check_int(bmp_width, 640, "case1 parsed width");
        check_int(bmp_height, 2, "case1 parsed height");
        check_int((sd_fat_transactions-fat0) >= 7, 1, "case1 repeated FAT traversal");
        check_int((sd_data_transactions-data0) >= 8, 1, "case1 eight data clusters read");
        wait_swap;
        check_int(read_buffer_sel, 0, "case1 Image A front");
        check_int(read_width, 640, "case1 baseline width");
        check_int(read_height, 2, "case1 baseline height");
        check_all_lines(8'h25);

        // ------------------------------------------------------------------
        // CASE2: no-reset third media item, data_offset=70 with non-pixel gap.
        // Confirms chain reuse and parser/pixel-stream gap handling end-to-end.
        // ------------------------------------------------------------------
        $display("CASE2 no-reset data_offset=70 13x4 -> full display RGB");
        random_sdram_stalls_enable = 1'b0;
        build_bmp(13, 4, 70, 8'h39);
        chain_len = 1; chain[0] = 6;
        install_file_on_chain;
        pulse_media_start(chain[0]);
        wait_media_load_complete(80000);
        check_int(bmp_data_offset, 70, "case2 parsed data_offset");
        wait_swap;
        check_int(read_buffer_sel, 1, "case2 Image B front again");
        check_all_lines(8'h39);

        $display("CASE3 final integration status");
        check_int(arb_protocol_error, 0, "arbiter no protocol error");
        check_int(arb_outstanding, 0, "arbiter no outstanding reads");
        check_int(mock_pending_reads, 0, "mock no pending reads");
        check_int(mock_range_error, 0, "mock no range error");
        check_int(mock_queue_error, 0, "mock no queue error");
        check_int(lb_protocol_error, 0, "line buffer no protocol error");
        check_int(lb_underflow_sticky, 0, "line buffer no underflow sticky");
        check_int(prefetch_recovery_required, 0, "prefetch no recovery quarantine");
        check_int(load_fail_pulse, 0, "manager no final load failure");
        check_int((arb_write_count > 1400), 1, "end-to-end writes crossed arbiter");
        check_int((arb_read_count > 1400), 1, "end-to-end reads crossed arbiter");

        if (errors == 0)
            $display("PASS: P0 media chain end-to-end all cases passed (checks=%0d)", checks);
        else
            $display("FAIL: P0 media chain end-to-end errors=%0d checks=%0d", errors, checks);
        $finish;
    end
endmodule
