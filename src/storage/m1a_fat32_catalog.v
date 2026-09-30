// M1A real FAT32 catalog path: sector byte stream -> existing scanner ->
// transactional catalog table.  This remains independent of the active top.
module m1a_fat32_catalog #(
    parameter integer FILE_MAX = 8,
    parameter integer SECTOR_BYTES = 512
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        scan_start,
    output wire        sector_req,
    output wire [31:0] sector_lba,
    input  wire        sector_ready,
    input  wire        din_valid,
    input  wire [7:0]  din,
    output wire        scan_done,
    output wire        scan_ok,
    output wire [4:0]  scan_file_count,
    input  wire        query_valid,
    input  wire [7:0]  query_image_id,
    output wire        query_ready,
    output wire        descriptor_valid,
    output wire [7:0]  descriptor_image_id,
    output wire [1:0]  descriptor_type,
    output wire [31:0] descriptor_cluster,
    output wire [31:0] descriptor_size,
    output wire [31:0] descriptor_fat_lba_base,
    output wire [31:0] descriptor_data_lba_base,
    output wire [7:0]  descriptor_sectors_per_cluster,
    output wire [15:0] descriptor_epoch,
    output wire        error_valid,
    output wire [7:0]  error_code,
    output wire        catalog_valid,
    output wire [7:0]  catalog_count,
    output wire [15:0] catalog_epoch
);
    wire [4:0] file_index;
    wire [1:0] file_type;
    wire [31:0] file_cluster, file_size;
    wire file_wr;
    wire [31:0] fat_lba_base, data_lba_base;
    wire [7:0] sectors_per_cluster;

    fat32_scan #(.FILE_MAX(FILE_MAX), .SECTOR_BYTES(SECTOR_BYTES)) u_scan (
        .clk(clk), .rst_n(rst_n), .start(scan_start),
        .sector_req(sector_req), .sector_lba(sector_lba),
        .sector_ready(sector_ready), .din_valid(din_valid), .din(din),
        .scan_done(scan_done), .scan_ok(scan_ok),
        .file_count(scan_file_count), .file_index(file_index),
        .file_type(file_type), .file_cluster(file_cluster),
        .file_size(file_size), .file_wr(file_wr),
        .fat_lba_base(fat_lba_base), .data_lba_base(data_lba_base),
        .sectors_per_cluster(sectors_per_cluster)
    );

    m1a_catalog_table #(.FILE_MAX(FILE_MAX)) u_catalog (
        .clk(clk), .rst_n(rst_n), .scan_start(scan_start),
        .scan_done(scan_done), .scan_ok(scan_ok),
        .entry_valid(file_wr), .entry_index(file_index),
        .entry_type(file_type), .entry_cluster(file_cluster),
        .entry_size(file_size), .scan_fat_lba_base(fat_lba_base),
        .scan_data_lba_base(data_lba_base),
        .scan_sectors_per_cluster(sectors_per_cluster),
        .query_valid(query_valid), .query_image_id(query_image_id),
        .query_ready(query_ready), .descriptor_valid(descriptor_valid),
        .descriptor_image_id(descriptor_image_id),
        .descriptor_type(descriptor_type),
        .descriptor_cluster(descriptor_cluster),
        .descriptor_size(descriptor_size),
        .descriptor_fat_lba_base(descriptor_fat_lba_base),
        .descriptor_data_lba_base(descriptor_data_lba_base),
        .descriptor_sectors_per_cluster(descriptor_sectors_per_cluster),
        .descriptor_epoch(descriptor_epoch), .error_valid(error_valid),
        .error_code(error_code), .catalog_valid(catalog_valid),
        .catalog_count(catalog_count), .catalog_epoch(catalog_epoch)
    );
endmodule
