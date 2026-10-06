`include "m1a_protocol.vh"

// M2 real-media control bridge for the proven M1 framed UART control plane.
//
// This bridge deliberately carries control/status only. Raw pixels remain on
// the M2 media/data path. It makes the existing Master coordinator consume the
// real Slave catalog and queue OPEN requests without depending on the mock
// media service used by M1.
module m2_real_media_uart_bridge (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        rx_frame_valid,
    input  wire [7:0]  rx_frame_opcode,
    input  wire [2:0]  rx_frame_length,
    input  wire [31:0] rx_frame_payload,
    input  wire        rx_frame_error,
    input  wire        rx_framing_error,

    input  wire        frame_tx_busy,
    output reg         frame_tx_request,
    output reg  [7:0]  frame_tx_opcode,
    output reg  [2:0]  frame_tx_length,
    output reg  [31:0] frame_tx_payload,

    input  wire        catalog_valid,
    input  wire [7:0]  catalog_count,
    input  wire        source_busy,
    input  wire        source_done,
    // Persistent indication that the most recently requested image has
    // completed successfully.  source_done is only a pulse; source_valid
    // keeps STATUS=DONE visible to the Master until the next OPEN begins.
    input  wire        source_valid,
    input  wire        source_error,
    input  wire [7:0]  source_error_code,
    input  wire [7:0]  selected_image_id,

    output reg         open_request,
    output reg  [7:0]  open_image_id,
    output reg         open_prefetch,
    output reg         link_seen,
    output reg         fault,
    output reg         command_toggle,
    output reg         reply_toggle
);
    localparam [7:0] OP_PING = 8'h00;
    localparam [1:0] ST_IDLE = 2'd0, ST_RESPOND = 2'd1;

    reg [1:0] state;
    reg [7:0] pending_opcode;
    reg [7:0] pending_status;
    reg [7:0] pending_error;
    reg open_pending;
    reg open_started;

    wire [7:0] live_status = source_error ? `M1A_STATUS_ERROR :
                              (source_busy || open_pending) ? `M1A_STATUS_ACCEPTED :
                              (source_done || source_valid) ? `M1A_STATUS_DONE :
                                             `M1A_STATUS_READY;
    wire [7:0] live_error = source_error ? source_error_code : 8'h00;

    task queue_response;
        input [7:0] op;
        input [7:0] status;
        input [7:0] err;
        begin
            pending_opcode <= op;
            pending_status <= status;
            pending_error  <= err;
            state          <= ST_RESPOND;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= ST_IDLE;
            pending_opcode   <= 8'h80;
            pending_status   <= `M1A_STATUS_READY;
            pending_error    <= 8'h00;
            frame_tx_request <= 1'b0;
            frame_tx_opcode  <= 8'h80;
            frame_tx_length  <= 3'd4;
            frame_tx_payload <= 32'd0;
            open_request     <= 1'b0;
            open_image_id    <= 8'd0;
            open_prefetch    <= 1'b0;
            link_seen        <= 1'b0;
            fault            <= 1'b0;
            command_toggle   <= 1'b0;
            reply_toggle     <= 1'b0;
            open_pending     <= 1'b0;
            open_started     <= 1'b0;
        end else begin
            frame_tx_request <= 1'b0;
            open_request     <= 1'b0;
            if (open_pending && source_busy)
                open_started <= 1'b1;
            if (source_error || (open_pending && open_started &&
                source_valid && !source_busy && selected_image_id == open_image_id)) begin
                open_pending <= 1'b0;
                open_started <= 1'b0;
            end

            if (rx_frame_error || rx_framing_error)
                fault <= 1'b1;
            if (source_error)
                fault <= 1'b1;
            else if (source_done)
                fault <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (rx_frame_valid) begin
                        link_seen      <= 1'b1;
                        command_toggle <= ~command_toggle;

                        if (rx_frame_opcode == OP_PING && rx_frame_length == 3'd0) begin
                            queue_response(8'h80, live_status, live_error);
                        end else if (rx_frame_opcode == `M1A_CMD_OPEN &&
                                     (rx_frame_length == 3'd1 || rx_frame_length == 3'd2)) begin
                            if (!catalog_valid) begin
                                fault <= 1'b1;
                                queue_response(8'h81, `M1A_STATUS_ERROR,
                                               `M1A_ERR_NOT_READY);
                            end else if (rx_frame_payload[7:0] >= catalog_count) begin
                                fault <= 1'b1;
                                queue_response(8'h81, `M1A_STATUS_ERROR,
                                               `M1A_ERR_BAD_IMAGE);
                            end else begin
                                // OPEN is acknowledged when queued, not when a
                                // ~1 MB BMP has finished loading. The Master
                                // coordinator therefore never times out while
                                // the Slave is legitimately busy with TF I/O.
                                open_image_id <= rx_frame_payload[7:0];
                                open_prefetch <= (rx_frame_length == 3'd2) &&
                                                 (rx_frame_payload[15:14] == 2'd1);
                                open_request  <= 1'b1;
                                open_pending  <= 1'b1;
                                open_started  <= 1'b0;
                                fault         <= 1'b0;
                                queue_response(8'h81, `M1A_STATUS_ACCEPTED, 8'h00);
                            end
                        end else if (rx_frame_opcode == `M1A_CMD_STATUS &&
                                     rx_frame_length == 3'd0) begin
                            queue_response(8'h89, live_status, live_error);
                        end else begin
                            fault <= 1'b1;
                            queue_response(rx_frame_opcode | 8'h80,
                                           `M1A_STATUS_ERROR,
                                           `M1A_ERR_BAD_FRAME);
                        end
                    end
                end

                ST_RESPOND: begin
                    if (!frame_tx_busy) begin
                        frame_tx_opcode  <= pending_opcode;
                        frame_tx_length  <= 3'd4;
                        frame_tx_payload <= {pending_error, catalog_count,
                                             selected_image_id, pending_status};
                        frame_tx_request <= 1'b1;
                        reply_toggle     <= ~reply_toggle;
                        state            <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
