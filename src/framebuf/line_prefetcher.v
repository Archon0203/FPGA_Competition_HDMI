// ================================================================
// 模块   : line_prefetcher
// 功能   : P0-06 framebuffer 行预取 request source。
//           - 根据 frame_base / stride / line_index 生成连续 word read
//           - 最多允许 MAX_OUTSTANDING 个有序 outstanding read
//           - 接收 0x00RRGGBB，向 line_buffer_pingpong 输出 RGB888
//           - 在 line buffer 成功分配 bank 后才发 memory request
//           - memory/line-buffer 长时间无进展时 timeout，失败释放 fill bank
// 作者   : FPGA 竞赛团队
// 日期   : 2026-08-31
// 版本   : v1.0  ([U] UNIT PASS, CASE0~CASE13, checks=2713)
// 时钟域 : P0 抽象 memory/request 时钟域。P1 接 APUG011 时由
//           sdram_arbiter/sdram_adapter 与 CDC 设计决定最终时钟归属。
//           本模块不直接例化 vendor primitive。
// ================================================================

module line_prefetcher #(
    parameter integer MAX_OUTSTANDING = 8,
    parameter integer STALL_TIMEOUT_CYCLES = 4096
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        start,
    input  wire [20:0] frame_base,
    input  wire [15:0] frame_width,
    input  wire [15:0] frame_height,
    input  wire [15:0] frame_stride_words,
    input  wire [15:0] line_index,

    // Abstract ordered memory-read request/response interface.
    output wire        mem_rd_valid,
    output wire [20:0] mem_rd_addr,
    input  wire        mem_rd_ready,
    input  wire        mem_rvalid,
    input  wire [31:0] mem_rdata,

    // Fill interface to line_buffer_pingpong.
    input  wire        lb_fill_ready,
    output reg         lb_fill_start,
    output reg  [15:0] lb_fill_line_index,
    output reg  [15:0] lb_fill_width,
    output wire        lb_fill_valid,
    output wire [23:0] lb_fill_data,
    output reg         lb_fill_done,
    output reg         lb_fill_ok,

    output reg         busy,
    output reg         done,
    output reg         ok,
    output reg         timeout_error,
    output reg         protocol_error,
    // Sticky safety flag: if a failed transaction still has accepted reads
    // outstanding, late responses could alias into a later line. Reset is required.
    output reg         recovery_required,
    output reg  [15:0] issued_count_debug,
    output reg  [15:0] received_count_debug
);

    localparam [2:0] S_IDLE        = 3'd0;
    localparam [2:0] S_WAIT_BUFFER = 3'd1;
    localparam [2:0] S_FETCH       = 3'd2;
    localparam [2:0] S_COMMIT_OK   = 3'd3;
    localparam [2:0] S_COMMIT_FAIL = 3'd4;
    localparam [2:0] S_DONE_OK     = 3'd5;
    localparam [2:0] S_DONE_FAIL   = 3'd6;

    reg [2:0] state;

    reg [20:0] line_base_latched;
    reg [15:0] width_latched;
    reg [15:0] line_latched;

    reg [15:0] issued_count;
    reg [15:0] received_count;
    reg [15:0] outstanding_count;
    reg [31:0] stall_count;
    reg        transaction_error;

    wire [47:0] line_offset_wide = line_index * frame_stride_words;
    wire [47:0] line_base_wide = {27'd0, frame_base} + line_offset_wide;
    wire [47:0] last_addr_wide = line_base_wide + frame_width - 16'd1;

    wire config_valid = (frame_width != 16'd0) &&
                        (frame_height != 16'd0) &&
                        (line_index < frame_height) &&
                        (frame_stride_words >= frame_width) &&
                        (frame_base[1:0] == 2'b00) &&
                        (line_base_wide < 48'd2097152) &&
                        (last_addr_wide < 48'd2097152) &&
                        (MAX_OUTSTANDING > 0) &&
                        (STALL_TIMEOUT_CYCLES > 0);

    wire issue_credit = (outstanding_count < MAX_OUTSTANDING);
    assign mem_rd_valid = (state == S_FETCH) &&
                          (issued_count < width_latched) &&
                          issue_credit && !transaction_error;
    assign mem_rd_addr = line_base_latched + issued_count;

    wire req_accept = mem_rd_valid && mem_rd_ready;
    wire response_legal = (state == S_FETCH) && mem_rvalid &&
                          ((outstanding_count != 16'd0) || req_accept) &&
                          (received_count < width_latched) &&
                          !transaction_error;
    wire response_illegal = mem_rvalid && !response_legal && (state == S_FETCH);

    assign lb_fill_valid = response_legal;
    assign lb_fill_data  = mem_rdata[23:0];

    wire [16:0] issued_next = {1'b0, issued_count} + (req_accept ? 17'd1 : 17'd0);
    wire [16:0] received_next = {1'b0, received_count} + (response_legal ? 17'd1 : 17'd0);
    wire [16:0] outstanding_next = {1'b0, outstanding_count}
                                 + (req_accept ? 17'd1 : 17'd0)
                                 - (response_legal ? 17'd1 : 17'd0);

    wire fetch_complete_now = (issued_next == {1'b0, width_latched}) &&
                              (received_next == {1'b0, width_latched}) &&
                              (outstanding_next == 17'd0) &&
                              !response_illegal && !transaction_error;

    wire any_progress = req_accept || response_legal ||
                        ((state == S_WAIT_BUFFER) && lb_fill_ready);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                <= S_IDLE;
            line_base_latched    <= 21'd0;
            width_latched        <= 16'd0;
            line_latched         <= 16'd0;
            issued_count         <= 16'd0;
            received_count       <= 16'd0;
            outstanding_count    <= 16'd0;
            stall_count          <= 32'd0;
            transaction_error    <= 1'b0;
            lb_fill_start        <= 1'b0;
            lb_fill_line_index   <= 16'd0;
            lb_fill_width        <= 16'd0;
            lb_fill_done         <= 1'b0;
            lb_fill_ok           <= 1'b0;
            busy                 <= 1'b0;
            done                 <= 1'b0;
            ok                   <= 1'b0;
            timeout_error        <= 1'b0;
            protocol_error       <= 1'b0;
            recovery_required    <= 1'b0;
            issued_count_debug   <= 16'd0;
            received_count_debug <= 16'd0;
        end else begin
            lb_fill_start <= 1'b0;
            lb_fill_done  <= 1'b0;
            done          <= 1'b0;

            issued_count_debug   <= issued_count;
            received_count_debug <= received_count;

            // A second start while active is an explicit protocol failure.
            if (start && (state != S_IDLE)) begin
                protocol_error    <= 1'b1;
                transaction_error <= 1'b1;
            end

            case (state)
                S_IDLE: begin
                    busy              <= 1'b0;
                    stall_count       <= 32'd0;
                    transaction_error <= 1'b0;
                    if (start) begin
                        ok                   <= 1'b0;
                        issued_count         <= 16'd0;
                        received_count       <= 16'd0;
                        outstanding_count    <= 16'd0;
                        issued_count_debug   <= 16'd0;
                        received_count_debug <= 16'd0;
                        if (recovery_required) begin
                            // Accepted reads from an aborted transaction may still return.
                            // Without tags/flush semantics it is unsafe to treat them as a new line.
                            protocol_error <= 1'b1;
                            busy           <= 1'b1;
                            state          <= S_DONE_FAIL;
                        end else begin
                            timeout_error  <= 1'b0;
                            protocol_error <= 1'b0;
                            if (config_valid) begin
                                line_base_latched  <= line_base_wide[20:0];
                                width_latched      <= frame_width;
                                line_latched       <= line_index;
                                lb_fill_line_index <= line_index;
                                lb_fill_width      <= frame_width;
                                busy               <= 1'b1;
                                state              <= S_WAIT_BUFFER;
                            end else begin
                                protocol_error <= 1'b1;
                                busy           <= 1'b1;
                                state          <= S_DONE_FAIL;
                            end
                        end
                    end
                end

                S_WAIT_BUFFER: begin
                    if (lb_fill_ready) begin
                        lb_fill_start <= 1'b1;
                        stall_count   <= 32'd0;
                        state         <= S_FETCH;
                    end else if (stall_count >= STALL_TIMEOUT_CYCLES-1) begin
                        timeout_error <= 1'b1;
                        state         <= S_DONE_FAIL; // no bank allocated yet
                    end else begin
                        stall_count <= stall_count + 32'd1;
                    end
                end

                S_FETCH: begin
                    // Counter updates support request+response on the same cycle.
                    if (req_accept)
                        issued_count <= issued_count + 16'd1;
                    if (response_legal)
                        received_count <= received_count + 16'd1;

                    case ({req_accept, response_legal})
                        2'b10: outstanding_count <= outstanding_count + 16'd1;
                        2'b01: outstanding_count <= outstanding_count - 16'd1;
                        default: outstanding_count <= outstanding_count;
                    endcase

                    if (response_illegal) begin
                        protocol_error    <= 1'b1;
                        transaction_error <= 1'b1;
                        state             <= S_COMMIT_FAIL;
                    end else if (transaction_error) begin
                        state <= S_COMMIT_FAIL;
                    end else if (fetch_complete_now) begin
                        stall_count <= 32'd0;
                        state       <= S_COMMIT_OK;
                    end else if (any_progress) begin
                        stall_count <= 32'd0;
                    end else if (stall_count >= STALL_TIMEOUT_CYCLES-1) begin
                        timeout_error <= 1'b1;
                        state         <= S_COMMIT_FAIL;
                    end else begin
                        stall_count <= stall_count + 32'd1;
                    end
                end

                S_COMMIT_OK: begin
                    lb_fill_done <= 1'b1;
                    lb_fill_ok   <= 1'b1;
                    state        <= S_DONE_OK;
                end

                S_COMMIT_FAIL: begin
                    // A bank was allocated in S_WAIT_BUFFER, so always release it.
                    lb_fill_done <= 1'b1;
                    lb_fill_ok   <= 1'b0;
                    // Accepted reads cannot be cancelled by this abstract interface.
                    // If any remain in flight, quarantine this path until reset.
                    if (outstanding_count != 16'd0)
                        recovery_required <= 1'b1;
                    state <= S_DONE_FAIL;
                end

                S_DONE_OK: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    ok   <= 1'b1;
                    state <= S_IDLE;
                end

                S_DONE_FAIL: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    ok   <= 1'b0;
                    state <= S_IDLE;
                end

                default: begin
                    protocol_error <= 1'b1;
                    busy           <= 1'b1;
                    state          <= S_COMMIT_FAIL;
                end
            endcase
        end
    end

endmodule
