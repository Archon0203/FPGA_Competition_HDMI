// ============================================================================
// Stable mailbox CDC for C-line display configuration.
// Source updates value then toggles update_toggle. Pixel side captures the
// stable mailbox after toggle synchronization and applies it only on a frame
// boundary, preventing half-frame configuration changes.
// ============================================================================
module m1c_frame_config_cdc #(
    parameter integer WIDTH = 8
)(
    input  wire             src_clk,
    input  wire             src_rst_n,
    input  wire [WIDTH-1:0] src_value,
    input  wire             src_update_toggle,

    input  wire             pix_clk,
    input  wire             pix_rst_n,
    input  wire             frame_boundary,
    output reg  [WIDTH-1:0] active_value,
    output reg              update_pulse
);
    reg toggle_sync1, toggle_sync2, toggle_seen;
    reg [WIDTH-1:0] data_sync1, data_sync2;
    reg [WIDTH-1:0] pending_value;
    reg pending_valid;

    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            toggle_sync1 <= 1'b0;
            toggle_sync2 <= 1'b0;
            toggle_seen  <= 1'b0;
            data_sync1   <= {WIDTH{1'b0}};
            data_sync2   <= {WIDTH{1'b0}};
            pending_value<= {WIDTH{1'b0}};
            pending_valid<= 1'b0;
            active_value <= {WIDTH{1'b0}};
            update_pulse <= 1'b0;
        end else begin
            toggle_sync1 <= src_update_toggle;
            toggle_sync2 <= toggle_sync1;
            data_sync1   <= src_value;
            data_sync2   <= data_sync1;
            update_pulse <= 1'b0;

            if (toggle_sync2 != toggle_seen) begin
                toggle_seen   <= toggle_sync2;
                pending_value <= data_sync2;
                pending_valid <= 1'b1;
            end

            if (frame_boundary && pending_valid) begin
                active_value  <= pending_value;
                pending_valid <= 1'b0;
                update_pulse  <= 1'b1;
            end
        end
    end

    wire _unused_src_rst_n = src_rst_n;
endmodule
