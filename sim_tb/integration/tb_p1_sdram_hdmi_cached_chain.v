`timescale 1ns/1ps

module tb_p1_sdram_hdmi_cached_chain;
    localparam integer TEST_WIDTH  = 64;
    localparam integer TEST_HEIGHT = 4;
    localparam integer TEST_HFP    = 4;
    localparam integer TEST_HSA    = 4;
    localparam integer TEST_HBP    = 8;   // HBLANK=16, 80% active duty.
    localparam integer TEST_VBP    = 200; // Preserve startup scheduler stress.

    reg pix_clk = 1'b0;
    reg sdr_clk = 1'b0;
    reg pix_rst_n = 1'b0;
    reg sdr_rst_n = 1'b0;
    reg frame_ready_sdr = 1'b0;

    // Pipeline abstract SDR-side read interface.
    wire        pipeline_rd_valid;
    wire [20:0] pipeline_rd_addr;
    wire        pipeline_rd_ready;
    wire        pipeline_rvalid;
    wire [31:0] pipeline_rdata;

    wire        fb_pixel_valid;
    wire [23:0] fb_pixel_data;
    wire        frame_boundary;
    wire        warm_ready;
    wire        frame_ready_pix;
    wire        underflow_sticky;
    wire        pipeline_protocol_error;

    // Arbiter -> cached adapter.
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

    // Cached adapter -> mock APUG011 application port.
    wire        App_wr_en;
    wire [20:0] App_wr_addr;
    wire [31:0] App_wr_din;
    wire [3:0]  App_wr_dm;
    wire        App_rd_en;
    wire [20:0] App_rd_addr;
    wire        Sdr_rd_en;
    wire [31:0] Sdr_rd_dout;
    wire        Sdr_init_done;
    wire        Sdr_init_ref_vld;
    wire        Sdr_busy;
    wire        App_ref_req;

    wire        adapter_ready_for_traffic;
    wire        adapter_protocol_error;
    wire        adapter_provider_fault;
    wire [31:0] adapter_app_read_words;
    wire [31:0] adapter_cache_hits;
    wire [31:0] adapter_cache_misses;

    wire        provider_protocol_error;
    wire [31:0] provider_app_read_count;

    integer checks = 0;
    integer capture = 0;
    integer captured_pixels = 0;
    integer expected_addr;
    integer i;

    always #20    pix_clk = ~pix_clk;   // 25 MHz
    always #3.333 sdr_clk = ~sdr_clk;   // ~150 MHz

    p1_sdram_hdmi_pipeline #(
        .FRAME_WIDTH     (TEST_WIDTH),
        .FRAME_HEIGHT    (TEST_HEIGHT),
        .FRAME_STRIDE    (TEST_WIDTH),
        .FRAME_BASE      (21'd0),
        .MAX_OUTSTANDING (8),
        .HFP             (TEST_HFP),
        .HSA             (TEST_HSA),
        .HBP             (TEST_HBP),
        .VFP             (1),
        .VSA             (1),
        .VBP             (TEST_VBP)
    ) pipeline (
        .pix_clk          (pix_clk),
        .pix_rst_n        (pix_rst_n),
        .sdr_clk          (sdr_clk),
        .sdr_rst_n        (sdr_rst_n),
        .frame_ready_sdr  (frame_ready_sdr),
        .sdr_mem_rd_valid (pipeline_rd_valid),
        .sdr_mem_rd_addr  (pipeline_rd_addr),
        .sdr_mem_rd_ready (pipeline_rd_ready),
        .sdr_mem_rvalid   (pipeline_rvalid),
        .sdr_mem_rdata    (pipeline_rdata),
        .fb_pixel_valid   (fb_pixel_valid),
        .fb_pixel_data    (fb_pixel_data),
        .frame_boundary   (frame_boundary),
        .warm_ready       (warm_ready),
        .frame_ready_pix  (frame_ready_pix),
        .underflow_sticky (underflow_sticky),
        .protocol_error   (pipeline_protocol_error)
    );

    sdram_arbiter #(
        .MAX_READ_OUTSTANDING(8)
    ) arbiter (
        .clk                     (sdr_clk),
        .rst_n                   (sdr_rst_n),
        .wr_valid                (1'b0),
        .wr_addr                 (21'd0),
        .wr_data                 (32'd0),
        .wr_ready                (),
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

    p1_sdram_cached_adapter adapter (
        .clk                        (sdr_clk),
        .rst_n                      (sdr_rst_n),
        .mem_wr_valid               (mem_wr_valid),
        .mem_wr_addr                (mem_wr_addr),
        .mem_wr_data                (mem_wr_data),
        .mem_wr_ready               (mem_wr_ready),
        .mem_rd_valid               (mem_rd_valid),
        .mem_rd_addr                (mem_rd_addr),
        .mem_rd_ready               (mem_rd_ready),
        .mem_rvalid                 (mem_rvalid),
        .mem_rdata                  (mem_rdata),
        .App_wr_en                  (App_wr_en),
        .App_wr_addr                (App_wr_addr),
        .App_wr_din                 (App_wr_din),
        .App_wr_dm                  (App_wr_dm),
        .App_rd_en                  (App_rd_en),
        .App_rd_addr                (App_rd_addr),
        .Sdr_rd_en                  (Sdr_rd_en),
        .Sdr_rd_dout                (Sdr_rd_dout),
        .Sdr_init_done              (Sdr_init_done),
        .Sdr_init_ref_vld           (Sdr_init_ref_vld),
        .Sdr_busy                   (Sdr_busy),
        .App_ref_req                (App_ref_req),
        .ready_for_traffic          (adapter_ready_for_traffic),
        .protocol_error             (adapter_protocol_error),
        .provider_fault             (adapter_provider_fault),
        .contention_seen            (),
        .read_outstanding_debug     (),
        .read_accept_count_debug    (),
        .write_accept_count_debug   (),
        .app_read_word_count_debug  (adapter_app_read_words),
        .app_write_word_count_debug (),
        .read_cache_hit_count_debug (adapter_cache_hits),
        .read_cache_miss_count_debug(adapter_cache_misses)
    );

    mock_apug011_app_port #(
        .MEM_WORDS(4096),
        .INIT_CYCLES(8),
        .READ_LATENCY(10)
    ) provider (
        .clk                        (sdr_clk),
        .rst                        (!sdr_rst_n),
        .App_wr_en                  (App_wr_en),
        .App_wr_addr                (App_wr_addr),
        .App_wr_din                 (App_wr_din),
        .App_wr_dm                  (App_wr_dm),
        .App_rd_en                  (App_rd_en),
        .App_rd_addr                (App_rd_addr),
        .Sdr_rd_en                  (Sdr_rd_en),
        .Sdr_rd_dout                (Sdr_rd_dout),
        .Sdr_init_done              (Sdr_init_done),
        .Sdr_init_ref_vld           (Sdr_init_ref_vld),
        .Sdr_busy                   (Sdr_busy),
        .force_refresh              (1'b0),
        .force_busy                 (1'b0),
        .inject_unsolicited_response(1'b0),
        .protocol_error             (provider_protocol_error),
        .app_read_count             (provider_app_read_count),
        .app_write_count            (),
        .masked_word_count          ()
    );

    always @(posedge pix_clk) begin
        if (pix_rst_n && warm_ready && frame_boundary)
            capture = 1;

        if (capture && fb_pixel_valid) begin
            expected_addr = captured_pixels;
            if (fb_pixel_data !== expected_addr[23:0]) begin
                $display("FAIL: cached-chain pixel %0d got=%h exp=%h underflow=%b pipeline_protocol=%b",
                         captured_pixels, fb_pixel_data, expected_addr[23:0],
                         underflow_sticky, pipeline_protocol_error);
                $finish;
            end

            captured_pixels = captured_pixels + 1;
            checks = checks + 1;

            if (captured_pixels == TEST_WIDTH * TEST_HEIGHT)
                capture = 0;
        end
    end

    initial begin
        repeat (5) @(posedge pix_clk);
        pix_rst_n = 1'b1;
        sdr_rst_n = 1'b1;

        wait (adapter_ready_for_traffic);

        // Simulation-only preload.  This test targets read bandwidth and
        // scheduling, not the already separately verified pattern writer.
        for (i = 0; i < TEST_WIDTH * TEST_HEIGHT; i = i + 1)
            provider.mem[i] = i;

        frame_ready_sdr = 1'b1;

        wait (captured_pixels == TEST_WIDTH * TEST_HEIGHT);
        repeat (10) @(posedge pix_clk);

        if (pipeline_protocol_error || arb_protocol_error ||
            adapter_protocol_error || adapter_provider_fault ||
            provider_protocol_error) begin
            $display("FAIL: protocol health pipeline=%b arb=%b adapter=%b provider_fault=%b mock=%b",
                     pipeline_protocol_error, arb_protocol_error,
                     adapter_protocol_error, adapter_provider_fault,
                     provider_protocol_error);
            $finish;
        end
        checks = checks + 1;

        if (underflow_sticky) begin
            $display("FAIL: cached-chain underflow asserted");
            $finish;
        end
        checks = checks + 1;

        // The scheduler may already prefetch the next frame by the time the
        // first captured frame completes, so do not require an exact final
        // provider count here.  Efficiency is checked exactly in the adapter
        // unit test; this chain test focuses on sustained no-underflow display.
        if (adapter_cache_misses == 32'd0 || adapter_cache_hits == 32'd0) begin
            $display("FAIL: cache path was not exercised hits=%0d misses=%0d",
                     adapter_cache_hits, adapter_cache_misses);
            $finish;
        end
        checks = checks + 1;

        if (adapter_app_read_words >= (adapter_cache_misses * 32'd16)) begin
            $display("FAIL: physical read expansion unexpectedly high app=%0d misses=%0d",
                     adapter_app_read_words, adapter_cache_misses);
            $finish;
        end
        checks = checks + 1;

        $display("PASS: p1_sdram_hdmi_cached_chain passed (checks=%0d, pixels=%0d, app_reads=%0d, hits=%0d, misses=%0d, underflow=%b)",
                 checks, captured_pixels, adapter_app_read_words,
                 adapter_cache_hits, adapter_cache_misses, underflow_sticky);
        $finish;
    end

    initial begin
        #5000000;
        $display("FAIL: cached-chain timeout pixels=%0d warm=%b underflow=%b pipeline_protocol=%b adapter_protocol=%b",
                 captured_pixels, warm_ready, underflow_sticky,
                 pipeline_protocol_error, adapter_protocol_error);
        $finish;
    end
endmodule
