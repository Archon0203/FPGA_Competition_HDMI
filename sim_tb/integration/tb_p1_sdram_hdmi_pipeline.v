`timescale 1ns/1ps

module tb_p1_sdram_hdmi_pipeline;
    // This integration TB intentionally preserves the real P1-05A clock and
    // horizontal-bandwidth ratios instead of using an extremely tiny raster.
    // The pipeline has a fixed CDC/prefetch setup latency per line; shrinking a
    // line to only a handful of pixels makes that fixed latency dominate and
    // creates an artificial line-2 underflow that does not model 640x480.
    localparam integer TEST_WIDTH  = 64;
    localparam integer TEST_HEIGHT = 4;
    localparam integer TEST_HFP    = 4;
    localparam integer TEST_HSA    = 4;
    localparam integer TEST_HBP    = 8;  // HBLANK=16 => 20% of HTOTAL, like 160/800.
    // Deliberately make the pre-active vertical interval longer than the
    // prefetch watchdog.  This reproduces the board-only startup corner where
    // line 0/1 are warm but both ping-pong banks remain occupied until the next
    // safe frame boundary.  A correct scheduler must NOT launch line 2 while
    // lb_fill_ready is low.
    localparam integer TEST_VBP    = 200;

    reg pix_clk = 1'b0;
    reg sdr_clk = 1'b0;
    reg pix_rst_n = 1'b0;
    reg sdr_rst_n = 1'b0;
    reg frame_ready_sdr = 1'b0;

    wire sdr_rd_valid;
    wire [20:0] sdr_rd_addr;
    reg  sdr_rd_ready = 1'b1;
    reg  sdr_rvalid = 1'b0;
    reg  [31:0] sdr_rdata = 32'd0;

    wire fb_pixel_valid;
    wire [23:0] fb_pixel_data;
    wire frame_boundary;
    wire warm_ready;
    wire frame_ready_pix;
    wire underflow_sticky;
    wire protocol_error;

    reg pending_valid = 1'b0;
    reg [20:0] pending_addr = 21'd0;

    integer checks = 0;
    integer capture = 0;
    integer captured_pixels = 0;
    integer expected_addr;

    always #20    pix_clk = ~pix_clk;   // 25 MHz pixel domain.
    always #3.333 sdr_clk = ~sdr_clk;   // ~150 MHz SDRAM-side relationship.

    p1_sdram_hdmi_pipeline #(
        .FRAME_WIDTH(TEST_WIDTH),
        .FRAME_HEIGHT(TEST_HEIGHT),
        .FRAME_STRIDE(TEST_WIDTH),
        .FRAME_BASE(0),
        .MAX_OUTSTANDING(8),
        .HFP(TEST_HFP),
        .HSA(TEST_HSA),
        .HBP(TEST_HBP),
        .VFP(1),
        .VSA(1),
        .VBP(TEST_VBP)
    ) dut (
        .pix_clk(pix_clk),
        .pix_rst_n(pix_rst_n),
        .sdr_clk(sdr_clk),
        .sdr_rst_n(sdr_rst_n),
        .frame_ready_sdr(frame_ready_sdr),
        .sdr_mem_rd_valid(sdr_rd_valid),
        .sdr_mem_rd_addr(sdr_rd_addr),
        .sdr_mem_rd_ready(sdr_rd_ready),
        .sdr_mem_rvalid(sdr_rvalid),
        .sdr_mem_rdata(sdr_rdata),
        .fb_pixel_valid(fb_pixel_valid),
        .fb_pixel_data(fb_pixel_data),
        .frame_boundary(frame_boundary),
        .warm_ready(warm_ready),
        .frame_ready_pix(frame_ready_pix),
        .underflow_sticky(underflow_sticky),
        .protocol_error(protocol_error)
    );

    // Ordered one-cycle response memory: lower 24 bits equal the word address.
    // The model runs in the SDRAM-side clock domain and deliberately accepts
    // every request so this test measures the pipeline/CDC scheduling itself.
    always @(posedge sdr_clk) begin
        if (!sdr_rst_n) begin
            pending_valid <= 1'b0;
            sdr_rvalid <= 1'b0;
            pending_addr <= 21'd0;
            sdr_rdata <= 32'd0;
        end else begin
            sdr_rvalid <= pending_valid;
            if (pending_valid)
                sdr_rdata <= {11'd0, pending_addr};
            pending_valid <= sdr_rd_valid && sdr_rd_ready;
            if (sdr_rd_valid && sdr_rd_ready)
                pending_addr <= sdr_rd_addr;
        end
    end

    always @(posedge pix_clk) begin
        if (pix_rst_n && warm_ready && frame_boundary)
            capture = 1;

        if (capture && fb_pixel_valid) begin
            expected_addr = captured_pixels;
            if (fb_pixel_data !== expected_addr[23:0]) begin
                $display("FAIL: pixel %0d got=%h exp=%h warm=%b underflow=%b protocol=%b",
                         captured_pixels, fb_pixel_data, expected_addr[23:0],
                         warm_ready, underflow_sticky, protocol_error);
                $finish;
            end

            captured_pixels = captured_pixels + 1;
            checks = checks + 1;

            if (captured_pixels == TEST_WIDTH * TEST_HEIGHT)
                capture = 0;
        end
    end

    initial begin
        repeat (4) @(posedge pix_clk);
        pix_rst_n <= 1'b1;
        sdr_rst_n <= 1'b1;
        frame_ready_sdr <= 1'b1;

        wait (captured_pixels == TEST_WIDTH * TEST_HEIGHT);
        repeat (5) @(posedge pix_clk);

        if (protocol_error) begin
            $display("FAIL: protocol_error asserted");
            $finish;
        end
        checks = checks + 1;

        if (underflow_sticky) begin
            $display("FAIL: unexpected line-buffer underflow during steady-state frame");
            $finish;
        end
        checks = checks + 1;

        $display("PASS: p1_sdram_hdmi_pipeline passed (checks=%0d, pixels=%0d, underflow=%b)",
                 checks, captured_pixels, underflow_sticky);
        $finish;
    end

    initial begin
        #3000000;
        $display("FAIL: timeout warm=%b pixels=%0d underflow=%b protocol=%b",
                 warm_ready, captured_pixels, underflow_sticky, protocol_error);
        $finish;
    end
endmodule
