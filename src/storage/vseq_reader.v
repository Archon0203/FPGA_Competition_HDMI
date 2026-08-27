// ================================================================
// 模块   : vseq_reader
// 功能   : 解析自定义 .vseq 容器(见 docs/06):
//           Header 64B: magic "VSEQ"|ver|width|height|bpp|fps|frame_count|保留
//           Body: frame_count 个原始帧, 每帧 frame_size = width*height*bpp/8 字节。
//           解析完成后按帧流式输出字节, 并给出帧边界。
// 作者   : FPGA 竞赛团队
// 日期   : 2026-08-27
// 版本   : v1.0
// 端口说明:
//   - clk / rst_n(低有效) : 读卡时钟
//   - din_valid / din[7:0]: 输入字节流
//   - vseq_ok             : 魔数 VSEQ 校验通过
//   - header_done         : 头解析完成
//   - width[15:0]/height[15:0]: 帧宽高
//   - bpp[5:0]/fps[7:0]   : 位深/帧率
//   - frame_count[15:0]   : 帧数
//   - byte_valid/byte_data[7:0]: 帧体字节输出
//   - frame_start / frame_done  : 帧起始/结束(单拍)
//   - all_done            : 全部帧输出完成
// 说明   : 小端解析; frame_size 用 32 位计算, 支持 1280x720x32。
// 时钟域: clk 为 SD 读卡时钟域(clk_sdo)。
// 修改历史:
//   2026-08-27 v1.0 初版, 按文档11任务卡 T7 实现。
//   2026-08-27 v1.1 修复 frame_size 计算位宽截断，支持真实 320x240 等分辨率。
// ================================================================

module vseq_reader #(
    parameter integer W = 16,
    parameter integer H = 16
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        din_valid,
    input  wire [7:0]  din,
    output reg         vseq_ok,
    output reg         header_done,
    output reg  [W-1:0] width,
    output reg  [H-1:0] height,
    output reg  [5:0]  bpp,
    output reg  [7:0]  fps,
    output reg  [15:0] frame_count,
    output wire        byte_valid,
    output wire [7:0]  byte_data,
    output wire        frame_start,
    output wire        frame_done,
    output reg         all_done
);

    localparam [1:0] S_HEADER = 2'd0, S_BODY = 2'd1, S_DONE = 2'd2;

    reg  [1:0] state;
    reg  [6:0] hdr_idx;            // 0..63
    reg  [7:0] m0,m1,m2,m3, ver;
    reg  [7:0] w0,w1, h0,h1, bpp_r, fps_r, fc0, fc1;
    reg  [31:0] frame_byte;        // 当前帧内字节数
    reg  [15:0] frame_idx;         // 已输出帧数

    // 显式将宽/高/位深零扩展到 32 位再相乘，防止 16bit*16bit 被截断。
    wire [31:0] w32 = {16'b0, width};
    wire [31:0] h32 = {16'b0, height};
    wire [31:0] b32 = {26'b0, bpp};
    wire [31:0] frame_size = (w32 * h32 * b32) >> 3;

    // 头字段提取
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_HEADER;
            hdr_idx  <= 7'd0;
            m0<=8'd0; m1<=8'd0; m2<=8'd0; m3<=8'd0; ver<=8'd0;
            w0<=8'd0; w1<=8'd0; h0<=8'd0; h1<=8'd0;
            bpp_r<=8'd0; fps_r<=8'd0; fc0<=8'd0; fc1<=8'd0;
            frame_byte <= 32'd0;
            frame_idx  <= 16'd0;
            header_done <= 1'b0;
            all_done    <= 1'b0;
        end else begin
            case (state)
                S_HEADER: begin
                    if (din_valid) begin
                        case (hdr_idx)
                            7'd0: m0 <= din;
                            7'd1: m1 <= din;
                            7'd2: m2 <= din;
                            7'd3: m3 <= din;
                            7'd4: ver <= din;
                            7'd5: w0 <= din;
                            7'd6: w1 <= din;
                            7'd7: h0 <= din;
                            7'd8: h1 <= din;
                            7'd9: bpp_r <= din;
                            7'd10: fps_r <= din;
                            7'd11: fc0 <= din;
                            7'd12: fc1 <= din;
                            default: ;
                        endcase
                        if (hdr_idx == 7'd63) begin
                            header_done <= 1'b1;
                            state       <= (frame_size == 0) ? S_DONE : S_BODY;
                            frame_byte  <= 32'd0;
                            frame_idx   <= 16'd0;
                        end else begin
                            hdr_idx <= hdr_idx + 1'b1;
                        end
                    end
                end
                S_BODY: begin
                    if (din_valid) begin
                        if (frame_byte >= frame_size - 1'b1) begin
                            frame_byte <= 32'd0;
                            frame_idx  <= frame_idx + 1'b1;
                            if (frame_idx + 1'b1 >= frame_count) begin
                                state     <= S_DONE;
                                all_done  <= 1'b1;
                            end
                        end else begin
                            frame_byte <= frame_byte + 1'b1;
                        end
                    end
                end
                S_DONE: all_done <= all_done;
                default: state <= S_HEADER;
            endcase
        end
    end

    // 组合输出
    assign byte_valid = (state == S_BODY) && din_valid;
    assign byte_data  = din;
    assign frame_start = byte_valid && (frame_byte == 32'd0);
    assign frame_done  = byte_valid && (frame_byte >= frame_size - 1'b1);

    // 头字段组合
    always @(*) begin
        vseq_ok     = (m0 == 8'h56) && (m1 == 8'h53) && (m2 == 8'h45) && (m3 == 8'h51); // VSEQ
        width       = {w1, w0};
        height      = {h1, h0};
        bpp         = bpp_r[5:0];
        fps         = fps_r;
        frame_count = {fc1, fc0};
    end

endmodule
