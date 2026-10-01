`include "m1a_protocol.vh"

// ============================================================================
// M1 integration bridge: board-proven UART transport -> A-line media service.
//
// This module is intentionally transport-specific only at its outer frame
// ports. Internally it uses the same cmd_valid/opcode/arg contract as the SPI
// service shell, so M2 can swap UART for SPI without changing the A service.
// ============================================================================
module m1a_uart_service_bridge #(
    parameter integer CATALOG_COUNT = 4,
    parameter integer IMAGE_WIDTH   = 640,
    parameter integer IMAGE_HEIGHT  = 480
)(
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

    output reg  [7:0]  display_image_id,
    output reg         link_seen,
    output reg         fault,
    output reg         command_toggle,
    output reg         reply_toggle,
    output reg         display_update_toggle,

    output wire        catalog_valid,
    output wire [7:0]  catalog_count,
    output wire [15:0] catalog_epoch,
    output wire        source_ready,
    output wire        source_busy,
    output wire        source_done,
    output wire        source_error,
    output wire [15:0] credit_level,

    output wire        media_valid,
    input  wire        media_ready,
    output wire [31:0] media_data,
    output wire        media_line_start,
    output wire        media_line_end,
    output wire        media_frame_end,
    output wire [15:0] media_frame_id,
    output wire [7:0]  media_image_id,
    output wire [15:0] media_line_index
);
    localparam [7:0] OP_PING = 8'h00;

    localparam [2:0] ST_IDLE        = 3'd0;
    localparam [2:0] ST_ISSUE       = 3'd1;
    localparam [2:0] ST_WAIT_STATUS = 3'd2;
    localparam [2:0] ST_RESPOND     = 3'd3;

    reg [2:0] state;
    reg       svc_cmd_valid;
    wire      svc_cmd_ready;
    reg [7:0] svc_cmd_opcode;
    reg [31:0] svc_cmd_arg;

    wire descriptor_valid;
    wire [7:0] descriptor_image_id;
    wire [1:0] descriptor_type;
    wire [15:0] descriptor_width;
    wire [15:0] descriptor_height;
    wire [15:0] descriptor_frame_count;
    wire [31:0] descriptor_duration;
    wire status_valid;
    wire [7:0] status_code;
    wire [7:0] status_error;

    reg [7:0] pending_response_opcode;
    reg [7:0] response_status;
    reg [7:0] response_error;

    function command_length_ok;
        input [7:0] op;
        input [2:0] len;
        begin
            case (op)
                `M1A_CMD_OPEN:       command_length_ok = (len == 3'd1);
                `M1A_CMD_SET_FORMAT: command_length_ok = (len == 3'd1);
                `M1A_CMD_CREDIT:     command_length_ok = (len == 3'd2);
                `M1A_CMD_NEXT,
                `M1A_CMD_PREV,
                `M1A_CMD_PLAY,
                `M1A_CMD_PAUSE,
                `M1A_CMD_ABORT,
                `M1A_CMD_STATUS:     command_length_ok = (len == 3'd0);
                default:             command_length_ok = 1'b0;
            endcase
        end
    endfunction

    m1a_media_service_mock #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .MOCK_LINES(IMAGE_HEIGHT),
        .WORDS_PER_LINE(4),
        .CATALOG_COUNT(CATALOG_COUNT)
    ) u_media_service (
        .clk(clk), .rst_n(rst_n),
        .cmd_valid(svc_cmd_valid), .cmd_opcode(svc_cmd_opcode),
        .cmd_arg(svc_cmd_arg), .cmd_ready(svc_cmd_ready),
        .catalog_valid(catalog_valid), .catalog_count(catalog_count),
        .catalog_epoch(catalog_epoch),
        .descriptor_valid(descriptor_valid),
        .descriptor_image_id(descriptor_image_id),
        .descriptor_type(descriptor_type), .descriptor_width(descriptor_width),
        .descriptor_height(descriptor_height),
        .descriptor_frame_count(descriptor_frame_count),
        .descriptor_duration(descriptor_duration),
        .status_valid(status_valid), .status_code(status_code),
        .status_error(status_error), .source_ready(source_ready),
        .source_busy(source_busy), .source_done(source_done),
        .source_error(source_error), .credit_level(credit_level),
        .media_valid(media_valid), .media_ready(media_ready),
        .media_data(media_data), .media_line_start(media_line_start),
        .media_line_end(media_line_end), .media_frame_end(media_frame_end),
        .media_frame_id(media_frame_id), .media_image_id(media_image_id),
        .media_line_index(media_line_index)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                   <= ST_IDLE;
            svc_cmd_valid           <= 1'b0;
            svc_cmd_opcode          <= 8'd0;
            svc_cmd_arg             <= 32'd0;
            pending_response_opcode <= 8'h80;
            response_status         <= `M1A_STATUS_READY;
            response_error          <= 8'd0;
            frame_tx_request        <= 1'b0;
            frame_tx_opcode         <= 8'h80;
            frame_tx_length         <= 3'd4;
            frame_tx_payload        <= 32'd0;
            display_image_id        <= 8'd0;
            link_seen               <= 1'b0;
            fault                   <= 1'b0;
            command_toggle          <= 1'b0;
            reply_toggle            <= 1'b0;
            display_update_toggle   <= 1'b0;
        end else begin
            frame_tx_request <= 1'b0;

            if (rx_frame_error || rx_framing_error)
                fault <= 1'b1;

            if (descriptor_valid) begin
                display_image_id      <= descriptor_image_id;
                display_update_toggle <= ~display_update_toggle;
            end

            case (state)
                ST_IDLE: begin
                    svc_cmd_valid <= 1'b0;
                    if (rx_frame_valid) begin
                        link_seen      <= 1'b1;
                        command_toggle <= ~command_toggle;

                        if (rx_frame_opcode == OP_PING && rx_frame_length == 0) begin
                            pending_response_opcode <= 8'h80;
                            response_status <= `M1A_STATUS_READY;
                            response_error  <= 8'd0;
                            state <= ST_RESPOND;
                        end else if (command_length_ok(rx_frame_opcode, rx_frame_length)) begin
                            svc_cmd_opcode <= rx_frame_opcode;
                            case (rx_frame_opcode)
                                `M1A_CMD_OPEN:       svc_cmd_arg <= {24'd0, rx_frame_payload[7:0]};
                                `M1A_CMD_SET_FORMAT: svc_cmd_arg <= {28'd0, rx_frame_payload[3:0]};
                                `M1A_CMD_CREDIT:     svc_cmd_arg <= {16'd0, rx_frame_payload[15:0]};
                                default:             svc_cmd_arg <= 32'd0;
                            endcase
                            pending_response_opcode <= rx_frame_opcode | 8'h80;
                            svc_cmd_valid <= 1'b1;
                            state <= ST_ISSUE;
                        end else begin
                            pending_response_opcode <= rx_frame_opcode | 8'h80;
                            response_status <= `M1A_STATUS_ERROR;
                            response_error  <= `M1A_ERR_BAD_FRAME;
                            fault <= 1'b1;
                            state <= ST_RESPOND;
                        end
                    end
                end

                ST_ISSUE: begin
                    if (svc_cmd_valid && svc_cmd_ready) begin
                        svc_cmd_valid <= 1'b0;
                        state <= ST_WAIT_STATUS;
                    end
                end

                ST_WAIT_STATUS: begin
                    if (status_valid) begin
                        response_status <= status_code;
                        response_error  <= status_error;
                        if (status_code == `M1A_STATUS_ERROR)
                            fault <= 1'b1;
                        else
                            fault <= 1'b0;
                        state <= ST_RESPOND;
                    end
                end

                ST_RESPOND: begin
                    if (!frame_tx_busy) begin
                        frame_tx_opcode  <= pending_response_opcode;
                        frame_tx_length  <= 3'd4;
                        frame_tx_payload <= {response_error, catalog_count,
                                             display_image_id, response_status};
                        frame_tx_request <= 1'b1;
                        reply_toggle     <= ~reply_toggle;
                        state            <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    // These descriptor fields are intentionally present in M1 so their width
    // contract is compiled even though the board demo only visualizes image_id.
    wire _unused_descriptor = ^descriptor_type ^ ^descriptor_width ^
                              ^descriptor_height ^ ^descriptor_frame_count ^
                              ^descriptor_duration;
endmodule
