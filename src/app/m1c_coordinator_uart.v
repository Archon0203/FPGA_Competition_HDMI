// ============================================================================
// M1 C-line coordinator for the board-proven 115200-baud UART link.
//
// Transaction rule used by M2 real-media control:
//   PING -> ACK(0x80) discovers catalog.
//   OPEN -> ACK(0x81/ACCEPTED) only means the Slave queued the request.
//   The coordinator then polls STATUS(0x09)->ACK(0x89) and does not expose
//   media_cmd_ready again until the requested image is actually DONE/visible.
//
// This completion gate is essential for real TF media, where one 640x480 BMP
// load takes far longer than a UART ACK.  Treating ACCEPTED as completion let
// the 2-second carousel and key presses outrun the Slave and overwrite queued
// selections.
// ============================================================================
module m1c_coordinator_uart #(
    parameter integer DISCOVERY_INTERVAL_CYCLES = 5_000_000,
    parameter integer ACK_TIMEOUT_CYCLES        = 2_500_000,
    parameter integer STATUS_POLL_INTERVAL_CYCLES = 1_000_000
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        media_cmd_valid,
    input  wire [7:0]  media_cmd_image_id,
    input  wire [1:0]  media_cmd_mode,
    output wire        media_cmd_ready,

    input  wire        frame_tx_busy,
    output reg         frame_tx_request,
    output reg  [7:0]  frame_tx_opcode,
    output reg  [2:0]  frame_tx_length,
    output reg  [31:0] frame_tx_payload,

    input  wire        rx_frame_valid,
    input  wire [7:0]  rx_frame_opcode,
    input  wire [2:0]  rx_frame_length,
    input  wire [31:0] rx_frame_payload,
    input  wire        rx_frame_error,
    input  wire        rx_framing_error,

    output reg         catalog_valid,
    output reg  [7:0]  catalog_count,
    output reg  [7:0]  remote_selected_image,
    output reg  [7:0]  remote_status,
    output reg  [7:0]  remote_error,
    output reg         link_ok,
    output reg         fault,
    output reg         ack_toggle,
    output reg         image_change_toggle
);
    localparam [7:0] OP_PING   = 8'h00;
    localparam [7:0] OP_OPEN   = 8'h01;
    localparam [7:0] OP_STATUS = 8'h09;
    localparam [7:0] ACK_PING  = 8'h80;
    localparam [7:0] ACK_OPEN  = 8'h81;
    localparam [7:0] ACK_STATUS= 8'h89;

    localparam [7:0] STATUS_READY    = 8'h01;
    localparam [7:0] STATUS_ACCEPTED = 8'h02;
    localparam [7:0] STATUS_DONE     = 8'h04;
    localparam [7:0] STATUS_ERROR    = 8'hE0;

    localparam [1:0] ST_IDLE      = 2'd0;
    localparam [1:0] ST_WAIT      = 2'd1;
    localparam [1:0] ST_POLL_GAP  = 2'd2;

    reg [1:0]  state;
    reg [31:0] discovery_count;
    reg [31:0] timeout_count;
    reg [31:0] poll_count;
    reg [7:0]  expected_ack;
    reg [7:0]  requested_image;
    reg        remote_visible;

    wire response_has_status = rx_frame_length >= 3'd1;
    wire response_has_image  = rx_frame_length >= 3'd2;
    wire response_has_count  = rx_frame_length >= 3'd3;
    wire response_has_error  = rx_frame_length >= 3'd4;
    wire [7:0] response_status = rx_frame_payload[7:0];
    wire [7:0] response_image  = rx_frame_payload[15:8];
    wire [7:0] response_count  = rx_frame_payload[23:16];
    wire [7:0] response_error  = rx_frame_payload[31:24];
    wire response_is_error = response_has_status && (response_status == STATUS_ERROR);
    wire response_completes_open = response_has_status && response_has_image &&
                                   (response_image == requested_image) &&
                                   (response_status == STATUS_DONE);
    wire matching_response = rx_frame_valid && (rx_frame_opcode == expected_ack) &&
                             (rx_frame_length == 3'd4);

    // OPEN remains back-pressured for the whole real-media transaction, not
    // merely until the Slave returns ACCEPTED.
    assign media_cmd_ready = (state == ST_IDLE) && catalog_valid && !frame_tx_busy;

    task issue_status_poll;
        begin
            frame_tx_opcode  <= OP_STATUS;
            frame_tx_length  <= 3'd0;
            frame_tx_payload <= 32'd0;
            frame_tx_request <= 1'b1;
            expected_ack     <= ACK_STATUS;
            timeout_count    <= 32'd0;
            state            <= ST_WAIT;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                 <= ST_IDLE;
            discovery_count       <= 32'd0;
            timeout_count         <= 32'd0;
            poll_count            <= 32'd0;
            expected_ack          <= ACK_PING;
            requested_image       <= 8'd0;
            remote_visible        <= 1'b0;
            frame_tx_request      <= 1'b0;
            frame_tx_opcode       <= OP_PING;
            frame_tx_length       <= 3'd0;
            frame_tx_payload      <= 32'd0;
            catalog_valid         <= 1'b0;
            catalog_count         <= 8'd0;
            remote_selected_image <= 8'd0;
            remote_status         <= 8'd0;
            remote_error          <= 8'd0;
            link_ok               <= 1'b0;
            fault                 <= 1'b0;
            ack_toggle            <= 1'b0;
            image_change_toggle   <= 1'b0;
        end else begin
            frame_tx_request <= 1'b0;

            if (rx_frame_error || rx_framing_error)
                fault <= 1'b1;

            // Consume only the response belonging to the outstanding frame.
            if (state == ST_WAIT && rx_frame_valid) begin
                if (matching_response) begin
                    remote_visible <= (response_status == STATUS_DONE);
                    if (response_has_status)
                        remote_status <= response_status;
                    if (response_has_error)
                        remote_error <= response_error;
                    else
                        remote_error <= 8'd0;
                    if (response_has_count) begin
                        catalog_count <= response_count;
                        catalog_valid <= (response_count != 0);
                    end
                    if (response_has_image) begin
                        if (response_image != remote_selected_image)
                            image_change_toggle <= ~image_change_toggle;
                        remote_selected_image <= response_image;
                    end

                    ack_toggle   <= ~ack_toggle;
                    timeout_count<= 32'd0;
                    link_ok      <= !response_is_error;
                    fault        <= response_is_error;

                    if (expected_ack == ACK_PING) begin
                        // Discovery has no long-running transaction.
                        state <= ST_IDLE;
                        discovery_count <= 32'd0;
                    end else if (expected_ack == ACK_OPEN) begin
                        if (response_is_error) begin
                            state <= ST_IDLE;
                        end else if (response_completes_open) begin
                            state <= ST_IDLE;
                            poll_count <= 32'd0;
                        end else begin
                            // ACCEPTED means queued/busy, not complete.
                            state <= ST_POLL_GAP;
                            poll_count <= 32'd0;
                        end
                    end else begin // ACK_STATUS
                        if (response_is_error) begin
                            state <= ST_IDLE;
                        end else if (response_completes_open) begin
                            state <= ST_IDLE;
                            poll_count <= 32'd0;
                        end else begin
                            state <= ST_POLL_GAP;
                            poll_count <= 32'd0;
                        end
                    end
                end else begin
                    // Stale/unexpected response: keep waiting for the expected
                    // opcode until the normal frame timeout expires.
                    fault <= 1'b1;
                end
            end

            case (state)
                ST_IDLE: begin
                    timeout_count <= 32'd0;
                    poll_count    <= 32'd0;

                    if (!catalog_valid) begin
                        if (discovery_count >= DISCOVERY_INTERVAL_CYCLES-1) begin
                            discovery_count <= 32'd0;
                            if (!frame_tx_busy) begin
                                frame_tx_opcode  <= OP_PING;
                                frame_tx_length  <= 3'd0;
                                frame_tx_payload <= 32'd0;
                                frame_tx_request <= 1'b1;
                                expected_ack     <= ACK_PING;
                                state            <= ST_WAIT;
                            end
                        end else begin
                            discovery_count <= discovery_count + 1'b1;
                        end
                    end else if (media_cmd_valid && media_cmd_ready) begin
                        // Consume the bootstrap OPEN without reloading a frame
                        // that discovery already confirmed as visible.
                        if (!(remote_visible && media_cmd_image_id == remote_selected_image)) begin
                        requested_image  <= media_cmd_image_id;
                        remote_visible   <= 1'b0;
                        frame_tx_opcode  <= OP_OPEN;
                        frame_tx_length  <= 3'd1;
                        frame_tx_payload <= {24'd0, media_cmd_image_id};
                        frame_tx_request <= 1'b1;
                        expected_ack     <= ACK_OPEN;
                        state            <= ST_WAIT;
                        discovery_count  <= 32'd0;
                        end
                    end
                end

                ST_WAIT: begin
                    if (matching_response) begin
                        // A valid response on the deadline wins over timeout.
                        timeout_count <= 32'd0;
                    end else if (timeout_count >= ACK_TIMEOUT_CYCLES-1) begin
                        timeout_count <= 32'd0;
                        // A lost ACCEPTED/STATUS reply is not media completion.
                        // Keep the OPEN serialized and reconcile via STATUS.
                        state         <= (expected_ack == ACK_PING) ? ST_IDLE : ST_POLL_GAP;
                        poll_count    <= 32'd0;
                        link_ok       <= 1'b0;
                        fault         <= 1'b1;
                        if (!catalog_valid)
                            discovery_count <= DISCOVERY_INTERVAL_CYCLES-1;
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end

                ST_POLL_GAP: begin
                    timeout_count <= 32'd0;
                    if (poll_count >= STATUS_POLL_INTERVAL_CYCLES-1) begin
                        poll_count <= 32'd0;
                        if (!frame_tx_busy)
                            issue_status_poll();
                    end else begin
                        poll_count <= poll_count + 1'b1;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    wire _unused_mode = ^media_cmd_mode ^ ^requested_image ^ ^STATUS_ACCEPTED;
endmodule
