// M2 Slave media core. All outputs are in clk domain; mem_wr_* goes to the
// Slave SDRAM arbiter. A separate read/packet path consumes committed frames.
module m2_slave_tf_media_core #(
    parameter integer SPI_CLK_DIV = 4,
    parameter integer SPI_INIT_CLK_DIV = SPI_CLK_DIV,
    parameter integer SPI_MODE3 = 0,
    parameter integer WIDTH = 640,
    parameter integer HEIGHT = 480
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        scan_start,
    input  wire        cmd_valid,
    output wire        cmd_ready,
    input  wire [7:0]  cmd_image_id,
    input  wire [20:0] frame_base,
    output wire        sd_ncs,
    output wire        sd_sclk,
    output wire        sd_mosi,
    input  wire        sd_miso,
    output wire        mem_wr_valid,
    output wire [20:0] mem_wr_addr,
    output wire [31:0] mem_wr_data,
    input  wire        mem_wr_ready,
    output wire        catalog_valid,
    output wire [7:0]  catalog_count,
    output wire [15:0] catalog_epoch,
    output wire        descriptor_valid,
    output wire [7:0]  descriptor_image_id,
    output wire [15:0] descriptor_width,
    output wire [15:0] descriptor_height,
    output wire        source_ready,
    output wire        source_busy,
    output wire        source_done,
    output wire        source_error,
    output wire [7:0]  error_code,
    output wire [7:0]  sector_error_detail
);
    wire sector_req, sector_ready, sector_idle, din_valid, sector_error;
    wire sector_consume_ready;
    wire [31:0] sector_lba;
    wire [7:0] din;

    m2_tf_sector_provider #(.SPI_CLK_DIV(SPI_CLK_DIV),
                            .SPI_INIT_CLK_DIV(SPI_INIT_CLK_DIV),
                            .SPI_MODE3(SPI_MODE3)) u_sector (
        .clk(clk), .rst_n(rst_n), .sector_req(sector_req),
        .sector_lba(sector_lba), .sector_ready(sector_ready),
        .serve_enable(sector_consume_ready),
        .sector_idle(sector_idle), .din_valid(din_valid), .din(din),
        .sector_error(sector_error), .sector_error_detail(sector_error_detail), .sd_ncs(sd_ncs),
        .sd_sclk(sd_sclk), .sd_mosi(sd_mosi), .sd_miso(sd_miso));

    m2_real_media_service #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) u_media (
        .clk(clk), .rst_n(rst_n), .scan_start(scan_start),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready),
        .cmd_image_id(cmd_image_id), .frame_base(frame_base),
        .sector_req(sector_req), .sector_lba(sector_lba),
        .sector_consume_ready(sector_consume_ready),
        .sector_ready(sector_ready), .sector_idle(sector_idle),
        .sector_din_valid(din_valid), .sector_din(din),
        .sector_error(sector_error),
        .mem_wr_valid(mem_wr_valid), .mem_wr_addr(mem_wr_addr),
        .mem_wr_data(mem_wr_data), .mem_wr_ready(mem_wr_ready),
        .catalog_valid(catalog_valid), .catalog_count(catalog_count),
        .catalog_epoch(catalog_epoch),
        .descriptor_valid(descriptor_valid),
        .descriptor_image_id(descriptor_image_id),
        .descriptor_width(descriptor_width),
        .descriptor_height(descriptor_height),
        .source_ready(source_ready), .source_busy(source_busy),
        .source_done(source_done), .source_error(source_error),
        .error_code(error_code));
endmodule
