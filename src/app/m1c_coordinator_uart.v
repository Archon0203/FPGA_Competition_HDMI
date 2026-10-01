// ============================================================================
// M1 C-line coordinator for the already board-proven 115200-baud UART link.
//
// It deliberately separates C's high-level media_cmd channel from the wire:
//   - discovery: PING(0x00) -> ACK(0x80) obtains catalog_count
//   - selection: media_cmd OPEN -> OPEN(image_id) -> ACK(0x81)
//
// Response payload bytes are:
//   [0] status_code, [1] remote_selected_image, [2] catalog_count,
//   [3] error_code.
//
// M2 can replace this UART transport with SPI without changing the
// media_command_controller interface.
// ============================================================================
module m1c_coordinator_uart #(
    parameter integer DISCOVERY_INTERVAL_CYCLES = 5_000_000,
    parameter integer ACK_TIMEOUT_CYCLES        = 2_500_000
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
    localparam [7:0] OP_PING = 8'h00;
    localparam [7:0] OP_OPEN = 8'h01;

    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_WAIT = 2'd1;

    reg [1:0]  state;
    reg [31:0] discovery_count;
    reg [31:0] timeout_count;
    reg [7:0]  expected_ack;
    reg [7:0]  requested_image;

    wire response_has_status = rx_frame_length >= 3'd1;
    wire response_has_image  = rx_frame_length >= 3'd2;
    wire response_has_count  = rx_frame_length >= 3'd3;
    wire response_has_error  = rx_frame_length >= 3'd4;
    wire response_is_error   = response_has_status && (rx_frame_payload[7:0] == 8'hE0);

    assign media_cmd_ready = (state == ST_IDLE) && catalog_valid && !frame_tx_busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                 <= ST_IDLE;
            discovery_count       <= 32'd0;
            timeout_count         <= 32'd0;
            expected_ack          <= 8'h80;
            requested_image       <= 8'd0;
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

            if (state == ST_WAIT && rx_frame_valid) begin
                if (rx_frame_opcode == expected_ack) begin
                    if (response_has_status)
                        remote_status <= rx_frame_payload[7:0];
                    if (response_has_error)
                        remote_error <= rx_frame_payload[31:24];
                    else
                        remote_error <= 8'd0;
                    if (response_has_count && rx_frame_payload[23:16] != 0) begin
                        catalog_count <= rx_frame_payload[23:16];
                        catalog_valid <= 1'b1;
                    end
                    if (response_has_image) begin
                        if (rx_frame_payload[15:8] != remote_selected_image)
                            image_change_toggle <= ~image_change_toggle;
                        remote_selected_image <= rx_frame_payload[15:8];
                    end

                    ack_toggle <= ~ack_toggle;
                    if (!response_is_error) begin
                        link_ok <= 1'b1;
                        fault   <= 1'b0;
                    end else begin
                        fault <= 1'b1;
                    end
                    state <= ST_IDLE;
                    timeout_count <= 32'd0;
                    discovery_count <= 32'd0;
                end else begin
                    // A syntactically valid but unexpected frame is a protocol
                    // error. Keep waiting for the expected response until the
                    // normal timeout expires so a stale frame cannot satisfy it.
                    fault <= 1'b1;
                end
            end

            case (state)
                ST_IDLE: begin
                    timeout_count <= 32'd0;

                    if (!catalog_valid) begin
                        if (discovery_count >= DISCOVERY_INTERVAL_CYCLES-1) begin
                            discovery_count <= 32'd0;
                            if (!frame_tx_busy) begin
                                frame_tx_opcode  <= OP_PING;
                                frame_tx_length  <= 3'd0;
                                frame_tx_payload <= 32'd0;
                                frame_tx_request <= 1'b1;
                                expected_ack     <= 8'h80;
                                state            <= ST_WAIT;
                            end
                        end else begin
                            discovery_count <= discovery_count + 1'b1;
                        end
                    end else if (media_cmd_valid && media_cmd_ready) begin
                        // M1 media_command_controller currently emits OPEN.
                        // Keep mode reserved so M2 can add PLAY/PAUSE without
                        // changing this high-level handshake.
                        requested_image  <= media_cmd_image_id;
                        frame_tx_opcode  <= OP_OPEN;
                        frame_tx_length  <= 3'd1;
                        frame_tx_payload <= {24'd0, media_cmd_image_id};
                        frame_tx_request <= 1'b1;
                        expected_ack     <= 8'h81;
                        state            <= ST_WAIT;
                        discovery_count  <= 32'd0;
                    end
                end

                ST_WAIT: begin
                    if (timeout_count >= ACK_TIMEOUT_CYCLES-1) begin
                        timeout_count <= 32'd0;
                        state         <= ST_IDLE;
                        link_ok       <= 1'b0;
                        fault         <= 1'b1;
                        if (!catalog_valid)
                            discovery_count <= DISCOVERY_INTERVAL_CYCLES-1;
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    // Keep currently-unused interface fields deliberately referenced so the
    // contract remains explicit in lint/synthesis reports.
    wire _unused_mode = ^media_cmd_mode ^ ^requested_image;
endmodule
