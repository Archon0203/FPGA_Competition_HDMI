// ================================================================
// Module  : hdmi_framebuffer_scanout
// Purpose : P1-05A free-running 640x480 line-buffer scanout scheduler.
//
// This block deliberately does NOT replace the P1-04C APUG092 timing source.
// The proven hdmi_official_baseline_source continues to supply user/valid/last
// to APUG092.  This block only schedules line_buffer_pingpong reads and returns
// framebuffer RGB data aligned to the same active-video cadence.
//
// With line_buffer_pingpong, read_start accepted at HBLANK-2 causes pixel 0 to
// become valid exactly when the local raster advances to HBLANK.
// ================================================================

module hdmi_framebuffer_scanout #(
    parameter integer HACTIVE = 640,
    parameter integer HFP     = 16,
    parameter integer HSA     = 96,
    parameter integer HBP     = 48,
    parameter integer VACTIVE = 480,
    parameter integer VFP     = 10,
    parameter integer VSA     = 2,
    parameter integer VBP     = 33
) (
    input  wire        clk_pix,
    input  wire        rst_n,
    input  wire        enable,

    output wire        lb_read_start,
    output wire [15:0] lb_read_line_index,
    output wire [15:0] lb_read_width,
    input  wire        lb_pixel_valid,
    input  wire [23:0] lb_pixel_data,
    input  wire        lb_line_done,

    output wire        pixel_valid,
    output wire [23:0] pixel_data,
    output wire        frame_boundary,
    output wire        active_expected,
    output reg         timing_error,
    output reg  [15:0] h_count_debug,
    output reg  [15:0] v_count_debug
);

    localparam integer HTOTAL = HACTIVE + HFP + HSA + HBP;
    localparam integer VTOTAL = VACTIVE + VFP + VSA + VBP;
    localparam integer HBLANK = HTOTAL - HACTIVE;
    localparam integer VBLANK = VTOTAL - VACTIVE;

    wire geometry_valid = (HACTIVE > 0) && (VACTIVE > 0) &&
                          (HBLANK >= 2) && (HTOTAL <= 65535) &&
                          (VTOTAL <= 65535);

    assign frame_boundary = (h_count_debug == 16'd0) &&
                            (v_count_debug == 16'd0);

    assign active_expected = enable &&
                             (v_count_debug >= VBLANK) &&
                             (h_count_debug >= HBLANK);

    assign lb_read_start = enable && geometry_valid &&
                           (v_count_debug >= VBLANK) &&
                           (h_count_debug == HBLANK - 2);

    assign lb_read_line_index = (v_count_debug >= VBLANK)
                              ? (v_count_debug - VBLANK)
                              : 16'd0;
    assign lb_read_width = HACTIVE;

    assign pixel_valid = lb_pixel_valid;
    assign pixel_data  = lb_pixel_data;

    always @(posedge clk_pix or negedge rst_n) begin
        if (!rst_n) begin
            h_count_debug <= 16'd0;
            v_count_debug <= 16'd0;
            timing_error  <= 1'b0;
        end else begin
            if (!geometry_valid)
                timing_error <= 1'b1;

            if (enable && geometry_valid &&
                (active_expected != lb_pixel_valid))
                timing_error <= 1'b1;

            // line_done must accompany the final active pixel of a line.
            if (enable && lb_line_done &&
                !((v_count_debug >= VBLANK) &&
                  (h_count_debug == HTOTAL - 1)))
                timing_error <= 1'b1;

            if (h_count_debug == HTOTAL - 1) begin
                h_count_debug <= 16'd0;
                if (v_count_debug == VTOTAL - 1)
                    v_count_debug <= 16'd0;
                else
                    v_count_debug <= v_count_debug + 16'd1;
            end else begin
                h_count_debug <= h_count_debug + 16'd1;
            end
        end
    end

endmodule
