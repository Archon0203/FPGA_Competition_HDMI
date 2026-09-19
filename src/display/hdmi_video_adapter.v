// ================================================================
// Module  : hdmi_video_adapter
// Purpose : P1-03A bridge from the frozen P0 line-buffer read contract
//           to the APUG092 HDMI1.4b Transmitter Video Interface.
//
// APUG092 contract used here (official APUG092 v1.0):
//   * I_axis_s_user : one-cycle SOF pulse on first active pixel of frame.
//   * I_axis_s_valid: active video data valid.
//   * I_axis_s_last : asserted on final pixel of each active line.
//   * O_axis_s_ready: may deassert after EOL; a line itself must be
//                     supplied continuously once started.
//
// P0 line_buffer_pingpong contract used here:
//   * read_start requests one full line.
//   * first pixel appears no earlier than the following cycle.
//   * pixel_valid is continuous for read_width cycles.
//   * missing line is replaced by a continuous black line.
//
// This block deliberately does NOT generate HDMI blanking/sync timing; the
// APUG092 core owns that timing and phase matching. It only packetizes the
// display-order active RGB stream into APUG092's line/frame video interface.
//
// RGB byte order is preserved: axis_data = {R[7:0],G[7:0],B[7:0]}.
// ================================================================

module hdmi_video_adapter #(
    parameter integer ACTIVE_WIDTH  = 640,
    parameter integer ACTIVE_HEIGHT = 480
) (
    input  wire        clk_pix,
    input  wire        rst_n,
    input  wire        enable,

    // -------- line_buffer_pingpong read side --------
    output reg         lb_read_start,
    output reg  [15:0] lb_read_line_index,
    output wire [15:0] lb_read_width,
    input  wire        lb_pixel_valid,
    input  wire [23:0] lb_pixel_data,
    input  wire        lb_line_done,

    // -------- APUG092 Video Interface --------
    output wire        axis_user,
    output wire        axis_valid,
    output wire        axis_last,
    output wire [23:0] axis_data,
    input  wire        axis_ready,

    // -------- status/debug --------
    output reg         frame_done_pulse,
    output reg         protocol_error,
    output reg  [15:0] current_line,
    output reg  [15:0] current_pixel
);

    localparam ST_IDLE      = 2'd0;
    localparam ST_WAIT_DATA = 2'd1;
    localparam ST_STREAM    = 2'd2;

    reg [1:0] state;
    reg       frame_first_line;

    localparam [15:0] ACTIVE_WIDTH_16 = ACTIVE_WIDTH;

    wire width_valid  = (ACTIVE_WIDTH  > 0) && (ACTIVE_WIDTH  <= 65535);
    wire height_valid = (ACTIVE_HEIGHT > 0) && (ACTIVE_HEIGHT <= 65535);

    assign lb_read_width = ACTIVE_WIDTH_16;

    // Once a line starts, the frozen line-buffer contract guarantees a beat
    // every pixel clock. Do not gate valid/data by axis_ready: APUG092 itself
    // specifies that ready only drops at a line boundary.
    assign axis_valid = ((state == ST_WAIT_DATA) || (state == ST_STREAM)) && lb_pixel_valid;
    assign axis_data  = lb_pixel_data;
    assign axis_user  = axis_valid && frame_first_line && (current_pixel == 16'd0);
    assign axis_last  = axis_valid && (current_pixel == ACTIVE_WIDTH-1);

    always @(posedge clk_pix or negedge rst_n) begin
        if (!rst_n) begin
            state              <= ST_IDLE;
            lb_read_start      <= 1'b0;
            lb_read_line_index <= 16'd0;
            frame_done_pulse   <= 1'b0;
            protocol_error     <= 1'b0;
            current_line       <= 16'd0;
            current_pixel      <= 16'd0;
            frame_first_line   <= 1'b1;
        end else begin
            lb_read_start    <= 1'b0;
            frame_done_pulse <= 1'b0;

            // Static parameter sanity becomes a sticky runtime diagnostic.
            if (!width_valid || !height_valid)
                protocol_error <= 1'b1;

            case (state)
                ST_IDLE: begin
                    current_pixel <= 16'd0;
                    if (enable && axis_ready && width_valid && height_valid) begin
                        lb_read_start      <= 1'b1;
                        lb_read_line_index <= current_line;
                        state              <= ST_WAIT_DATA;
                    end
                end

                ST_WAIT_DATA: begin
                    // The first returned pixel is already an APUG092 transfer
                    // beat in this state (axis_valid is asserted combinationally).
                    if (lb_pixel_valid) begin
                        if (lb_line_done != (ACTIVE_WIDTH == 1))
                            protocol_error <= 1'b1;

                        if (ACTIVE_WIDTH == 1) begin
                            current_pixel <= 16'd0;
                            if (current_line == ACTIVE_HEIGHT-1) begin
                                current_line     <= 16'd0;
                                frame_first_line <= 1'b1;
                                frame_done_pulse <= 1'b1;
                            end else begin
                                current_line     <= current_line + 16'd1;
                                frame_first_line <= 1'b0;
                            end
                            state <= ST_IDLE;
                        end else begin
                            current_pixel <= 16'd1;
                            state         <= ST_STREAM;
                        end
                    end
                end

                ST_STREAM: begin
                    // APUG092 documents ready as line-boundary backpressure.
                    // A mid-line drop is a provider/protocol violation; the
                    // source remains continuous rather than stalling P0.
                    if (!axis_ready)
                        protocol_error <= 1'b1;

                    if (!lb_pixel_valid) begin
                        // P0 promised an uninterrupted active line.
                        protocol_error <= 1'b1;
                    end else begin
                        // line_done must coincide exactly with the configured
                        // final pixel. axis_last is generated from our counter,
                        // so a malformed line cannot move the APUG092 EOL marker.
                        if (lb_line_done != (current_pixel == ACTIVE_WIDTH-1))
                            protocol_error <= 1'b1;

                        if (current_pixel == ACTIVE_WIDTH-1) begin
                            current_pixel <= 16'd0;
                            if (current_line == ACTIVE_HEIGHT-1) begin
                                current_line     <= 16'd0;
                                frame_first_line <= 1'b1;
                                frame_done_pulse <= 1'b1;
                            end else begin
                                current_line     <= current_line + 16'd1;
                                frame_first_line <= 1'b0;
                            end
                            state <= ST_IDLE;
                        end else begin
                            current_pixel <= current_pixel + 16'd1;
                        end
                    end
                end

                default: begin
                    protocol_error <= 1'b1;
                    current_line   <= 16'd0;
                    current_pixel  <= 16'd0;
                    frame_first_line <= 1'b1;
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
