// ============================================================================
// M1 C-line diagnostic compositor.
// Keeps the P1-04C official axis_user/valid/last cadence untouched and only
// substitutes RGB data. Four deterministic local patterns let the master
// visibly control the slave HDMI output before the M2 media data plane exists.
// ============================================================================
module m1c_axis_pattern_mux #(
    parameter integer HACTIVE = 640,
    parameter integer VACTIVE = 480
)(
    input  wire        clk_pix,
    input  wire        rst,
    input  wire        axis_user,
    input  wire        axis_valid,
    input  wire        axis_last,
    input  wire [23:0] base_data,
    input  wire [1:0]  pattern_id,
    input  wire        link_ok,
    input  wire        fault,
    output reg  [23:0] axis_data
);
    reg [11:0] x_count;
    reg [11:0] y_count;
    wire [11:0] px = axis_user ? 12'd0 : x_count;
    wire [11:0] py = axis_user ? 12'd0 : y_count;

    reg [23:0] pattern_data;
    wire border = (px < 8) || (px >= HACTIVE-8) ||
                  (py < 8) || (py >= VACTIVE-8);
    wire cross = (px >= HACTIVE/2-8 && px < HACTIVE/2+8) ||
                 (py >= VACTIVE/2-8 && py < VACTIVE/2+8);
    wire checker = px[5] ^ py[5];

    always @(*) begin
        case (pattern_id)
            2'd0: pattern_data = base_data;
            2'd1: begin
                if (border)
                    pattern_data = 24'hFFFFFF;
                else if (cross)
                    pattern_data = 24'h00FFFF;
                else if (px < HACTIVE/2 && py < VACTIVE/2)
                    pattern_data = 24'hFF0000;
                else if (px >= HACTIVE/2 && py < VACTIVE/2)
                    pattern_data = 24'h00FF00;
                else if (px < HACTIVE/2)
                    pattern_data = 24'h0000FF;
                else
                    pattern_data = 24'hFFFF00;
            end
            2'd2: pattern_data = checker ? 24'hE0E0E0 : 24'h202060;
            default: pattern_data = {px[7:0], py[7:0], (px[7:0] ^ py[7:0])};
        endcase

        // Small status strips do not alter AXI cadence. Red has priority.
        if (fault && py < 12'd24)
            axis_data = 24'hFF0000;
        else if (link_ok && px < 12'd32 && py < 12'd32)
            axis_data = 24'h00FF00;
        else
            axis_data = pattern_data;
    end

    always @(posedge clk_pix or posedge rst) begin
        if (rst) begin
            x_count <= 12'd0;
            y_count <= 12'd0;
        end else if (axis_valid) begin
            if (axis_user) begin
                x_count <= axis_last ? 12'd0 : 12'd1;
                y_count <= 12'd0;
            end else if (axis_last) begin
                x_count <= 12'd0;
                if (y_count == VACTIVE-1)
                    y_count <= 12'd0;
                else
                    y_count <= y_count + 1'b1;
            end else begin
                x_count <= x_count + 1'b1;
            end
        end
    end
endmodule
