`include "m1a_protocol.vh"

// M1A catalog boundary between the FAT32 scanner and the media service.
//
// The scanner writes one entry at a time while a scan is in progress.  The
// table is not visible to consumers until scan_done && scan_ok, so a partial
// or failed scan can never be presented as a valid catalog.  scan_start
// invalidates the previous catalog immediately and advances the epoch.
//
// The query response is a one-cycle descriptor_valid pulse.  Descriptor fields
// remain registered after the pulse and are therefore safe for a coordinator
// that samples them on the pulse.  A query is accepted only when query_ready
// is high; no request is silently dropped.
module m1a_catalog_table #(
    parameter integer FILE_MAX = 8
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        scan_start,
    input  wire        scan_done,
    input  wire        scan_ok,
    input  wire        entry_valid,
    input  wire [4:0]  entry_index,
    input  wire [1:0]  entry_type,
    input  wire [31:0] entry_cluster,
    input  wire [31:0] entry_size,
    input  wire [87:0] entry_name_83,
    input  wire [31:0] scan_fat_lba_base,
    input  wire [31:0] scan_data_lba_base,
    input  wire [7:0]  scan_sectors_per_cluster,

    input  wire        query_valid,
    input  wire [7:0]  query_image_id,
    output wire        query_ready,

    output reg         descriptor_valid,
    output reg  [7:0]  descriptor_image_id,
    output reg  [1:0]  descriptor_type,
    output reg  [31:0] descriptor_cluster,
    output reg  [31:0] descriptor_size,
    output reg  [87:0] descriptor_name_83,
    output reg  [31:0] descriptor_fat_lba_base,
    output reg  [31:0] descriptor_data_lba_base,
    output reg  [7:0]  descriptor_sectors_per_cluster,
    output reg  [15:0] descriptor_epoch,
    output reg         error_valid,
    output reg  [7:0]  error_code,

    output reg         catalog_valid,
    output reg  [7:0]  catalog_count,
    output reg  [15:0] catalog_epoch
);

    // FILE_MAX is intentionally bounded by the 5-bit index used by
    // fat32_scan.  Keeping the bound explicit avoids an accidental truncated
    // index when this module is configured for a larger table.
    localparam integer TABLE_MAX = (FILE_MAX > 32) ? 32 : FILE_MAX;

    reg [TABLE_MAX-1:0] present;
    reg [1:0]  type_mem [0:TABLE_MAX-1];
    reg [31:0] cluster_mem [0:TABLE_MAX-1];
    reg [31:0] size_mem [0:TABLE_MAX-1];
    reg [87:0] name_mem [0:TABLE_MAX-1];
    reg [31:0] fat_base_mem [0:TABLE_MAX-1];
    reg [31:0] data_base_mem [0:TABLE_MAX-1];
    reg [7:0]  spc_mem [0:TABLE_MAX-1];

    reg query_pending;
    wire query_index_valid = (query_image_id < TABLE_MAX);
    wire query_entry_present = query_index_valid && present[query_image_id[4:0]];

    assign query_ready = catalog_valid && !query_pending;

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            present <= {TABLE_MAX{1'b0}};
            query_pending <= 1'b0;
            descriptor_valid <= 1'b0;
            descriptor_image_id <= 8'd0;
            descriptor_type <= 2'd0;
            descriptor_cluster <= 32'd0;
            descriptor_size <= 32'd0;
            descriptor_name_83 <= {11{8'h20}};
            descriptor_fat_lba_base <= 32'd0;
            descriptor_data_lba_base <= 32'd0;
            descriptor_sectors_per_cluster <= 8'd0;
            descriptor_epoch <= 16'd0;
            error_valid <= 1'b0;
            error_code <= 8'd0;
            catalog_valid <= 1'b0;
            catalog_count <= 8'd0;
            catalog_epoch <= 16'd0;
            for (i = 0; i < TABLE_MAX; i = i + 1) begin
                type_mem[i] <= 2'd0;
                cluster_mem[i] <= 32'd0;
                size_mem[i] <= 32'd0;
                name_mem[i] <= {11{8'h20}};
                fat_base_mem[i] <= 32'd0;
                data_base_mem[i] <= 32'd0;
                spc_mem[i] <= 8'd0;
            end
        end else begin
            descriptor_valid <= 1'b0;
            error_valid <= 1'b0;

            // A new scan invalidates the old catalog before the first entry
            // arrives.  This prevents C from using stale image IDs.
            if (scan_start) begin
                present <= {TABLE_MAX{1'b0}};
                catalog_valid <= 1'b0;
                catalog_count <= 8'd0;
                catalog_epoch <= catalog_epoch + 16'd1;
                query_pending <= 1'b0;
            end

            if (entry_valid && (entry_index < TABLE_MAX)) begin
                present[entry_index] <= 1'b1;
                type_mem[entry_index] <= entry_type;
                cluster_mem[entry_index] <= entry_cluster;
                size_mem[entry_index] <= entry_size;
                name_mem[entry_index] <= entry_name_83;
                fat_base_mem[entry_index] <= scan_fat_lba_base;
                data_base_mem[entry_index] <= scan_data_lba_base;
                spc_mem[entry_index] <= scan_sectors_per_cluster;
                if (entry_index >= catalog_count)
                    catalog_count <= entry_index + 1'b1;
            end

            // Publish only a successful scan.  A failed scan leaves the
            // catalog invalid and forces the coordinator to wait for a retry.
            if (scan_done) begin
                if (scan_ok) begin
                    catalog_valid <= 1'b1;
                end else begin
                    catalog_valid <= 1'b0;
                end
            end

            // A rescan is a transaction boundary: discard outstanding work
            // and do not accept a request using the catalog being invalidated.
            if (scan_start) begin
                query_pending <= 1'b0;
            end else if (query_pending) begin
                query_pending <= 1'b0;
                if (query_entry_present) begin
                    descriptor_valid <= 1'b1;
                    descriptor_image_id <= query_image_id;
                    descriptor_type <= type_mem[query_image_id[4:0]];
                    descriptor_cluster <= cluster_mem[query_image_id[4:0]];
                    descriptor_size <= size_mem[query_image_id[4:0]];
                    descriptor_name_83 <= name_mem[query_image_id[4:0]];
                    descriptor_fat_lba_base <= fat_base_mem[query_image_id[4:0]];
                    descriptor_data_lba_base <= data_base_mem[query_image_id[4:0]];
                    descriptor_sectors_per_cluster <= spc_mem[query_image_id[4:0]];
                    descriptor_epoch <= catalog_epoch;
                end else begin
                    error_valid <= 1'b1;
                    error_code <= catalog_valid ? `M1A_ERR_BAD_IMAGE : `M1A_ERR_NOT_READY;
                end
            end else if (query_valid && query_ready) begin
                query_pending <= 1'b1;
            end
        end
    end
endmodule
