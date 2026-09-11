// ================================================================
// Module  : hdmi_test_pattern_line_provider
// Purpose : Synthesizable P1 HDMI bring-up source implementing the same
//           whole-line read contract consumed by hdmi_video_adapter.
//
// This block is deliberately independent from SDRAM.  It lets P1-03B prove
// the external-video APUG092 path (project adapter -> protected core -> EG
// PHY) before P1-04 joins the SDRAM/display domains in the final board top.
//
// Contract:
//   * read_start is accepted only while idle.
//   * first pixel is returned after the request (never combinationally).
//   * pixel_valid remains continuous for read_width beats.
//   * line_done is high together with the final valid pixel.
//   * the expected production width is ACTIVE_WIDTH; malformed requests set
//     protocol_error sticky but do not alter any vendor source.
//
// Pattern: 8 vertical RGB color bars (white/yellow/cyan/green/magenta/red/
//          blue/black), convenient for first HDMI monitor bring-up.
// ================================================================

module hdmi_test_pattern_line_provider #(
    parameter integer ACTIVE_WIDTH  = 640,
    parameter integer ACTIVE_HEIGHT = 480
) (
    input  wire        clk_pix,
    input  wire        rst_n,

    input  wire        read_start,
    input  wire [15:0] read_line_index,
    input  wire [15:0] read_width,

    output reg         pixel_valid,
    output reg  [23:0] pixel_data,
    output reg         line_done,

    output reg         busy,
    output reg         protocol_error
);

    localparam [15:0] ACTIVE_WIDTH_16  = ACTIVE_WIDTH;
    localparam [15:0] ACTIVE_HEIGHT_16 = ACTIVE_HEIGHT;

    // Constant elaboration-time boundaries.  The current 720p baseline width
    // (1280) is exactly divisible by eight.  For other widths, the final bar
    // absorbs any remainder.
    localparam integer BAR_W = (ACTIVE_WIDTH >= 8) ? (ACTIVE_WIDTH / 8) : 1;

    reg [15:0] x_count;
    reg [15:0] width_latched;

    function [23:0] color_bar;
        input [15:0] x;
        begin
            if      (x < BAR_W*1) color_bar = 24'hFFFFFF; // white
            else if (x < BAR_W*2) color_bar = 24'hFFFF00; // yellow
            else if (x < BAR_W*3) color_bar = 24'h00FFFF; // cyan
            else if (x < BAR_W*4) color_bar = 24'h00FF00; // green
            else if (x < BAR_W*5) color_bar = 24'hFF00FF; // magenta
            else if (x < BAR_W*6) color_bar = 24'hFF0000; // red
            else if (x < BAR_W*7) color_bar = 24'h0000FF; // blue
            else                  color_bar = 24'h000000; // black
        end
    endfunction

    always @(posedge clk_pix or negedge rst_n) begin
        if (!rst_n) begin
            pixel_valid    <= 1'b0;
            pixel_data     <= 24'd0;
            line_done      <= 1'b0;
            busy           <= 1'b0;
            protocol_error <= 1'b0;
            x_count        <= 16'd0;
            width_latched  <= 16'd0;
        end else begin
            pixel_valid <= 1'b0;
            line_done   <= 1'b0;

            if (!busy) begin
                if (read_start) begin
                    // hdmi_video_adapter always requests ACTIVE_WIDTH.  Keep
                    // explicit diagnostics here because this module is also a
                    // useful standalone board bring-up source.
                    if ((read_width == 16'd0) ||
                        (read_width != ACTIVE_WIDTH_16) ||
                        (read_line_index >= ACTIVE_HEIGHT_16))
                        protocol_error <= 1'b1;

                    if (read_width != 16'd0) begin
                        busy          <= 1'b1;
                        x_count       <= 16'd0;
                        width_latched <= read_width;
                    end
                end
            end else begin
                pixel_valid <= 1'b1;
                pixel_data  <= color_bar(x_count);

                if (x_count == width_latched - 16'd1) begin
                    line_done <= 1'b1;
                    busy      <= 1'b0;
                    x_count   <= 16'd0;
                end else begin
                    x_count <= x_count + 16'd1;
                end
            end

            // Overlapping line requests violate the provider contract.
            if (busy && read_start)
                protocol_error <= 1'b1;
        end
    end

endmodule
