// ================================================================
// 模块   : frame_buffer_manager
// 功能   : P0-04 图片双帧缓冲控制/地址分配。
//           - Image A 为当前 read/front buffer，Image B 为 write/back buffer
//           - 每个物理 buffer 同步保存 width/height/stride/valid metadata
//           - 仅在 display_frame_boundary 切换 read/write buffer
//           - 新帧写完整且 writer_ok 后进入 pending_swap
//           - 写失败不破坏当前显示帧，back buffer 可重试
//           - pending frame 未显示前拒绝再次覆盖 back buffer
//           本模块不发 SDRAM request；writer/prefetcher 才是 request source。
// 作者   : FPGA 竞赛团队
// 日期   : 2026-08-31
// 版本   : v1.0  ([U] UNIT PASS, 2026-08-31)
// 时钟域 : 控制时钟域。P0 baseline 假设 writer_done 与 frame boundary 已
//           在本域同步；跨域时由 system_top/CDC 层处理。
//
// 默认地址来自 Architecture Contract v1.0：
//   Image A = 0 words
//   Image B = 307200 words (= 640*480)
// 两个 base 均为 4-word 对齐。
// ================================================================

module frame_buffer_manager #(
    parameter [20:0] IMAGE_A_BASE = 21'd0,
    parameter [20:0] IMAGE_B_BASE = 21'd307200
) (
    input  wire        clk,
    input  wire        rst_n,

    // Request to begin loading a new complete image into the back buffer.
    input  wire        load_start,
    input  wire [15:0] load_width,
    input  wire [15:0] load_height,
    input  wire [15:0] load_stride_words,
    output wire        load_ready,
    output reg         load_accept,

    // To framebuffer_writer.
    output reg         writer_start,
    output wire [20:0] write_base,
    output wire [15:0] write_width,
    output wire [15:0] write_height,
    output wire [15:0] write_stride_words,
    input  wire        writer_done,
    input  wire        writer_ok,

    // Display-domain frame boundary, already synchronized into clk if needed.
    input  wire        display_frame_boundary,

    // To line_prefetcher / display path.
    output wire [20:0] read_base,
    output wire [15:0] read_width,
    output wire [15:0] read_height,
    output wire [15:0] read_stride_words,
    output wire        read_frame_valid,

    // Status/debug.
    output reg         write_in_progress,
    output reg         pending_swap,
    output reg         swap_pulse,
    output reg         load_fail_pulse,
    output wire        read_buffer_sel,
    output wire        write_buffer_sel,
    output wire        config_error
);

    reg read_sel;
    reg write_sel;

    // Metadata belongs to the physical buffer, not to the current role.
    reg [15:0] width_a, width_b;
    reg [15:0] height_a, height_b;
    reg [15:0] stride_a, stride_b;
    reg valid_a, valid_b;

    assign read_buffer_sel  = read_sel;
    assign write_buffer_sel = write_sel;

    assign read_base  = read_sel  ? IMAGE_B_BASE : IMAGE_A_BASE;
    assign write_base = write_sel ? IMAGE_B_BASE : IMAGE_A_BASE;

    assign read_width        = read_sel  ? width_b  : width_a;
    assign read_height       = read_sel  ? height_b : height_a;
    assign read_stride_words = read_sel  ? stride_b : stride_a;
    assign read_frame_valid  = read_sel  ? valid_b  : valid_a;

    assign write_width        = write_sel ? width_b  : width_a;
    assign write_height       = write_sel ? height_b : height_a;
    assign write_stride_words = write_sel ? stride_b : stride_a;

    // The manager refuses operation if the frozen double-buffer map is invalid.
    assign config_error = (IMAGE_A_BASE == IMAGE_B_BASE) ||
                          (IMAGE_A_BASE[1:0] != 2'b00) ||
                          (IMAGE_B_BASE[1:0] != 2'b00);

    // Once a fully written frame is pending, its back buffer must not be
    // overwritten before it becomes the front buffer at a frame boundary.
    assign load_ready = !config_error && !write_in_progress && !pending_swap;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_sel          <= 1'b0; // Image A front/read
            write_sel         <= 1'b1; // Image B back/write
            width_a           <= 16'd0;
            width_b           <= 16'd0;
            height_a          <= 16'd0;
            height_b          <= 16'd0;
            stride_a          <= 16'd0;
            stride_b          <= 16'd0;
            valid_a           <= 1'b0;
            valid_b           <= 1'b0;
            write_in_progress <= 1'b0;
            pending_swap      <= 1'b0;
            writer_start      <= 1'b0;
            load_accept       <= 1'b0;
            swap_pulse        <= 1'b0;
            load_fail_pulse   <= 1'b0;
        end else begin
            // Event outputs are one-cycle pulses.
            writer_start    <= 1'b0;
            load_accept     <= 1'b0;
            swap_pulse      <= 1'b0;
            load_fail_pulse <= 1'b0;

            // A pending complete frame may become visible only at an explicit
            // display frame boundary. This branch intentionally sees the
            // *previous* pending_swap value, so writer_done and frame_boundary
            // on the same edge defer the swap to the next frame boundary.
            if (pending_swap && display_frame_boundary && !write_in_progress) begin
                read_sel     <= write_sel;
                write_sel    <= read_sel;
                pending_swap <= 1'b0;
                swap_pulse   <= 1'b1;
            end

            // Accept a new load only when the current back buffer is free.
            if (load_start && load_ready) begin
                write_in_progress <= 1'b1;
                writer_start      <= 1'b1;
                load_accept       <= 1'b1;

                // Latch source dimensions into the physical back buffer. The
                // previous contents become invalid as soon as overwrite starts.
                if (write_sel) begin
                    width_b  <= load_width;
                    height_b <= load_height;
                    stride_b <= load_stride_words;
                    valid_b  <= 1'b0;
                end else begin
                    width_a  <= load_width;
                    height_a <= load_height;
                    stride_a <= load_stride_words;
                    valid_a  <= 1'b0;
                end
            end

            // Consume writer completion only for an accepted/in-progress load.
            if (writer_done && write_in_progress) begin
                write_in_progress <= 1'b0;
                if (writer_ok) begin
                    pending_swap <= 1'b1;
                    if (write_sel)
                        valid_b <= 1'b1;
                    else
                        valid_a <= 1'b1;
                end else begin
                    pending_swap    <= 1'b0;
                    load_fail_pulse <= 1'b1;
                    if (write_sel)
                        valid_b <= 1'b0;
                    else
                        valid_a <= 1'b0;
                end
            end
        end
    end

endmodule
