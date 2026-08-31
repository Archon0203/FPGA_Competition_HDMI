// ================================================================
// 模块   : bmp_pixel_stream
// 功能   : P0-02 BMP 像素流解包器。
//           与 bmp_parser 共享同一文件字节流；在 header_done 后从
//           首个像素字节开始消费 24-bit BI_RGB BMP 像素阵列：
//             - BGR888 -> RGB888
//             - 处理每行 4-byte 对齐 padding
//             - 将 BMP bottom-up 文件行映射为显示坐标 y
//             - 输出 pixel_x / pixel_y / pixel_valid
//           本模块不感知 SDRAM，不生成 framebuffer 地址。
// 作者   : FPGA 竞赛团队
// 日期   : 2026-08-31
// 版本   : v1.0
// 时钟域 : 与 fat32_file_reader / bmp_parser 相同的文件流时钟域。
//
// 接口约定：
//   start                : 新文件开始脉冲，同时用于清除上一文件状态
//   din/din_valid        : 与 bmp_parser 共享的完整 BMP 文件字节流
//   header_done          : bmp_parser.done；头部最后一个 byte 消费后脉冲
//   bmp_ok,width,height  : bmp_parser 对应输出；本 baseline 仅支持
//                          24-bit BI_RGB、正高度(bottom-up)
//   file_done/file_ok    : 上游文件流完成状态；若像素阵列尚未完整而
//                          file_done 提前到达，则本模块失败
//   pixel_*              : 每收齐 B/G/R 三字节后输出一拍 pixel_valid
//   done/ok              : 像素阵列完整/失败；保持到下一次 start
//
// 重要时序：bmp_parser 的 header_done 可能与首个 pixel byte 在同一
//           个采样沿同时可见。本模块必须在该拍直接消费首个 B byte，
//           不能丢失 BMP 的第一个像素字节。
// ================================================================

module bmp_pixel_stream (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,

    input  wire [7:0]   din,
    input  wire         din_valid,

    input  wire         header_done,
    input  wire         bmp_ok,
    input  wire [15:0]  width,
    input  wire [15:0]  height,

    input  wire         file_done,
    input  wire         file_ok,

    output reg          pixel_valid,
    output reg  [7:0]   pixel_r,
    output reg  [7:0]   pixel_g,
    output reg  [7:0]   pixel_b,
    output reg  [15:0]  pixel_x,
    output reg  [15:0]  pixel_y,

    output reg          done,
    output reg          ok
);

    localparam [2:0]
        S_IDLE        = 3'd0,
        S_WAIT_HEADER = 3'd1,
        S_PIXELS      = 3'd2,
        S_PADDING     = 3'd3,
        S_DONE        = 3'd4,
        S_ABORT       = 3'd5;

    reg [2:0] state;

    reg [15:0] width_latched;
    reg [15:0] height_latched;
    reg [15:0] cur_x;
    reg [15:0] cur_y;

    // 24-bit pixel byte phase: 0=B, 1=G, 2=R.
    reg [1:0] byte_phase;
    reg [7:0] b_hold;
    reg [7:0] g_hold;

    // BMP row padding is always 0..3 bytes.
    reg [1:0] row_padding;
    reg [1:0] padding_left;

    // width*3 fits in 18 bits for a 16-bit width.
    wire [17:0] row_bytes_calc = {2'b00, width} + ({2'b00, width} << 1);
    reg  [1:0]  padding_calc;

    // Combinational row padding = (4 - (width*3 mod 4)) mod 4.
    always @(*) begin
        case (row_bytes_calc[1:0])
            2'd0: padding_calc = 2'd0;
            2'd1: padding_calc = 2'd3;
            2'd2: padding_calc = 2'd2;
            default: padding_calc = 2'd1; // mod 4 == 3
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            width_latched  <= 16'd0;
            height_latched <= 16'd0;
            cur_x          <= 16'd0;
            cur_y          <= 16'd0;
            byte_phase     <= 2'd0;
            b_hold         <= 8'd0;
            g_hold         <= 8'd0;
            row_padding    <= 2'd0;
            padding_left   <= 2'd0;
            pixel_valid    <= 1'b0;
            pixel_r        <= 8'd0;
            pixel_g        <= 8'd0;
            pixel_b        <= 8'd0;
            pixel_x        <= 16'd0;
            pixel_y        <= 16'd0;
            done           <= 1'b0;
            ok             <= 1'b0;
        end else begin
            // pixel_valid is a one-cycle strobe.
            pixel_valid <= 1'b0;

            // start has highest priority and permits back-to-back files without reset.
            if (start) begin
                state          <= S_WAIT_HEADER;
                width_latched  <= 16'd0;
                height_latched <= 16'd0;
                cur_x          <= 16'd0;
                cur_y          <= 16'd0;
                byte_phase     <= 2'd0;
                b_hold         <= 8'd0;
                g_hold         <= 8'd0;
                row_padding    <= 2'd0;
                padding_left   <= 2'd0;
                done           <= 1'b0;
                ok             <= 1'b0;
            end else begin
                case (state)
                    S_IDLE: begin
                        done <= 1'b0;
                        ok   <= 1'b0;
                    end

                    S_WAIT_HEADER: begin
                        // Upstream file ended before a complete/valid BMP header.
                        if (file_done) begin
                            done  <= 1'b1;
                            ok    <= 1'b0;
                            state <= S_ABORT;
                        end else if (header_done) begin
                            // Architecture Contract baseline: only positive-height
                            // bottom-up BMP is accepted. Negative 32-bit height is
                            // visible as bit15=1 for all practical target sizes.
                            if (!bmp_ok || (width == 16'd0) ||
                                (height == 16'd0) || height[15]) begin
                                done  <= 1'b1;
                                ok    <= 1'b0;
                                state <= S_ABORT;
                            end else begin
                                width_latched  <= width;
                                height_latched <= height;
                                cur_x          <= 16'd0;
                                cur_y          <= height - 16'd1;
                                row_padding    <= padding_calc;
                                padding_left   <= 2'd0;
                                byte_phase     <= 2'd0;
                                state          <= S_PIXELS;

                                // Critical boundary case: bmp_parser.done can be
                                // observed on the same edge as the first pixel byte.
                                // Consume that byte immediately instead of waiting
                                // one more cycle and losing pixel[0].B.
                                if (din_valid) begin
                                    b_hold     <= din;
                                    byte_phase <= 2'd1;
                                end
                            end
                        end
                    end

                    S_PIXELS: begin
                        // file_done before all expected pixels/padding is truncation,
                        // regardless of file_ok. file_ok=0 is also an upstream error.
                        if (file_done) begin
                            done  <= 1'b1;
                            ok    <= 1'b0;
                            state <= S_ABORT;
                        end else if (din_valid) begin
                            case (byte_phase)
                                2'd0: begin
                                    b_hold     <= din;
                                    byte_phase <= 2'd1;
                                end

                                2'd1: begin
                                    g_hold     <= din;
                                    byte_phase <= 2'd2;
                                end

                                default: begin
                                    // Third byte is R. Emit display-coordinate pixel.
                                    pixel_valid <= 1'b1;
                                    pixel_r     <= din;
                                    pixel_g     <= g_hold;
                                    pixel_b     <= b_hold;
                                    pixel_x     <= cur_x;
                                    pixel_y     <= cur_y;
                                    byte_phase  <= 2'd0;

                                    if (cur_x == width_latched - 16'd1) begin
                                        cur_x <= 16'd0;

                                        if (row_padding == 2'd0) begin
                                            if (cur_y == 16'd0) begin
                                                done  <= 1'b1;
                                                ok    <= 1'b1;
                                                state <= S_DONE;
                                            end else begin
                                                cur_y <= cur_y - 16'd1;
                                            end
                                        end else begin
                                            padding_left <= row_padding;
                                            state        <= S_PADDING;
                                        end
                                    end else begin
                                        cur_x <= cur_x + 16'd1;
                                    end
                                end
                            endcase
                        end
                    end

                    S_PADDING: begin
                        if (file_done) begin
                            done  <= 1'b1;
                            ok    <= 1'b0;
                            state <= S_ABORT;
                        end else if (din_valid) begin
                            if (padding_left <= 2'd1) begin
                                padding_left <= 2'd0;
                                if (cur_y == 16'd0) begin
                                    done  <= 1'b1;
                                    ok    <= 1'b1;
                                    state <= S_DONE;
                                end else begin
                                    cur_y <= cur_y - 16'd1;
                                    state <= S_PIXELS;
                                end
                            end else begin
                                padding_left <= padding_left - 2'd1;
                            end
                        end
                    end

                    S_DONE: begin
                        done <= 1'b1;
                        ok   <= 1'b1;
                        // Ignore trailing BMP bytes, if any, until the next start.
                    end

                    S_ABORT: begin
                        done <= 1'b1;
                        ok   <= 1'b0;
                    end

                    default: begin
                        done  <= 1'b1;
                        ok    <= 1'b0;
                        state <= S_ABORT;
                    end
                endcase
            end
        end
    end

    // file_ok is intentionally only meaningful together with file_done.
    // A premature file_done is already an error; after S_DONE trailing bytes are
    // irrelevant to the decoded pixel array. Keep this wire referenced so lint
    // tools do not treat the documented interface as accidentally unused.
    wire _unused_file_ok = file_ok;

endmodule
