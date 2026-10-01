// ============================================================================
// Vendor-PHY-independent canonical 1920x1080p60 raster contract.
//
// This module does not generate the 148.5 MHz clock; M4 must close the real
// PLL/APUG092/PHY profile separately. M1 uses this RTL to freeze coordinates,
// sideband semantics and the exact 2200x1125 timing geometry.
// ============================================================================
module hdmi_1080p_raster #(
    parameter integer HACTIVE = 1920,
    parameter integer HFP     = 88,
    parameter integer HSA     = 44,
    parameter integer HBP     = 148,
    parameter integer VACTIVE = 1080,
    parameter integer VFP     = 4,
    parameter integer VSA     = 5,
    parameter integer VBP     = 36
)(
    input  wire        pix_clk,
    input  wire        rst_n,
    output wire        active,
    output wire [11:0] x,
    output wire [11:0] y,
    output wire        frame_start,
    output wire        line_start,
    output wire        line_last,
    output wire        frame_boundary,
    output wire        hsync,
    output wire        vsync
);
    localparam integer HTOTAL = HACTIVE + HFP + HSA + HBP;
    localparam integer VTOTAL = VACTIVE + VFP + VSA + VBP;

    reg [11:0] h_count;
    reg [11:0] v_count;

    assign active = (h_count < HACTIVE) && (v_count < VACTIVE);
    assign x = h_count;
    assign y = v_count;
    assign line_start = active && (h_count == 0);
    assign line_last  = active && (h_count == HACTIVE-1);
    assign frame_start = active && (h_count == 0) && (v_count == 0);
    assign frame_boundary = frame_start;
    // CEA-861 1080p60 uses positive H/V sync polarity.  The APUG092 AXI
    // integration does not consume these wires directly, but keeping the
    // canonical raster polarity correct prevents a later wrapper mismatch.
    assign hsync = ((h_count >= HACTIVE + HFP) &&
                    (h_count <  HACTIVE + HFP + HSA));
    assign vsync = ((v_count >= VACTIVE + VFP) &&
                    (v_count <  VACTIVE + VFP + VSA));

    always @(posedge pix_clk or negedge rst_n) begin
        if (!rst_n) begin
            h_count <= 12'd0;
            v_count <= 12'd0;
        end else if (h_count == HTOTAL-1) begin
            h_count <= 12'd0;
            if (v_count == VTOTAL-1)
                v_count <= 12'd0;
            else
                v_count <= v_count + 1'b1;
        end else begin
            h_count <= h_count + 1'b1;
        end
    end
endmodule
