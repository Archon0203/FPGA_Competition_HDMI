// ================================================================
// 模块   : line_buffer_pingpong
// 功能   : P0-05 双行乒乓缓冲。
//           - line_prefetcher 顺序填充完整 RGB888 行
//           - 两个 bank 交替承担 fill / display
//           - display 请求命中 ready 行后连续输出整行 pixel_valid
//           - 行未准备好时仍输出同宽黑行，并置 underflow，保证显示时序不断流
//           - incomplete/overflow fill 不会被标记为 ready
// 作者   : FPGA 竞赛团队
// 日期   : 2026-08-31
// 版本   : v1.0  ([U] UNIT PASS, CASE-GOLDEN+CASE0~CASE8, checks=2204)
// 时钟域 : P0 单时钟抽象接口。正式 TD 集成若读写跨域，必须在 system_top/
//           wrapper 层解决 CDC；不得直接异步采样本模块控制信号。
//
// 重要时序：read_start 在某个上升沿被接受后，从“下一个上升沿”开始
//           pixel_valid 连续保持 read_width 个周期。
// ================================================================

module line_buffer_pingpong #(
    parameter integer MAX_LINE_PIXELS = 640
) (
    input  wire        clk,
    input  wire        rst_n,

    // ---------------- Fill side: from line_prefetcher ----------------
    input  wire        fill_start,
    input  wire [15:0] fill_line_index,
    input  wire [15:0] fill_width,
    output wire        fill_ready,
    output reg         fill_accept,

    input  wire        fill_valid,
    input  wire [23:0] fill_data,
    input  wire        fill_done,
    input  wire        fill_ok,

    output reg         fill_commit_pulse,
    output reg         fill_fail_pulse,

    // ---------------- Display side ----------------
    input  wire        read_start,
    input  wire [15:0] read_line_index,
    input  wire [15:0] read_width,

    output reg         pixel_valid,
    output reg  [23:0] pixel_data,
    output reg         line_done,
    output reg         underflow_pulse,
    output reg         underflow_sticky,

    // ---------------- Status/debug ----------------
    output reg         protocol_error,
    output reg         fill_active,
    output reg         read_active,
    output wire        bank0_ready,
    output wire        bank1_ready
);

    // Deliberately no reset/clear on pixel RAM arrays.
    // Ready/ownership metadata is reset instead; unread RAM contents are never
    // exposed. This coding style preserves the opportunity for TD to infer ERAM.
    reg [23:0] bank0 [0:MAX_LINE_PIXELS-1];
    reg [23:0] bank1 [0:MAX_LINE_PIXELS-1];

    reg        ready0, ready1;
    reg [15:0] line0, line1;
    reg [15:0] width0, width1;

    reg        fill_bank;
    reg [15:0] fill_line_latched;
    reg [15:0] fill_width_latched;
    reg [15:0] fill_count;
    reg        fill_error_latched;

    reg        read_bank;
    reg        read_underflow;
    reg [15:0] read_width_latched;
    reg [15:0] read_count;

    wire read_uses_bank0 = read_active && !read_underflow && (read_bank == 1'b0);
    wire read_uses_bank1 = read_active && !read_underflow && (read_bank == 1'b1);
    wire fill_uses_bank0 = fill_active && (fill_bank == 1'b0);
    wire fill_uses_bank1 = fill_active && (fill_bank == 1'b1);

    wire free0 = !ready0 && !read_uses_bank0 && !fill_uses_bank0;
    wire free1 = !ready1 && !read_uses_bank1 && !fill_uses_bank1;

    assign fill_ready = !fill_active && (free0 || free1);
    assign bank0_ready = ready0;
    assign bank1_ready = ready1;

    wire fill_width_valid = (fill_width_latched != 16'd0) &&
                            (fill_width_latched <= MAX_LINE_PIXELS);
    wire fill_can_write = fill_active && fill_valid && fill_width_valid &&
                          (fill_count < fill_width_latched);
    wire [16:0] fill_count_after = {1'b0, fill_count} +
                                   (fill_can_write ? 17'd1 : 17'd0);
    wire fill_write_error_now = fill_active && fill_valid && !fill_can_write;
    wire fill_success_now = fill_active && fill_done && fill_ok &&
                            !fill_error_latched && !fill_write_error_now &&
                            fill_width_valid &&
                            (fill_count_after == {1'b0, fill_width_latched});

    wire read_req_width_valid = (read_width != 16'd0) &&
                                (read_width <= MAX_LINE_PIXELS);
    wire hit0 = ready0 && (line0 == read_line_index) && (width0 == read_width);
    wire hit1 = ready1 && (line1 == read_line_index) && (width1 == read_width);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ready0               <= 1'b0;
            ready1               <= 1'b0;
            line0                <= 16'd0;
            line1                <= 16'd0;
            width0               <= 16'd0;
            width1               <= 16'd0;
            fill_bank            <= 1'b0;
            fill_line_latched    <= 16'd0;
            fill_width_latched   <= 16'd0;
            fill_count           <= 16'd0;
            fill_error_latched   <= 1'b0;
            read_bank            <= 1'b0;
            read_underflow       <= 1'b0;
            read_width_latched   <= 16'd0;
            read_count           <= 16'd0;
            fill_accept          <= 1'b0;
            fill_commit_pulse    <= 1'b0;
            fill_fail_pulse      <= 1'b0;
            pixel_valid          <= 1'b0;
            pixel_data           <= 24'd0;
            line_done            <= 1'b0;
            underflow_pulse      <= 1'b0;
            underflow_sticky     <= 1'b0;
            protocol_error       <= 1'b0;
            fill_active          <= 1'b0;
            read_active          <= 1'b0;
        end else begin
            // One-cycle events/default display outputs.
            fill_accept       <= 1'b0;
            fill_commit_pulse <= 1'b0;
            fill_fail_pulse   <= 1'b0;
            pixel_valid       <= 1'b0;
            line_done         <= 1'b0;
            underflow_pulse   <= 1'b0;

            // --------------------------------------------------------
            // Fill transaction allocation.
            // --------------------------------------------------------
            if (fill_start) begin
                if (fill_ready && (fill_width != 16'd0) &&
                    (fill_width <= MAX_LINE_PIXELS)) begin
                    fill_active        <= 1'b1;
                    fill_accept        <= 1'b1;
                    fill_line_latched  <= fill_line_index;
                    fill_width_latched <= fill_width;
                    fill_count         <= 16'd0;
                    fill_error_latched <= 1'b0;
                    if (free0)
                        fill_bank <= 1'b0;
                    else
                        fill_bank <= 1'b1;
                end else begin
                    protocol_error <= 1'b1;
                    fill_fail_pulse <= 1'b1;
                end
            end

            // Fill data. The bank was guaranteed free when allocated.
            if (fill_can_write) begin
                if (fill_bank == 1'b0)
                    bank0[fill_count] <= fill_data;
                else
                    bank1[fill_count] <= fill_data;
                fill_count <= fill_count + 16'd1;
            end

            if (fill_write_error_now) begin
                fill_error_latched <= 1'b1;
                protocol_error     <= 1'b1;
            end

            // Commit/abort. Same-cycle final fill_valid + fill_done is legal.
            if (fill_done) begin
                if (!fill_active) begin
                    protocol_error  <= 1'b1;
                    fill_fail_pulse <= 1'b1;
                end else begin
                    fill_active <= 1'b0;
                    if (fill_success_now) begin
                        fill_commit_pulse <= 1'b1;
                        if (fill_bank == 1'b0) begin
                            ready0 <= 1'b1;
                            line0  <= fill_line_latched;
                            width0 <= fill_width_latched;
                            // A stale duplicate of the same line is discarded.
                            if (ready1 && (line1 == fill_line_latched))
                                ready1 <= 1'b0;
                        end else begin
                            ready1 <= 1'b1;
                            line1  <= fill_line_latched;
                            width1 <= fill_width_latched;
                            if (ready0 && (line0 == fill_line_latched))
                                ready0 <= 1'b0;
                        end
                    end else begin
                        fill_fail_pulse <= 1'b1;
                        if (fill_bank == 1'b0)
                            ready0 <= 1'b0;
                        else
                            ready1 <= 1'b0;
                    end
                end
            end

            // --------------------------------------------------------
            // Display request. A missing line produces a continuous black
            // replacement line rather than a gap in pixel_valid.
            // --------------------------------------------------------
            if (read_start) begin
                if (read_active) begin
                    protocol_error <= 1'b1;
                end else if (!read_req_width_valid) begin
                    underflow_pulse  <= 1'b1;
                    underflow_sticky <= 1'b1;
                    line_done        <= 1'b1;
                    protocol_error   <= 1'b1;
                end else begin
                    read_active        <= 1'b1;
                    read_width_latched <= read_width;
                    read_count         <= 16'd0;
                    if (hit0) begin
                        read_bank      <= 1'b0;
                        read_underflow <= 1'b0;
                        ready0         <= 1'b0; // reserve until line_done
                        if (hit1) begin
                            // Duplicate ready lines should not normally exist.
                            protocol_error <= 1'b1;
                            ready1 <= 1'b0;
                        end
                    end else if (hit1) begin
                        read_bank      <= 1'b1;
                        read_underflow <= 1'b0;
                        ready1         <= 1'b0;
                    end else begin
                        read_bank         <= 1'b0;
                        read_underflow    <= 1'b1;
                        underflow_pulse   <= 1'b1;
                        underflow_sticky  <= 1'b1;
                    end
                end
            end

            // The first pixel is emitted one cycle after read_start, then
            // pixel_valid remains asserted on every cycle until line_done.
            if (read_active) begin
                pixel_valid <= 1'b1;
                if (read_underflow)
                    pixel_data <= 24'h000000;
                else if (read_bank == 1'b0)
                    pixel_data <= bank0[read_count];
                else
                    pixel_data <= bank1[read_count];

                if (read_count + 16'd1 >= read_width_latched) begin
                    read_active <= 1'b0;
                    line_done   <= 1'b1;
                    read_count  <= 16'd0;
                end else begin
                    read_count <= read_count + 16'd1;
                end
            end
        end
    end

endmodule
