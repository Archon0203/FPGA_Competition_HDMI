// ================================================================
// 模块   : vseq_yuv_unpack
// 功能   : 把 vseq_reader 输出的字节流解包为逐像素 YUV444。
//           针对 YUV444 的 .vseq：每 3 个 body 字节为一像素
//           Y,Cb,Cr。frame_start 用于在每帧首字节强制对齐相位。
//           该模块只做字节分组，不改变颜色空间。
// 作者   : FPGA 竞赛团队
// 日期   : 2026-08-28
// 版本   : v1.0
// 端口说明:
//   - clk / rst_n(低有效) : 像素/读取时钟与复位
//   - byte_valid/byte_data : vseq_reader.body 的字节流
//   - frame_start          : vseq_reader.frame_start(可选对齐)
//   - pix_valid            : 一个完整 YUV444 像素输出有效
//   - y/cb/cr[7:0]         : 解包后的像素
// 时钟域: clk 为像素时钟域(clk_pix)，上游 vseq_reader 已按此域消费。
// 修改历史:
//   2026-08-28 v1.0 初版, 用于修正 planar .vseq 与显示链的接口断层。
// ================================================================

module vseq_yuv_unpack #(
    parameter DW = 8
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        byte_valid,
    input  wire [DW-1:0] byte_data,
    input  wire        frame_start,
    output reg         pix_valid,
    output reg  [DW-1:0] y,
    output reg  [DW-1:0] cb,
    output reg  [DW-1:0] cr
);

    reg [1:0] phase;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase     <= 2'd0;
            pix_valid <= 1'b0;
            y <= {DW{1'b0}}; cb <= {DW{1'b0}}; cr <= {DW{1'b0}};
        end else begin
            pix_valid <= 1'b0;
            if (byte_valid) begin
                if (frame_start) phase <= 2'd0;
                case (phase)
                    2'd0: begin
                        y     <= byte_data;
                        phase <= 2'd1;
                    end
                    2'd1: begin
                        cb    <= byte_data;
                        phase <= 2'd2;
                    end
                    default: begin
                        cr        <= byte_data;
                        pix_valid <= 1'b1;
                        phase     <= 2'd0;
                    end
                endcase
            end
        end
    end

endmodule
