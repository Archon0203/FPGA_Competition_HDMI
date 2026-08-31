// ================================================================
// 模块   : fat32_file_reader
// 功能   : FAT32 文件读取器（P0-01）。
//           输入起始 cluster 与 file_size，遍历 FAT chain，按
//           file_size 输出文件字节流；支持 fragmented FAT chain、
//           跨 sector、非 sector 整数倍文件大小。
//           EOC 作为 FAT chain 完成检查；若 file_size 尚未读完
//           却遇到 EOC，则判为 premature EOC 错误。
// 作者   : FPGA 竞赛团队
// 日期   : 2026-08-31
// 版本   : v1.0
// 端口说明:
//   - clk / rst_n(低有效) : 时钟与复位
//   - start               : 单拍启动
//   - start_cluster       : 文件起始 cluster
//   - file_size           : 文件字节数（最终输出边界）
//   - fat_lba_base        : FAT 区域起始 LBA
//   - data_lba_base       : 数据区域起始 LBA(cluster 2 对应 sector)
//   - sectors_per_cluster : 每 cluster sector 数
//   - sector_req/lba      : 请求读 sector（电平请求，lba 有效）
//   - sector_ready/din_valid/din : sector 字节流
//   - byte_valid/byte_data : 输出文件字节流
//   - done/ok             : 完成/成功
// 时钟域: clk 为 SD/读卡时钟域(clk_sdo)。
// 修改历史:
//   2026-08-31 v1.0 初版, 按 Architecture Freeze v1.0 P0-01 实现。
// ================================================================

module fat32_file_reader #(
    parameter integer SECTOR_BYTES = 512,
    parameter integer STALL_TIMEOUT_CYCLES = 200000
)(
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    input  wire [31:0]   start_cluster,
    input  wire [31:0]   file_size,
    input  wire [31:0]   fat_lba_base,
    input  wire [31:0]   data_lba_base,
    input  wire [7:0]    sectors_per_cluster,

    output reg           sector_req,
    output reg  [31:0]   sector_lba,
    input  wire          sector_ready,
    input  wire          din_valid,
    input  wire [7:0]    din,

    output reg           byte_valid,
    output reg  [7:0]    byte_data,
    output reg           done,
    output reg           ok
);

    localparam [3:0]
        S_IDLE         = 4'd0,
        S_DATA_REQ     = 4'd1,
        S_DATA_STREAM  = 4'd2,
        S_FAT_REQ      = 4'd3,
        S_FAT_STREAM   = 4'd4,
        S_FAT_EVAL     = 4'd5,
        S_WAIT_RELEASE = 4'd6,
        S_DONE         = 4'd7,
        S_ABORT        = 4'd8;

    reg [3:0] state;
    reg [3:0] release_next_state;

    reg [31:0] cur_cluster;
    reg [31:0] remaining;
    reg [7:0]  sector_in_cluster;
    reg [8:0]  byte_idx;

    // FAT32 entry is 4 bytes. With 512-byte sectors the offset is 0..508.
    // 9 bits are required; the old 8-bit offset silently broke entries >= cluster 64.
    reg [8:0] fat_byte_off_latched;
    reg [7:0] fat_b0, fat_b1, fat_b2, fat_b3;

    reg [31:0] stall_cnt;

    wire [31:0] fat_entry_byte_index = cur_cluster << 2;
    wire [31:0] fat_sector_lba_calc  = fat_lba_base +
                                        (fat_entry_byte_index / SECTOR_BYTES);
    wire [8:0]  fat_byte_off_calc    = fat_entry_byte_index % SECTOR_BYTES;

    wire [31:0] data_sector_lba_calc = data_lba_base +
                                        ((cur_cluster - 32'd2) * sectors_per_cluster) +
                                        sector_in_cluster;

    wire [31:0] fat_value = {fat_b3, fat_b2, fat_b1, fat_b0} & 32'h0FFFFFFF;
    wire        fat_is_eoc = (fat_value >= 32'h0FFFFFF8);
    wire        fat_is_valid_data_cluster =
                    (fat_value >= 32'd2) && (fat_value < 32'h0FFFFFF0);

    wire        start_cluster_valid =
                    (start_cluster >= 32'd2) &&
                    (start_cluster < 32'h0FFFFFF0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                  <= S_IDLE;
            release_next_state     <= S_IDLE;
            sector_req             <= 1'b0;
            sector_lba             <= 32'd0;
            byte_valid             <= 1'b0;
            byte_data              <= 8'd0;
            done                   <= 1'b0;
            ok                     <= 1'b0;
            cur_cluster            <= 32'd0;
            remaining              <= 32'd0;
            sector_in_cluster      <= 8'd0;
            byte_idx               <= 9'd0;
            fat_byte_off_latched   <= 9'd0;
            fat_b0                 <= 8'd0;
            fat_b1                 <= 8'd0;
            fat_b2                 <= 8'd0;
            fat_b3                 <= 8'd0;
            stall_cnt              <= 32'd0;
        end else begin
            byte_valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    sector_req <= 1'b0;
                    done       <= 1'b0;
                    ok         <= 1'b0;
                    stall_cnt  <= 32'd0;

                    if (start) begin
                        if (file_size == 32'd0) begin
                            done  <= 1'b1;
                            ok    <= 1'b1;
                            state <= S_DONE;
                        end else if ((sectors_per_cluster == 8'd0) ||
                                     !start_cluster_valid ||
                                     (SECTOR_BYTES != 512)) begin
                            done  <= 1'b1;
                            ok    <= 1'b0;
                            state <= S_ABORT;
                        end else begin
                            cur_cluster       <= start_cluster;
                            remaining         <= file_size;
                            sector_in_cluster <= 8'd0;
                            state             <= S_DATA_REQ;
                        end
                    end
                end

                S_DATA_REQ: begin
                    sector_req <= 1'b1;
                    sector_lba <= data_sector_lba_calc;
                    byte_idx   <= 9'd0;
                    stall_cnt  <= 32'd0;
                    state      <= S_DATA_STREAM;
                end

                S_DATA_STREAM: begin
                    // sector_req intentionally remains asserted for the whole block.
                    sector_req <= 1'b1;

                    if (sector_ready && din_valid) begin
                        stall_cnt <= 32'd0;

                        // file_size is the sole output boundary. Bytes beyond the end
                        // of file in the final sector are consumed but not emitted.
                        if (remaining != 32'd0) begin
                            byte_valid <= 1'b1;
                            byte_data  <= din;
                            remaining  <= remaining - 32'd1;
                        end

                        if (byte_idx == SECTOR_BYTES-1) begin
                            sector_req <= 1'b0;
                            byte_idx   <= 9'd0;

                            // remaining is the pre-clock value here. If it is 0,
                            // file ended earlier in this sector; if it is 1, the
                            // current byte is the final file byte.
                            if (remaining <= 32'd1) begin
                                // Finish the physical block transaction first;
                                // done is asserted only after sector_ready releases.
                                release_next_state <= S_DONE;
                                state              <= S_WAIT_RELEASE;
                            end else if (sector_in_cluster + 8'd1 < sectors_per_cluster) begin
                                sector_in_cluster  <= sector_in_cluster + 8'd1;
                                release_next_state <= S_DATA_REQ;
                                state              <= S_WAIT_RELEASE;
                            end else begin
                                // Need another cluster; resolve FAT[cur_cluster].
                                sector_in_cluster  <= 8'd0;
                                release_next_state <= S_FAT_REQ;
                                state              <= S_WAIT_RELEASE;
                            end
                        end else begin
                            byte_idx <= byte_idx + 9'd1;
                        end
                    end else begin
                        if (stall_cnt >= STALL_TIMEOUT_CYCLES-1) begin
                            sector_req <= 1'b0;
                            done       <= 1'b1;
                            ok         <= 1'b0;
                            state      <= S_ABORT;
                        end else begin
                            stall_cnt <= stall_cnt + 32'd1;
                        end
                    end
                end

                S_FAT_REQ: begin
                    sector_req           <= 1'b1;
                    sector_lba           <= fat_sector_lba_calc;
                    fat_byte_off_latched <= fat_byte_off_calc;
                    byte_idx             <= 9'd0;
                    fat_b0               <= 8'd0;
                    fat_b1               <= 8'd0;
                    fat_b2               <= 8'd0;
                    fat_b3               <= 8'd0;
                    stall_cnt            <= 32'd0;
                    state                <= S_FAT_STREAM;
                end

                S_FAT_STREAM: begin
                    sector_req <= 1'b1;

                    if (sector_ready && din_valid) begin
                        stall_cnt <= 32'd0;

                        if (byte_idx == fat_byte_off_latched)          fat_b0 <= din;
                        if (byte_idx == fat_byte_off_latched + 9'd1)  fat_b1 <= din;
                        if (byte_idx == fat_byte_off_latched + 9'd2)  fat_b2 <= din;
                        if (byte_idx == fat_byte_off_latched + 9'd3)  fat_b3 <= din;

                        if (byte_idx == SECTOR_BYTES-1) begin
                            sector_req         <= 1'b0;
                            byte_idx           <= 9'd0;
                            release_next_state <= S_FAT_EVAL;
                            state              <= S_WAIT_RELEASE;
                        end else begin
                            byte_idx <= byte_idx + 9'd1;
                        end
                    end else begin
                        if (stall_cnt >= STALL_TIMEOUT_CYCLES-1) begin
                            sector_req <= 1'b0;
                            done       <= 1'b1;
                            ok         <= 1'b0;
                            state      <= S_ABORT;
                        end else begin
                            stall_cnt <= stall_cnt + 32'd1;
                        end
                    end
                end

                S_FAT_EVAL: begin
                    // We only arrive here if remaining > 0, therefore EOC now is
                    // premature by definition.
                    if (fat_is_valid_data_cluster) begin
                        cur_cluster       <= fat_value;
                        sector_in_cluster <= 8'd0;
                        state             <= S_DATA_REQ;
                    end else begin
                        // EOC, free cluster, bad cluster and reserved cluster all
                        // indicate a broken/short chain for this requested file_size.
                        done  <= 1'b1;
                        ok    <= 1'b0;
                        state <= S_ABORT;
                    end
                end

                S_WAIT_RELEASE: begin
                    sector_req <= 1'b0;
                    stall_cnt  <= 32'd0;
                    if (!sector_ready)
                        state <= release_next_state;
                end

                S_DONE: begin
                    sector_req <= 1'b0;
                    done       <= 1'b1;
                    ok         <= 1'b1;
                    if (start) begin
                        done <= 1'b0;
                        ok   <= 1'b0;
                        if (file_size == 32'd0) begin
                            done <= 1'b1;
                            ok   <= 1'b1;
                        end else if ((sectors_per_cluster == 8'd0) ||
                                     !start_cluster_valid ||
                                     (SECTOR_BYTES != 512)) begin
                            done  <= 1'b1;
                            ok    <= 1'b0;
                            state <= S_ABORT;
                        end else begin
                            cur_cluster       <= start_cluster;
                            remaining         <= file_size;
                            sector_in_cluster <= 8'd0;
                            state             <= S_DATA_REQ;
                        end
                    end
                end

                S_ABORT: begin
                    sector_req <= 1'b0;
                    done       <= 1'b1;
                    ok         <= 1'b0;
                    if (start) begin
                        done <= 1'b0;
                        ok   <= 1'b0;
                        if (file_size == 32'd0) begin
                            done  <= 1'b1;
                            ok    <= 1'b1;
                            state <= S_DONE;
                        end else if ((sectors_per_cluster == 8'd0) ||
                                     !start_cluster_valid ||
                                     (SECTOR_BYTES != 512)) begin
                            done  <= 1'b1;
                            ok    <= 1'b0;
                            state <= S_ABORT;
                        end else begin
                            cur_cluster       <= start_cluster;
                            remaining         <= file_size;
                            sector_in_cluster <= 8'd0;
                            state             <= S_DATA_REQ;
                        end
                    end
                end

                default: begin
                    sector_req <= 1'b0;
                    done       <= 1'b1;
                    ok         <= 1'b0;
                    state      <= S_ABORT;
                end
            endcase
        end
    end

endmodule