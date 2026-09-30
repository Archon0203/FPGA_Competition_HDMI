`include "m1a_protocol.vh"

// From-board M1A shell. SPI byte ingress crosses into service_clk through an
// async FIFO; provider bytes use a separate explicit CDC interface.
module m1a_service_shell #(
    parameter integer SPI_FIFO_ADDR_WIDTH = 4,
    parameter integer MOCK_LINES = 480,
    parameter integer WORDS_PER_LINE = 160
)(
    input  wire        service_clk,
    input  wire        service_rst_n,
    input  wire        spi_clk,
    input  wire        spi_cs_n,
    input  wire        spi_mosi,
    output wire        spi_miso,
    output reg         spi_rx_overflow,

    input  wire        provider_clk,
    input  wire        provider_rst_n,
    input  wire        provider_valid,
    input  wire [7:0]  provider_data,
    output wire        provider_ready,
    output wire        provider_overflow,
    output wire        media_byte_valid,
    output wire [7:0]  media_byte_data,
    input  wire        media_byte_ready,

    input  wire        media_ready,
    output wire        media_valid,
    output wire [31:0] media_data,
    output wire        media_line_start,
    output wire        media_line_end,
    output wire        media_frame_end,
    output wire [15:0] media_frame_id,
    output wire [7:0]  media_image_id,
    output wire [15:0] media_line_index,

    output wire        catalog_valid,
    output wire [7:0]  catalog_count,
    output wire [15:0] catalog_epoch,
    output wire        descriptor_valid,
    output wire [7:0]  descriptor_image_id,
    output wire [1:0]  descriptor_type,
    output wire [15:0] descriptor_width,
    output wire [15:0] descriptor_height,
    output wire [15:0] descriptor_frame_count,
    output wire [31:0] descriptor_duration,
    output wire        status_valid,
    output wire [7:0]  status_code,
    output wire [7:0]  status_error,
    output wire        source_ready,
    output wire        source_busy,
    output wire        source_done,
    output wire        source_error,
    output wire [15:0] credit_level
);
    wire spi_rx_valid;
    wire [7:0] spi_rx_data;
    wire spi_tx_ready;
    wire [7:0] spi_tx_data;
    wire cmd_fifo_full, cmd_fifo_empty;
    wire [7:0] cmd_fifo_data;
    wire decoder_byte_ready;
    wire cmd_fifo_rd_en = ~cmd_fifo_empty & decoder_byte_ready;
    wire cmd_valid;
    wire cmd_ready;
    wire [7:0] cmd_opcode;
    wire [31:0] cmd_arg;
    wire cmd_error_valid;
    wire [7:0] cmd_error_code;

    // Latest-status mailbox: data remains stable while the toggle crosses.
    reg [7:0] status_mailbox;
    reg status_toggle;
    reg status_toggle_sync1, status_toggle_sync2, status_toggle_seen;
    reg [7:0] status_code_sync2;

    m1a_spi_slave u_spi_slave (
        .spi_clk(spi_clk), .spi_cs_n(spi_cs_n), .spi_mosi(spi_mosi),
        .spi_miso(spi_miso), .tx_data(spi_tx_data), .tx_ready(spi_tx_ready),
        .rx_valid(spi_rx_valid), .rx_data(spi_rx_data)
    );

    async_fifo #(.DATA_WIDTH(8), .ADDR_WIDTH(SPI_FIFO_ADDR_WIDTH)) u_spi_rx_fifo (
        .wr_clk(spi_clk), .wr_rst_n(service_rst_n),
        .wr_en(spi_rx_valid & ~cmd_fifo_full), .din(spi_rx_data),
        .rd_clk(service_clk), .rd_rst_n(service_rst_n), .rd_en(cmd_fifo_rd_en),
        .dout(cmd_fifo_data), .full(cmd_fifo_full), .empty(cmd_fifo_empty)
    );

    // SPI has no byte-level backpressure. Keep any FIFO overflow observable.
    always @(posedge spi_clk or negedge service_rst_n) begin
        if (!service_rst_n) spi_rx_overflow <= 1'b0;
        else if (spi_rx_valid && cmd_fifo_full) spi_rx_overflow <= 1'b1;
    end

    m1a_command_decoder u_decoder (
        .clk(service_clk), .rst_n(service_rst_n),
        .byte_valid(cmd_fifo_rd_en), .byte_data(cmd_fifo_data),
        .byte_ready(decoder_byte_ready), .cmd_valid(cmd_valid), .cmd_ready(cmd_ready),
        .cmd_opcode(cmd_opcode), .cmd_arg(cmd_arg),
        .error_valid(cmd_error_valid), .error_code(cmd_error_code)
    );

    m1a_provider_cdc u_provider_cdc (
        .src_clk(provider_clk), .src_rst_n(provider_rst_n),
        .src_valid(provider_valid), .src_data(provider_data),
        .src_ready(provider_ready), .src_overflow(provider_overflow),
        .dst_clk(service_clk), .dst_rst_n(service_rst_n),
        .dst_valid(media_byte_valid), .dst_data(media_byte_data),
        .dst_ready(media_byte_ready)
    );

    m1a_media_service_mock #(
        .MOCK_LINES(MOCK_LINES), .WORDS_PER_LINE(WORDS_PER_LINE)
    ) u_service (
        .clk(service_clk), .rst_n(service_rst_n),
        .cmd_valid(cmd_valid), .cmd_opcode(cmd_opcode), .cmd_arg(cmd_arg),
        .cmd_ready(cmd_ready), .catalog_valid(catalog_valid), .catalog_count(catalog_count),
        .catalog_epoch(catalog_epoch), .descriptor_valid(descriptor_valid),
        .descriptor_image_id(descriptor_image_id), .descriptor_type(descriptor_type),
        .descriptor_width(descriptor_width), .descriptor_height(descriptor_height),
        .descriptor_frame_count(descriptor_frame_count),
        .descriptor_duration(descriptor_duration), .status_valid(status_valid),
        .status_code(status_code), .status_error(status_error),
        .source_ready(source_ready), .source_busy(source_busy),
        .source_done(source_done), .source_error(source_error),
        .credit_level(credit_level), .media_valid(media_valid),
        .media_ready(media_ready), .media_data(media_data),
        .media_line_start(media_line_start), .media_line_end(media_line_end),
        .media_frame_end(media_frame_end), .media_frame_id(media_frame_id),
        .media_image_id(media_image_id), .media_line_index(media_line_index)
    );

    // Transfer status as a stable-data mailbox. Status events are serialized
    // by SPI command transactions; the receiver therefore captures the latest
    // state after synchronizing the event toggle rather than crossing 8 bits
    // independently through synchronizer flops.
    always @(posedge service_clk or negedge service_rst_n) begin
        if (!service_rst_n) begin
            status_mailbox <= `M1A_STATUS_ERROR;
            status_toggle <= 1'b0;
        end else if (status_valid) begin
            status_mailbox <= status_code;
            status_toggle <= ~status_toggle;
        end
    end

    always @(posedge spi_clk or negedge service_rst_n) begin
        if (!service_rst_n) begin
            status_toggle_sync1 <= 1'b0;
            status_toggle_sync2 <= 1'b0;
            status_toggle_seen <= 1'b0;
            status_code_sync2 <= `M1A_STATUS_ERROR;
        end else begin
            status_toggle_sync1 <= status_toggle;
            status_toggle_sync2 <= status_toggle_sync1;
            if (status_toggle_sync2 != status_toggle_seen) begin
                status_code_sync2 <= status_mailbox;
                status_toggle_seen <= status_toggle_sync2;
            end
        end
    end
    assign spi_tx_data = status_code_sync2;
endmodule
