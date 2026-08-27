// ================================================================
// 模块   : fat32_scan
// 功能   : FAT32 文件索引扫描(纯 RTL)。
//           读取 MBR -> 找 FAT32 分区 -> 读取引导扇区(BPB)
//           -> 读取根目录首扇区 -> 解析 32B 目录项, 建立文件索引。
//           支持 8.3 短名, 扩展名 BMP/SEQ 分别记为图片/视频片段;
//           VFAT 长文件名(.vseq 等)需后续扩展(工具可生成 8.3 名)。
// 作者   : FPGA 竞赛团队
// 日期   : 2026-08-27
// 版本   : v1.0
// 端口说明:
//   - clk / rst_n(低有效) : 系统/SD 时钟
//   - start               : 启动扫描(单拍)
//   - sector_req          : 请求读扇区(电平, 请求期间保持 lba 有效)
//   - sector_lba[31:0]    : 要读的 LBA
//   - din_valid/din[7:0]  : 扇区字节流
//   - scan_done/scan_ok   : 扫描完成/成功
//   - file_count[4:0]     : 找到文件数
//   - file_index[4:0]     : 当前写入索引(0..FILE_MAX-1)
//   - file_type[1:0]      : 1=BMP 2=SEQ
//   - file_cluster[31:0]  : 起始簇
//   - file_size[31:0]     : 字节大小
//   - file_wr             : 索引写有效(单拍)
// 参数:
//   - FILE_MAX            : 索引条目上限(默认 8)
//   - SECTOR_BYTES        : 扇区字节数(默认 512)
// 说明   : 当前扫描根目录第一簇的第一扇区; 子目录/多簇根目录后续扩展。
// 时钟域: clk 为 SD 读卡时钟域。
// 修改历史:
//   2026-08-27 v1.0 初版, 按文档11任务卡 T5 实现。
// ================================================================

module fat32_scan #(
    parameter integer FILE_MAX     = 8,
    parameter integer SECTOR_BYTES = 512
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    output reg         sector_req,
    output reg  [31:0] sector_lba,
    input  wire        sector_ready,
    input  wire        din_valid,
    input  wire [7:0]  din,
    output reg         scan_done,
    output reg         scan_ok,
    output reg  [4:0]  file_count,
    output reg  [4:0]  file_index,
    output reg  [1:0]  file_type,
    output reg  [31:0] file_cluster,
    output reg  [31:0] file_size,
    output reg         file_wr
);

    localparam [2:0] S_IDLE=0, S_MBR=1, S_BOOT=2, S_ROOT=3, S_DONE=4, S_GAP=5;

    reg  [2:0]  state;
    reg  [2:0]  next_state;
    reg  [8:0]  byte_idx;
    // MBR 分区
    reg  [7:0]  ptype;
    reg  [31:0] part_lba;
    // BPB
    reg  [15:0] bps;
    reg  [7:0]  spc;
    reg  [15:0] reserved;
    reg  [7:0]  num_fats;
    reg  [31:0] fat_sz;
    reg  [31:0] root_clu;
    // 当前目录项
    reg  [7:0]  entry_state;   // bit0=entry0x00, bit1=deleted, bit2=dir
    reg  [7:0]  ext0, ext1, ext2;
    reg  [15:0] clu_hi, clu_lo;
    reg  [31:0] cur_size;

    wire [31:0] root_lba = part_lba + reserved + (num_fats * fat_sz) +
                           ((root_clu - 2) * spc);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state  <= S_IDLE;
            byte_idx <= 9'd0;
            sector_req <= 1'b0;
            sector_lba <= 32'd0;
            ptype <= 8'd0; part_lba <= 32'd0;
            bps <= 16'd0; spc <= 8'd0; reserved <= 16'd0;
            num_fats <= 8'd0; fat_sz <= 32'd0; root_clu <= 32'd0;
            entry_state <= 8'd0; ext0<=8'd0; ext1<=8'd0; ext2<=8'd0;
            clu_hi<=16'd0; clu_lo<=16'd0; cur_size<=32'd0;
            scan_done <= 1'b0; scan_ok <= 1'b0;
            file_count <= 5'd0; file_index <= 5'd0;
            file_type <= 2'd0; file_cluster <= 32'd0; file_size <= 32'd0;
            file_wr <= 1'b0;
        end else begin
            file_wr <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start) begin
                        state      <= S_MBR;
                        byte_idx   <= 9'd0;
                        sector_lba <= 32'd0;
                        sector_req <= 1'b1;
                    end
                end
                S_MBR: begin
                    if (din_valid && sector_ready) begin
                        if (byte_idx == 9'd450) ptype <= din;
                        if (byte_idx >= 9'd454 && byte_idx <= 9'd457)
                            part_lba[(byte_idx-9'd454)*8 +: 8] <= din;
                        if (byte_idx == SECTOR_BYTES-1) begin
                            sector_req <= 1'b0;
                            byte_idx   <= 9'd0;
                            if (ptype == 8'h0B || ptype == 8'h0C) begin
                                state      <= S_GAP;
                                next_state <= S_BOOT;
                                sector_lba <= part_lba;
                                sector_req <= 1'b0;
                            end else begin
                                state <= S_DONE;
                                scan_done <= 1'b1;
                                scan_ok   <= 1'b0;
                            end
                        end else begin
                            byte_idx <= byte_idx + 1'b1;
                        end
                    end
                end
                S_BOOT: begin
                    if (din_valid && sector_ready) begin
                        if (byte_idx == 9'd11)  bps[7:0]    <= din;
                        if (byte_idx == 9'd12)  bps[15:8]   <= din;
                        if (byte_idx == 9'd13)  spc         <= din;
                        if (byte_idx == 9'd14)  reserved[7:0] <= din;
                        if (byte_idx == 9'd15)  reserved[15:8] <= din;
                        if (byte_idx == 9'd16)  num_fats    <= din;
                        if (byte_idx >= 9'd36 && byte_idx <= 9'd39)
                            fat_sz[(byte_idx-9'd36)*8 +: 8] <= din;
                        if (byte_idx >= 9'd44 && byte_idx <= 9'd47)
                            root_clu[(byte_idx-9'd44)*8 +: 8] <= din;
                        if (byte_idx == SECTOR_BYTES-1) begin
                            sector_req <= 1'b0;
                            byte_idx   <= 9'd0;
                            state      <= S_GAP;
                            next_state <= S_ROOT;
                            sector_lba <= root_lba;
                            entry_state <= 8'd0;
                        end else begin
                            byte_idx <= byte_idx + 1'b1;
                        end
                    end
                end
                S_ROOT: begin
                    if (din_valid && sector_ready) begin
                        if ((byte_idx & 9'd31) == 9'd0) begin
                            entry_state <= 8'h00;
                            if (din == 8'h00) entry_state[0] <= 1'b1;   // 结束
                            else if (din == 8'hE5) entry_state[1] <= 1'b1; // 已删除
                        end
                        if ((byte_idx & 9'd31) == 9'd8)  ext0 <= din;
                        if ((byte_idx & 9'd31) == 9'd9)  ext1 <= din;
                        if ((byte_idx & 9'd31) == 9'd10) ext2 <= din;
                        if ((byte_idx & 9'd31) == 9'd11) begin
                            if (din & 8'h10) entry_state[2] <= 1'b1;    // 目录
                        end
                        if ((byte_idx & 9'd31) == 9'd20) clu_hi[7:0] <= din;
                        if ((byte_idx & 9'd31) == 9'd21) clu_hi[15:8] <= din;
                        if ((byte_idx & 9'd31) == 9'd26) clu_lo[7:0] <= din;
                        if ((byte_idx & 9'd31) == 9'd27) clu_lo[15:8] <= din;
                        if ((byte_idx & 9'd31) >= 9'd28 && (byte_idx & 9'd31) <= 9'd31)
                            cur_size[((byte_idx & 9'd31)-9'd28)*8 +: 8] <= din;

                        // 字节 31 结束一个条目
                        if ((byte_idx & 9'd31) == 9'd31) begin
                            if (entry_state[0]) begin
                                // 目录结束
                                state <= S_DONE;
                                scan_done <= 1'b1;
                                scan_ok   <= 1'b1;
                                sector_req <= 1'b0;
                            end else if (!entry_state[1] && !entry_state[2] &&
                                         file_count < FILE_MAX) begin
                                if ((ext0==8'h42 && ext1==8'h4D && ext2==8'h50)) begin // BMP
                                    file_type     <= 2'd1;
                                    file_cluster  <= {clu_hi, clu_lo};
                                    file_size     <= cur_size;
                                    file_index    <= file_count;
                                    file_count    <= file_count + 1'b1;
                                    file_wr       <= 1'b1;
                                end else if ((ext0==8'h53 && ext1==8'h45 && ext2==8'h51)) begin // SEQ
                                    file_type     <= 2'd2;
                                    file_cluster  <= {clu_hi, clu_lo};
                                    file_size     <= cur_size;
                                    file_index    <= file_count;
                                    file_count    <= file_count + 1'b1;
                                    file_wr       <= 1'b1;
                                end
                            end
                        end

                        if (byte_idx == SECTOR_BYTES-1) begin
                            // 扇区读完(无 0x00 结束也结束)
                            if (state == S_ROOT && !scan_done) begin
                                state <= S_DONE;
                                scan_done <= 1'b1;
                                scan_ok   <= 1'b1;
                                sector_req <= 1'b0;
                            end
                        end else begin
                            byte_idx <= byte_idx + 1'b1;
                        end
                    end
                end
                S_DONE: begin
                    sector_req <= 1'b0;
                end
                S_GAP: begin
                    sector_req <= 1'b1;   // 拉低一拍后重新请求下一扇区
                    state      <= next_state;
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
