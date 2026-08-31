// ================================================================
// 模块   : framebuffer_writer
// 功能   : P0-03 RGB888 像素流 -> 32-bit framebuffer 写请求源。
//           - 输入 display-coordinate pixel_x/pixel_y + RGB888
//           - 生成 21-bit SDRAM word address
//           - 统一写数据格式 0x00RRGGBB
//           - 内置小型像素 FIFO，吸收短时 memory backpressure
//           - 等待全部 pending write 被下游接受后再报告 frame done
//           - 检测非法坐标、FIFO overflow、上游失败和配置错误
//           本模块不做 buffer swap，不直接例化 APUG011。
// 作者   : FPGA 竞赛团队
// 日期   : 2026-08-31
// 版本   : v1.0  ([U] UNIT PASS, 2026-08-31)
// 时钟域 : framebuffer/write request 时钟域；P0 mock 链阶段与像素流同域。
//
// 体系结构约束：
//   - SDRAM word 格式固定为 0x00RRGGBB。
//   - 地址单位为 32-bit word，物理范围 0 .. 2^21-1。
//   - frame_base 必须 4-word 对齐。
//   - framebuffer_writer 只产生 write request；真正的 read/write 互斥由
//     sdram_arbiter 负责，APUG011 适配由 sdram_adapter 负责。
//
// 流控说明：
//   bmp_pixel_stream 当前输出 valid-only 像素流，不能被本模块反压。
//   因此这里用 PIXEL_FIFO_DEPTH 个 entry 吸收短 stall，并输出 pixel_ready
//   作为诊断/后续链路扩展信号。若 pixel_valid 到来时 FIFO 已无空间，
//   overflow 置位且本帧最终 ok=0；不会静默覆盖旧数据。
// ================================================================

module framebuffer_writer #(
    parameter integer PIXEL_FIFO_DEPTH = 8
) (
    input  wire         clk,
    input  wire         rst_n,

    // New-frame configuration. start is accepted only while busy=0.
    input  wire         start,
    input  wire [20:0]  frame_base,
    input  wire [15:0]  frame_width,
    input  wire [15:0]  frame_height,
    input  wire [15:0]  frame_stride_words,

    // Pixel stream from bmp_pixel_stream / future media source.
    input  wire         pixel_valid,
    input  wire [7:0]   pixel_r,
    input  wire [7:0]   pixel_g,
    input  wire [7:0]   pixel_b,
    input  wire [15:0]  pixel_x,
    input  wire [15:0]  pixel_y,
    output wire         pixel_ready,

    // Source-frame completion. source_done may arrive while writes are pending.
    input  wire         source_done,
    input  wire         source_ok,

    // Abstract write request toward sdram_arbiter/mock SDRAM.
    output wire         mem_wr_valid,
    output wire [20:0]  mem_wr_addr,
    output wire [31:0]  mem_wr_data,
    input  wire         mem_wr_ready,

    // Status. done is a one-cycle pulse; ok is valid with done and retained
    // until the next accepted start for debug visibility.
    output reg          busy,
    output reg          done,
    output reg          ok,
    output reg          overflow
);

    function integer clog2;
        input integer value;
        integer v;
        begin
            v = value - 1;
            clog2 = 0;
            while (v > 0) begin
                v = v >> 1;
                clog2 = clog2 + 1;
            end
            if (clog2 < 1)
                clog2 = 1;
        end
    endfunction

    localparam integer PTR_W = clog2(PIXEL_FIFO_DEPTH);
    localparam integer CNT_W = clog2(PIXEL_FIFO_DEPTH + 1);

    function [31:0] mul16x16;
        input [15:0] a;
        input [15:0] b;
        begin
            // Explicit zero-extension avoids accidental 16-bit expression
            // truncation under older Verilog expression-sizing rules.
            mul16x16 = {16'd0, a} * {16'd0, b};
        end
    endfunction

    reg [20:0] fifo_addr [0:PIXEL_FIFO_DEPTH-1];
    reg [31:0] fifo_data [0:PIXEL_FIFO_DEPTH-1];
    reg [PTR_W-1:0] wr_ptr;
    reg [PTR_W-1:0] rd_ptr;
    reg [CNT_W-1:0] fifo_count;

    reg [20:0] frame_base_latched;
    reg [15:0] frame_width_latched;
    reg [15:0] frame_height_latched;
    reg [15:0] frame_stride_latched;
    reg [31:0] expected_pixels;
    reg [31:0] accepted_pixels;

    reg        source_done_seen;
    reg        source_ok_latched;
    reg        error_latched;

    wire fifo_nonempty = (fifo_count != {CNT_W{1'b0}});
    wire pop = fifo_nonempty && mem_wr_ready;
    wire fifo_has_space = (fifo_count < PIXEL_FIFO_DEPTH) || pop;

    assign mem_wr_valid = fifo_nonempty;
    assign mem_wr_addr  = fifo_addr[rd_ptr];
    assign mem_wr_data  = fifo_data[rd_ptr];

    assign pixel_ready = busy && !source_done_seen && fifo_has_space;

    wire coord_valid = (pixel_x < frame_width_latched) &&
                       (pixel_y < frame_height_latched);

    // Address is in 32-bit words. The multiplication is intentionally isolated
    // here; TD resource reports decide later whether it must be strength-reduced.
    wire [31:0] row_offset_calc = mul16x16(pixel_y, frame_stride_latched);
    wire [32:0] addr_full_calc  = {12'd0, frame_base_latched}
                                + {1'b0, row_offset_calc}
                                + {17'd0, pixel_x};
    wire        addr_overflow   = |addr_full_calc[32:21];
    wire [20:0] addr_word_calc  = addr_full_calc[20:0];
    wire [31:0] data_word_calc  = {8'h00, pixel_r, pixel_g, pixel_b};

    wire push = pixel_valid && pixel_ready && coord_valid && !addr_overflow;

    wire config_valid = (PIXEL_FIFO_DEPTH >= 2) &&
                        (frame_width != 16'd0) &&
                        (frame_height != 16'd0) &&
                        (frame_stride_words >= frame_width) &&
                        (frame_stride_words != 16'd0) &&
                        (frame_base[1:0] == 2'b00);

    wire [31:0] expected_pixels_calc = mul16x16(frame_width, frame_height);

    // Pointer increment supports any constant depth >=2, not only powers of two.
    function [PTR_W-1:0] ptr_next;
        input [PTR_W-1:0] ptr;
        begin
            if (ptr == PIXEL_FIFO_DEPTH - 1)
                ptr_next = {PTR_W{1'b0}};
            else
                ptr_next = ptr + {{(PTR_W-1){1'b0}}, 1'b1};
        end
    endfunction

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy                <= 1'b0;
            done                <= 1'b0;
            ok                  <= 1'b0;
            overflow            <= 1'b0;
            wr_ptr              <= {PTR_W{1'b0}};
            rd_ptr              <= {PTR_W{1'b0}};
            fifo_count          <= {CNT_W{1'b0}};
            frame_base_latched  <= 21'd0;
            frame_width_latched <= 16'd0;
            frame_height_latched<= 16'd0;
            frame_stride_latched<= 16'd0;
            expected_pixels     <= 32'd0;
            accepted_pixels     <= 32'd0;
            source_done_seen    <= 1'b0;
            source_ok_latched   <= 1'b0;
            error_latched       <= 1'b0;
            for (i = 0; i < PIXEL_FIFO_DEPTH; i = i + 1) begin
                fifo_addr[i] <= 21'd0;
                fifo_data[i] <= 32'd0;
            end
        end else begin
            // Completion is an event pulse.
            done <= 1'b0;

            // New transaction: only legal when idle.
            if (start && !busy) begin
                wr_ptr               <= {PTR_W{1'b0}};
                rd_ptr               <= {PTR_W{1'b0}};
                fifo_count           <= {CNT_W{1'b0}};
                accepted_pixels      <= 32'd0;
                source_done_seen     <= 1'b0;
                source_ok_latched    <= 1'b0;
                error_latched        <= 1'b0;
                overflow             <= 1'b0;
                ok                   <= 1'b0;

                frame_base_latched   <= frame_base;
                frame_width_latched  <= frame_width;
                frame_height_latched <= frame_height;
                frame_stride_latched <= frame_stride_words;
                expected_pixels      <= expected_pixels_calc;

                if (config_valid) begin
                    busy <= 1'b1;
                end else begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    ok   <= 1'b0;
                end
            end else if (busy) begin
                // A second start while active is a protocol error; never discard
                // pending writes by resetting the transaction underneath them.
                if (start)
                    error_latched <= 1'b1;

                // Consume current FIFO head whenever downstream accepts it.
                if (pop)
                    rd_ptr <= ptr_next(rd_ptr);

                // Validate each pixel independently. Invalid pixels are not
                // enqueued, but make the entire frame fail at completion.
                if (pixel_valid) begin
                    if (source_done_seen) begin
                        error_latched <= 1'b1;
                    end else if (!fifo_has_space) begin
                        overflow      <= 1'b1;
                        error_latched <= 1'b1;
                    end else if (!coord_valid || addr_overflow) begin
                        error_latched <= 1'b1;
                    end
                end

                if (push) begin
                    fifo_addr[wr_ptr] <= addr_word_calc;
                    fifo_data[wr_ptr] <= data_word_calc;
                    wr_ptr            <= ptr_next(wr_ptr);
                    accepted_pixels   <= accepted_pixels + 32'd1;
                end

                case ({push, pop})
                    2'b10: fifo_count <= fifo_count + {{(CNT_W-1){1'b0}}, 1'b1};
                    2'b01: fifo_count <= fifo_count - {{(CNT_W-1){1'b0}}, 1'b1};
                    default: fifo_count <= fifo_count;
                endcase

                if (source_done && !source_done_seen) begin
                    source_done_seen  <= 1'b1;
                    source_ok_latched <= source_ok;
                    if (!source_ok)
                        error_latched <= 1'b1;
                end

                // Wait until source completion has been seen and every accepted
                // write request has drained. Block completion if a late pixel is
                // present on this cycle so a protocol error cannot be missed.
                if (source_done_seen && !fifo_nonempty && !pixel_valid) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    ok   <= source_ok_latched && !error_latched &&
                            (accepted_pixels == expected_pixels);
                end
            end
        end
    end

endmodule
