// Standalone top for TD synthesis and place/route of the M1A block set.
// Wide internal media/catalog buses are folded into compact observability
// outputs so the timing harness fits the EG4S20BG256 package pin budget.
module m1a_validation_top (
    input  wire        service_clk,
    input  wire        service_rst_n,
    input  wire        spi_clk,
    input  wire        spi_cs_n,
    input  wire        spi_mosi,
    output wire        spi_miso,
    input  wire        provider_clk,
    input  wire        provider_rst_n,
    input  wire        provider_valid,
    input  wire [7:0]  provider_data,
    output wire        provider_ready,
    input  wire        media_ready,
    input  wire        scan_start,
    input  wire        sector_ready,
    input  wire        din_valid,
    input  wire [7:0]  din,
    input  wire        query_valid,
    input  wire [7:0]  query_image_id,
    output wire        sector_req,
    output wire [31:0] sector_lba,
    output wire        query_ready,
    output wire [31:0] observability,
    output wire [15:0] status_summary
);
    wire spi_rx_overflow;
    wire provider_overflow;
    wire media_byte_valid;
    wire [7:0] media_byte_data;
    wire media_valid;
    wire [31:0] media_data;
    wire media_line_start, media_line_end, media_frame_end;
    wire [15:0] media_frame_id;
    wire [7:0] media_image_id;
    wire [15:0] media_line_index;
    wire catalog_valid;
    wire [7:0] catalog_count;
    wire [15:0] catalog_epoch;
    wire descriptor_valid;
    wire [7:0] descriptor_image_id;
    wire [1:0] descriptor_type;
    wire [15:0] descriptor_width, descriptor_height, descriptor_frame_count;
    wire [31:0] descriptor_duration;
    wire status_valid;
    wire [7:0] status_code, status_error;
    wire source_ready, source_busy, source_done, source_error;
    wire [15:0] credit_level;

    wire scan_done, scan_ok;
    wire [4:0] scan_file_count;
    wire catalog_query_valid;
    wire [7:0] catalog_query_image_id;
    wire catalog_query_ready;
    wire descriptor_catalog_valid;
    wire [7:0] descriptor_catalog_image_id;
    wire [1:0] descriptor_catalog_type;
    wire [31:0] descriptor_cluster, descriptor_size;
    wire [31:0] descriptor_fat_lba_base, descriptor_data_lba_base;
    wire [7:0] descriptor_sectors_per_cluster;
    wire [15:0] descriptor_epoch;
    wire catalog_error_valid;
    wire [7:0] catalog_error_code;
    wire fat_catalog_valid;
    wire [7:0] fat_catalog_count;
    wire [15:0] fat_catalog_epoch;

    assign catalog_query_valid = query_valid;
    assign catalog_query_image_id = query_image_id;
    assign query_ready = catalog_query_ready;

    m1a_service_shell u_service_shell (
        .service_clk(service_clk), .service_rst_n(service_rst_n),
        .spi_clk(spi_clk), .spi_cs_n(spi_cs_n), .spi_mosi(spi_mosi),
        .spi_miso(spi_miso), .spi_rx_overflow(spi_rx_overflow),
        .provider_clk(provider_clk), .provider_rst_n(provider_rst_n),
        .provider_valid(provider_valid), .provider_data(provider_data),
        .provider_ready(provider_ready), .provider_overflow(provider_overflow),
        .media_byte_valid(media_byte_valid), .media_byte_data(media_byte_data),
        .media_byte_ready(1'b1), .media_ready(media_ready),
        .media_valid(media_valid), .media_data(media_data),
        .media_line_start(media_line_start), .media_line_end(media_line_end),
        .media_frame_end(media_frame_end), .media_frame_id(media_frame_id),
        .media_image_id(media_image_id), .media_line_index(media_line_index),
        .catalog_valid(catalog_valid), .catalog_count(catalog_count),
        .catalog_epoch(catalog_epoch), .descriptor_valid(descriptor_valid),
        .descriptor_image_id(descriptor_image_id), .descriptor_type(descriptor_type),
        .descriptor_width(descriptor_width), .descriptor_height(descriptor_height),
        .descriptor_frame_count(descriptor_frame_count),
        .descriptor_duration(descriptor_duration), .status_valid(status_valid),
        .status_code(status_code), .status_error(status_error),
        .source_ready(source_ready), .source_busy(source_busy),
        .source_done(source_done), .source_error(source_error),
        .credit_level(credit_level)
    );

    m1a_fat32_catalog u_fat32_catalog (
        .clk(service_clk), .rst_n(service_rst_n), .scan_start(scan_start),
        .sector_req(sector_req), .sector_lba(sector_lba),
        .sector_ready(sector_ready), .din_valid(din_valid), .din(din),
        .scan_done(scan_done), .scan_ok(scan_ok),
        .scan_file_count(scan_file_count), .query_valid(catalog_query_valid),
        .query_image_id(catalog_query_image_id), .query_ready(catalog_query_ready),
        .descriptor_valid(descriptor_catalog_valid),
        .descriptor_image_id(descriptor_catalog_image_id),
        .descriptor_type(descriptor_catalog_type),
        .descriptor_cluster(descriptor_cluster), .descriptor_size(descriptor_size),
        .descriptor_fat_lba_base(descriptor_fat_lba_base),
        .descriptor_data_lba_base(descriptor_data_lba_base),
        .descriptor_sectors_per_cluster(descriptor_sectors_per_cluster),
        .descriptor_epoch(descriptor_epoch), .error_valid(catalog_error_valid),
        .error_code(catalog_error_code), .catalog_valid(fat_catalog_valid),
        .catalog_count(fat_catalog_count), .catalog_epoch(fat_catalog_epoch)
    );

    // Fold every wide data/descriptor path into a small observable endpoint.
    // This prevents dead-code trimming while keeping top-level pads bounded.
    assign observability = media_data ^ descriptor_duration ^ descriptor_cluster ^
        descriptor_size ^ descriptor_fat_lba_base ^ descriptor_data_lba_base ^
        {media_frame_id, media_line_index} ^
        {descriptor_width, descriptor_height} ^
        {descriptor_frame_count, descriptor_catalog_image_id} ^
        {descriptor_image_id, media_image_id, descriptor_type,
         descriptor_catalog_type, descriptor_sectors_per_cluster, 2'b00} ^
        {media_byte_data, media_byte_valid, media_valid, media_line_start,
         media_line_end, media_frame_end, source_ready, source_busy,
         source_done, source_error, provider_overflow, spi_rx_overflow,
         status_error[3:0]};

    assign status_summary = {scan_done, scan_ok, scan_file_count,
        catalog_error_valid, catalog_error_code[2:0], fat_catalog_valid,
        fat_catalog_count[2:0], fat_catalog_epoch[0]} ^
        {catalog_valid, catalog_count[6:0], catalog_epoch[7:0]};
endmodule
