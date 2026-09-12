// ================================================================
// Module  : p1_framebuffer_pattern_writer
// Purpose : P1-05A deterministic RGB888 framebuffer initializer.
//           Writes one complete 0x00RRGGBB test frame through the frozen
//           abstract write interface.  The generated image is intentionally
//           distinctive so a board test can prove data came from SDRAM rather
//           than from the P1-04C HDMI color-bar fallback.
//
// Pattern : white border; four color quadrants; magenta vertical center bar;
//           cyan horizontal center bar.
//
// Clock   : SDRAM/request domain (150 MHz in the P1-05A board build).
// Contract: mem_wr_valid/address/data remain stable until mem_wr_ready.
// ================================================================

module p1_framebuffer_pattern_writer #(
    parameter integer FRAME_WIDTH        = 640,
    parameter integer FRAME_HEIGHT       = 480,
    parameter integer FRAME_STRIDE_WORDS = 640,
    parameter [20:0]  FRAME_BASE         = 21'd0,
    parameter integer BORDER_PIXELS      = 8,
    parameter integer CENTER_BAR_PIXELS  = 16
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,

    output wire        mem_wr_valid,
    output wire [20:0] mem_wr_addr,
    output wire [31:0] mem_wr_data,
    input  wire        mem_wr_ready,

    output reg         busy,
    output reg         done,
    output reg         ok,
    output reg         protocol_error,
    output reg  [15:0] x_debug,
    output reg  [15:0] y_debug
);

    localparam integer FRAME_PIXELS = FRAME_WIDTH * FRAME_HEIGHT;
    localparam integer LAST_X       = FRAME_WIDTH  - 1;
    localparam integer LAST_Y       = FRAME_HEIGHT - 1;
    localparam integer HALF_X       = FRAME_WIDTH  / 2;
    localparam integer HALF_Y       = FRAME_HEIGHT / 2;
    localparam integer VCENTER_LO   = HALF_X - (CENTER_BAR_PIXELS / 2);
    localparam integer VCENTER_HI   = VCENTER_LO + CENTER_BAR_PIXELS;
    localparam integer HCENTER_LO   = HALF_Y - (CENTER_BAR_PIXELS / 2);
    localparam integer HCENTER_HI   = HCENTER_LO + CENTER_BAR_PIXELS;
    localparam integer LAST_ADDR    = FRAME_BASE +
                                      (FRAME_HEIGHT - 1) * FRAME_STRIDE_WORDS +
                                      (FRAME_WIDTH - 1);

    reg [20:0] current_addr;

    wire config_valid = (FRAME_WIDTH > 0) &&
                        (FRAME_HEIGHT > 0) &&
                        (FRAME_STRIDE_WORDS >= FRAME_WIDTH) &&
                        (FRAME_BASE[1:0] == 2'b00) &&
                        (FRAME_PIXELS > 0) &&
                        (LAST_ADDR < 2097152) &&
                        (BORDER_PIXELS >= 0) &&
                        (CENTER_BAR_PIXELS > 0);

    function [23:0] pattern_rgb;
        input [15:0] x;
        input [15:0] y;
        begin
            if ((x < BORDER_PIXELS) ||
                (x >= FRAME_WIDTH - BORDER_PIXELS) ||
                (y < BORDER_PIXELS) ||
                (y >= FRAME_HEIGHT - BORDER_PIXELS)) begin
                pattern_rgb = 24'hFFFFFF; // white border
            end
            else if ((x >= VCENTER_LO) && (x < VCENTER_HI)) begin
                pattern_rgb = 24'hFF00FF; // magenta vertical bar
            end
            else if ((y >= HCENTER_LO) && (y < HCENTER_HI)) begin
                pattern_rgb = 24'h00FFFF; // cyan horizontal bar
            end
            else if ((x < HALF_X) && (y < HALF_Y)) begin
                pattern_rgb = 24'hFF0000; // top-left red
            end
            else if ((x >= HALF_X) && (y < HALF_Y)) begin
                pattern_rgb = 24'h00FF00; // top-right green
            end
            else if ((x < HALF_X) && (y >= HALF_Y)) begin
                pattern_rgb = 24'h0000FF; // bottom-left blue
            end
            else begin
                pattern_rgb = 24'hFFFF00; // bottom-right yellow
            end
        end
    endfunction

    assign mem_wr_valid = busy;
    assign mem_wr_addr  = current_addr;
    assign mem_wr_data  = {8'h00, pattern_rgb(x_debug, y_debug)};

    wire wr_accept = mem_wr_valid && mem_wr_ready;
    wire last_pixel = (x_debug == LAST_X) && (y_debug == LAST_Y);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_addr   <= FRAME_BASE;
            busy           <= 1'b0;
            done           <= 1'b0;
            ok             <= 1'b0;
            protocol_error <= 1'b0;
            x_debug        <= 16'd0;
            y_debug        <= 16'd0;
        end else begin
            done <= 1'b0;

            if (start && busy)
                protocol_error <= 1'b1;

            if (start && !busy) begin
                current_addr <= FRAME_BASE;
                x_debug      <= 16'd0;
                y_debug      <= 16'd0;
                ok           <= 1'b0;

                if (config_valid) begin
                    busy <= 1'b1;
                end else begin
                    busy           <= 1'b0;
                    done           <= 1'b1;
                    ok             <= 1'b0;
                    protocol_error <= 1'b1;
                end
            end else if (busy && wr_accept) begin
                if (last_pixel) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    ok   <= !protocol_error;
                end else if (x_debug == LAST_X) begin
                    x_debug      <= 16'd0;
                    y_debug      <= y_debug + 16'd1;
                    current_addr <= current_addr +
                                    (FRAME_STRIDE_WORDS - FRAME_WIDTH) + 21'd1;
                end else begin
                    x_debug      <= x_debug + 16'd1;
                    current_addr <= current_addr + 21'd1;
                end
            end
        end
    end

endmodule
