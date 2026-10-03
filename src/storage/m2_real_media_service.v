// Slave-side M2 media transaction. All sector, catalog and write signals use
// clk; the display/physical-link boundary is downstream of mem_wr_*.
module m2_real_media_service #(
    parameter integer FILE_MAX = 8,
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
    output wire        sector_req,
    output wire [31:0] sector_lba,
    output wire        sector_consume_ready,
    input  wire        sector_ready,
    input  wire        sector_idle,
    input  wire        sector_din_valid,
    input  wire [7:0]  sector_din,
    input  wire        sector_error,
    output wire        mem_wr_valid,
    output wire [20:0] mem_wr_addr,
    output wire [31:0] mem_wr_data,
    input  wire        mem_wr_ready,
    output wire        catalog_valid,
    output wire [7:0]  catalog_count,
    output wire [15:0] catalog_epoch,
    output reg         descriptor_valid,
    output reg  [7:0]  descriptor_image_id,
    output reg  [15:0] descriptor_width,
    output reg  [15:0] descriptor_height,
    output wire        source_ready,
    output wire        source_busy,
    output reg         source_done,
    output reg         source_error,
    output reg  [7:0]  error_code
);
    localparam [2:0] INIT=0, SCAN=1, IDLE=2, QUERY=3, LOAD=4, FAULT=5;
    reg [2:0] state;
    reg scan_pulse, query_pulse, load_pulse;
    reg [7:0] image_q;
    reg [20:0] base_q;
    reg [31:0] cluster_q, size_q, fat_q, data_q;
    reg [7:0] spc_q;
    wire cat_sector_req, load_sector_req;
    wire [31:0] cat_sector_lba, load_sector_lba;
    wire scan_done, scan_ok, query_ready, cat_descriptor_valid;
    wire [1:0] descriptor_type;
    wire [31:0] descriptor_cluster, descriptor_size, descriptor_fat, descriptor_data;
    wire [7:0] descriptor_spc;
    wire cat_error;
    wire [7:0] cat_error_code;
    wire load_ready, load_busy, load_done, load_ok;
    wire load_protocol_error, load_source_error, load_overflow;
    wire [3:0] load_protocol_detail;
    wire load_sector_consume_ready;
    wire [15:0] bmp_width, bmp_height;

    assign sector_req = (state == SCAN) ? cat_sector_req :
                        (state == LOAD) ? load_sector_req : 1'b0;
    assign sector_lba = (state == SCAN) ? cat_sector_lba : load_sector_lba;
    assign sector_consume_ready = (state != LOAD) || load_sector_consume_ready;
    assign cmd_ready = (state == IDLE) && catalog_valid && query_ready && sector_idle;
    assign source_ready = cmd_ready;
    assign source_busy = (state == SCAN || state == QUERY || state == LOAD);

    m1a_fat32_catalog #(.FILE_MAX(FILE_MAX)) u_catalog (
        .clk(clk), .rst_n(rst_n && state != FAULT), .scan_start(scan_pulse),
        .sector_req(cat_sector_req), .sector_lba(cat_sector_lba),
        .sector_ready(sector_ready && state == SCAN),
        .din_valid(sector_din_valid && state == SCAN), .din(sector_din),
        .scan_done(scan_done), .scan_ok(scan_ok), .scan_file_count(),
        .query_valid(query_pulse), .query_image_id(image_q),
        .query_ready(query_ready), .descriptor_valid(cat_descriptor_valid),
        .descriptor_image_id(), .descriptor_type(descriptor_type),
        .descriptor_cluster(descriptor_cluster), .descriptor_size(descriptor_size),
        .descriptor_fat_lba_base(descriptor_fat),
        .descriptor_data_lba_base(descriptor_data),
        .descriptor_sectors_per_cluster(descriptor_spc), .descriptor_epoch(),
        .error_valid(cat_error), .error_code(cat_error_code),
        .catalog_valid(catalog_valid), .catalog_count(catalog_count),
        .catalog_epoch(catalog_epoch));

    p1_media_framebuffer_loader #(
        .EXPECTED_WIDTH(WIDTH), .EXPECTED_HEIGHT(HEIGHT),
        .FRAME_STRIDE_WORDS(WIDTH),
        .STALL_TIMEOUT_CYCLES(5_000_000)
    ) u_loader (
        .clk(clk), .rst_n(rst_n && state != FAULT), .start(load_pulse), .frame_base(base_q),
        .ready(load_ready), .start_cluster(cluster_q), .file_size(size_q),
        .fat_lba_base(fat_q), .data_lba_base(data_q),
        .sectors_per_cluster(spc_q),
        .sector_req(load_sector_req), .sector_lba(load_sector_lba),
        .sector_ready(sector_ready && state == LOAD),
        .sector_din_valid(sector_din_valid && state == LOAD),
        .sector_din(sector_din),
        .sector_consume_ready(load_sector_consume_ready),
        .mem_wr_valid(mem_wr_valid), .mem_wr_addr(mem_wr_addr),
        .mem_wr_data(mem_wr_data), .mem_wr_ready(mem_wr_ready),
        .busy(load_busy), .done(load_done), .ok(load_ok),
        .protocol_error(load_protocol_error),
        .protocol_detail(load_protocol_detail),
        .source_error(load_source_error), .overflow(load_overflow),
        .bmp_width(bmp_width), .bmp_height(bmp_height),
        .bmp_data_offset(), .file_done(), .file_ok(),
        .pixels_done(), .pixels_ok());

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= INIT;
            scan_pulse <= 0; query_pulse <= 0; load_pulse <= 0;
            image_q <= 0; base_q <= 0;
            cluster_q <= 0; size_q <= 0; fat_q <= 0; data_q <= 0; spc_q <= 0;
            descriptor_valid <= 0; descriptor_image_id <= 0;
            descriptor_width <= 0; descriptor_height <= 0;
            source_done <= 0; source_error <= 0; error_code <= 0;
        end else begin
            scan_pulse <= 0; query_pulse <= 0; load_pulse <= 0;
            descriptor_valid <= 0; source_done <= 0; source_error <= 0;
            case (state)
                INIT: begin scan_pulse <= 1'b1; state <= SCAN; end
                SCAN: begin
                    if (sector_error) begin
                        source_error <= 1'b1; error_code <= 8'h11; state <= FAULT;
                    end else if (scan_done) begin
                        if (scan_ok) state <= IDLE;
                        else begin source_error <= 1'b1; error_code <= 8'h12; state <= FAULT; end
                    end
                end
                IDLE: begin
                    if (scan_start) begin scan_pulse <= 1'b1; state <= SCAN; end
                    else if (cmd_valid && cmd_ready) begin
                        image_q <= cmd_image_id;
                        base_q <= frame_base;
                        query_pulse <= 1'b1;
                        state <= QUERY;
                    end
                end
                QUERY: begin
                    if (cat_error) begin
                        source_error <= 1'b1; error_code <= cat_error_code;
                        state <= IDLE;
                    end else if (cat_descriptor_valid) begin
                        if (descriptor_type != 2'd1 || !load_ready) begin
                            source_error <= 1'b1; error_code <= 8'h13;
                            state <= IDLE;
                        end else begin
                            cluster_q <= descriptor_cluster; size_q <= descriptor_size;
                            fat_q <= descriptor_fat; data_q <= descriptor_data;
                            spc_q <= descriptor_spc;
                            load_pulse <= 1'b1;
                            state <= LOAD;
                        end
                    end
                end
                LOAD: begin
                    if (sector_error) begin
                        source_error <= 1'b1; error_code <= 8'h14;
                        state <= FAULT;
                    end else if (load_done) begin
                        if (load_ok) begin
                            descriptor_valid <= 1'b1;
                            descriptor_image_id <= image_q;
                            descriptor_width <= bmp_width;
                            descriptor_height <= bmp_height;
                            source_done <= 1'b1;
                            error_code <= 0;
                        end else begin
                            source_error <= 1'b1;
                            error_code <= load_overflow ? 8'h3D :
                                          load_protocol_error ?
                                          {4'h3, (load_protocol_detail != 4'd0) ?
                                                   load_protocol_detail : 4'hF} :
                                          8'h17;
                        end
                        state <= IDLE;
                    end
                end
                FAULT: if (scan_start) begin
                    scan_pulse <= 1'b1; error_code <= 0; state <= SCAN;
                end
                default: state <= INIT;
            endcase
        end
    end
endmodule
