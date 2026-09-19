// ================================================================
// 模块   : sdram_adapter
// 功能   : P1-01 P0 抽象 memory 接口 -> APUG011 application-side 接口。
//           - 保持 P0 的单 word 21-bit/32-bit read/write 契约
//           - APUG011 不允许读写同时进行，按 4-word(128-bit) 地址组访问
//           - 任意单 word 写：转换为 4-word 对齐组，目标 word 正常写，
//             其余 3 word 使用 App_wr_dm=4'b1111 完全屏蔽
//           - 任意单 word 读：转换为 4-word 对齐组，仅把目标 lane 的
//             Sdr_rd_en/Sdr_rd_dout 返回给 P0，其余 3 个响应丢弃
//           - init/refresh/busy 期间暂停 APUG011 command，不丢失当前组
//           - 读优先；当前 4-word 组完成后才允许切换读/写方向
// 作者   : FPGA 竞赛团队
// 日期   : 2026-09-01
// 版本   : v0.4  (150 MHz timing cleanup candidate-2；v0.3 historical regressions PASS，v0.4 待回归)
// 时钟域 : 与 APUG011 Sdr_clk 相同。跨域由后续 system_top/CDC 层处理。
//
// APUG011 v1.2 依据：
//   * 21-bit word address / 32-bit data / 4-bit byte mask
//   * 读写互斥
//   * 读请求约 10 个 Sdr_clk 后由 Sdr_rd_en 标记有效返回
//   * 地址跳跃以 4 words 为粒度；每组首地址 [1:0]==2'b00
//   * 操作前等待 Sdr_init_done，刷新/忙时暂停读写
//
// 注意：
//   1) App_ref_req 固定为 0，正式例化使用 APUG011 默认 self refresh。
//   2) mem_*_ready 只在目标 lane 的 APUG011 command 实际发出时拉高；
//      因此 framebuffer_writer 不会因为 adapter 内部预缓存而提前完成。
//   3) APUG011 官方 app_wrrd 在读周期把 App_wr_dm 保持 4'b0000；
//      外部 IS42 模型也会把 DQM 用作读数据屏蔽。因此只有 ST_WRITE
//      padding lane 才输出 4'b1111；ST_READ/IDLE 始终输出 4'b0000。
//   4) 本模块不例化 sdr_as_ram/EG primitive；只做 application-side adapter。
// ================================================================

module sdram_adapter #(
    parameter integer RESP_TAG_FIFO_DEPTH = 32
) (
    input  wire         clk,
    input  wire         rst_n,

    // ---------------- P0 abstract memory side ----------------
    input  wire         mem_wr_valid,
    input  wire [20:0]  mem_wr_addr,
    input  wire [31:0]  mem_wr_data,
    output wire         mem_wr_ready,

    input  wire         mem_rd_valid,
    input  wire [20:0]  mem_rd_addr,
    output wire         mem_rd_ready,
    output wire         mem_rvalid,
    output wire [31:0]  mem_rdata,

    // ---------------- APUG011 application side ----------------
    output wire         App_wr_en,
    output wire [20:0]  App_wr_addr,
    output wire [31:0]  App_wr_din,
    output wire [3:0]   App_wr_dm,

    output wire         App_rd_en,
    output wire [20:0]  App_rd_addr,
    input  wire         Sdr_rd_en,
    input  wire [31:0]  Sdr_rd_dout,

    input  wire         Sdr_init_done,
    input  wire         Sdr_init_ref_vld,
    input  wire         Sdr_busy,
    output wire         App_ref_req,

    // ---------------- Status / debug ----------------
    output wire         ready_for_traffic,
    output reg          protocol_error,
    output reg          provider_fault,
    output reg          contention_seen,
    output reg  [15:0]  read_outstanding_debug,
    output reg  [31:0]  read_accept_count_debug,
    output reg  [31:0]  write_accept_count_debug,
    output reg  [31:0]  app_read_word_count_debug,
    output reg  [31:0]  app_write_word_count_debug
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

    localparam integer TAG_PTR_W = clog2(RESP_TAG_FIFO_DEPTH);
    localparam integer TAG_CNT_W = clog2(RESP_TAG_FIFO_DEPTH + 1);

    localparam [1:0] ST_IDLE  = 2'd0;
    localparam [1:0] ST_READ  = 2'd1;
    localparam [1:0] ST_WRITE = 2'd2;

    reg [1:0] state;
    reg [1:0] group_lane;

    reg [20:0] current_addr;
    reg [20:0] current_group_base;
    reg [1:0]  current_target_lane;
    reg [31:0] current_write_data;
    reg        target_accepted;

    // One tag is pushed for every APUG011 read word. Exactly one tag in every
    // 4-word micro-group is '1', identifying the P0 word that must be returned.
    reg tag_fifo [0:RESP_TAG_FIFO_DEPTH-1];
    reg [TAG_PTR_W-1:0] tag_wr_ptr;
    reg [TAG_PTR_W-1:0] tag_rd_ptr;
    reg [TAG_CNT_W-1:0] tag_count;

    reg init_seen;

    wire provider_available = Sdr_init_done && !Sdr_init_ref_vld && !Sdr_busy;
    assign ready_for_traffic = Sdr_init_done && !provider_fault;
    assign App_ref_req = 1'b0;

    wire source_read_matches = mem_rd_valid && (mem_rd_addr == current_addr);
    wire source_write_matches = mem_wr_valid &&
                                (mem_wr_addr == current_addr) &&
                                (mem_wr_data == current_write_data);

    wire tag_space = (tag_count < RESP_TAG_FIFO_DEPTH);

    // Before the target request is accepted, valid/address/data must remain
    // stable per the normal valid/ready contract. After acceptance, the source
    // may advance while the adapter finishes masked/discard padding lanes.
    wire read_source_ok = target_accepted || source_read_matches;
    wire write_source_ok = target_accepted || source_write_matches;

    wire issue_read = (state == ST_READ) && provider_available && tag_space &&
                      read_source_ok;
    wire issue_write = (state == ST_WRITE) && provider_available &&
                       write_source_ok;

    wire read_target_lane = (group_lane == current_target_lane);
    wire write_target_lane = (group_lane == current_target_lane);

    assign App_rd_en   = issue_read;
    assign App_rd_addr = current_group_base + {19'd0, group_lane};

    assign App_wr_en   = issue_write;
    assign App_wr_addr = current_group_base + {19'd0, group_lane};
    assign App_wr_din  = write_target_lane ? current_write_data : 32'd0;

    // APUG011 labels App_wr_dm as a write mask, but the official reference
    // application keeps it at 4'b0000 outside masked writes.  The bundled
    // IS42 SDRAM model applies DQM to read output as well; leaving 4'b1111
    // on read padding lanes therefore tri-states DQ and produces all-Z data.
    // Only masked WRITE padding lanes may drive 4'b1111.  During READ/IDLE
    // keep the mask open so the provider can return data normally.
    assign App_wr_dm   = (state == ST_WRITE)
                       ? (write_target_lane ? 4'b0000 : 4'b1111)
                       : 4'b0000;

    // ready means the abstract request's actual target word has just been
    // presented to APUG011. Padding lanes never consume an upstream request.
    assign mem_rd_ready = issue_read && read_target_lane && !target_accepted;
    assign mem_wr_ready = issue_write && write_target_lane && !target_accepted;

    wire rd_accept = mem_rd_valid && mem_rd_ready;
    wire wr_accept = mem_wr_valid && mem_wr_ready;

    wire tag_head = tag_fifo[tag_rd_ptr];
    wire response_legal = Sdr_rd_en && (tag_count != {TAG_CNT_W{1'b0}});
    wire response_target = response_legal && tag_head;

    assign mem_rvalid = response_target;
    assign mem_rdata  = Sdr_rd_dout;

    wire tag_push = issue_read;
    wire tag_pop  = response_legal;
    wire tag_value_this_issue = read_target_lane;

    function [TAG_PTR_W-1:0] tag_ptr_next;
        input [TAG_PTR_W-1:0] ptr;
        begin
            if (ptr == RESP_TAG_FIFO_DEPTH - 1)
                tag_ptr_next = {TAG_PTR_W{1'b0}};
            else
                tag_ptr_next = ptr + {{(TAG_PTR_W-1){1'b0}}, 1'b1};
        end
    endfunction

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                         <= ST_IDLE;
            group_lane                    <= 2'd0;
            current_addr                  <= 21'd0;
            current_group_base            <= 21'd0;
            current_target_lane           <= 2'd0;
            current_write_data            <= 32'd0;
            target_accepted               <= 1'b0;
            tag_wr_ptr                    <= {TAG_PTR_W{1'b0}};
            tag_rd_ptr                    <= {TAG_PTR_W{1'b0}};
            tag_count                     <= {TAG_CNT_W{1'b0}};
            init_seen                     <= 1'b0;
            protocol_error                <= 1'b0;
            provider_fault                <= 1'b0;
            contention_seen               <= 1'b0;
            read_outstanding_debug        <= 16'd0;
            read_accept_count_debug       <= 32'd0;
            write_accept_count_debug      <= 32'd0;
            app_read_word_count_debug     <= 32'd0;
            app_write_word_count_debug    <= 32'd0;
            for (i = 0; i < RESP_TAG_FIFO_DEPTH; i = i + 1)
                tag_fifo[i] <= 1'b0;
        end else begin
            if (Sdr_init_done)
                init_seen <= 1'b1;
            if (init_seen && !Sdr_init_done)
                provider_fault <= 1'b1;

            if (mem_rd_valid && mem_wr_valid)
                contention_seen <= 1'b1;

            if (rd_accept)
                read_accept_count_debug <= read_accept_count_debug + 32'd1;
            if (wr_accept)
                write_accept_count_debug <= write_accept_count_debug + 32'd1;
            if (issue_read)
                app_read_word_count_debug <= app_read_word_count_debug + 32'd1;
            if (issue_write)
                app_write_word_count_debug <= app_write_word_count_debug + 32'd1;

            // APUG011 must never see read and write enables together.
            if (App_rd_en && App_wr_en)
                protocol_error <= 1'b1;

            // An APUG011 response without a corresponding issued read word is
            // a provider/protocol violation; do not forward it into P0.
            if (Sdr_rd_en && !response_legal)
                protocol_error <= 1'b1;

            // Each forwarded P0 response must correspond to an accepted P0 read.
            if (response_target && (read_outstanding_debug == 16'd0) && !rd_accept)
                protocol_error <= 1'b1;

            // read_outstanding_debug only tracks accepted P0 target words,
            // not the four APUG011 micro-group words.  The previous v0.3
            // implementation formed a 17-bit add/subtract result every cycle
            // and then inspected the carry/borrow bit.  After the BIST
            // request-slice/arbiter cleanup reduced the TD5.6.2 setup failures
            // from nine endpoints to three, this remaining project-owned
            // arithmetic is the next low-risk cone to remove.
            //
            // Underflow is already detected explicitly above.  Overflow is
            // structurally impossible here: APUG011 reads are serialized into
            // 4-word groups and the response-tag FIFO bounds in-flight read
            // words well below 16'hffff.  Use the equivalent 2-event state
            // update so the counter input depends only on a single increment
            // or decrement path.
            case ({rd_accept, response_target})
                2'b10: read_outstanding_debug <= read_outstanding_debug + 16'd1;
                2'b01: begin
                    if (read_outstanding_debug != 16'd0)
                        read_outstanding_debug <= read_outstanding_debug - 16'd1;
                end
                default: read_outstanding_debug <= read_outstanding_debug;
            endcase

            // Tag FIFO push/pop. Official APUG011 has non-zero latency, so a
            // response while the FIFO is empty is intentionally treated as bad.
            if (tag_push) begin
                tag_fifo[tag_wr_ptr] <= tag_value_this_issue;
                tag_wr_ptr <= tag_ptr_next(tag_wr_ptr);
            end
            if (tag_pop)
                tag_rd_ptr <= tag_ptr_next(tag_rd_ptr);

            case ({tag_push, tag_pop})
                2'b10: tag_count <= tag_count + {{(TAG_CNT_W-1){1'b0}}, 1'b1};
                2'b01: tag_count <= tag_count - {{(TAG_CNT_W-1){1'b0}}, 1'b1};
                default: tag_count <= tag_count;
            endcase

            case (state)
                ST_IDLE: begin
                    group_lane      <= 2'd0;
                    target_accepted <= 1'b0;

                    // Only begin a micro-group when APUG011 is currently able
                    // to accept commands. Reads have strict priority.
                    if (provider_available && mem_rd_valid) begin
                        current_addr        <= mem_rd_addr;
                        current_group_base  <= {mem_rd_addr[20:2], 2'b00};
                        current_target_lane <= mem_rd_addr[1:0];
                        state               <= ST_READ;
                    end else if (provider_available && mem_wr_valid) begin
                        current_addr        <= mem_wr_addr;
                        current_group_base  <= {mem_wr_addr[20:2], 2'b00};
                        current_target_lane <= mem_wr_addr[1:0];
                        current_write_data  <= mem_wr_data;
                        state               <= ST_WRITE;
                    end
                end

                ST_READ: begin
                    // If the source violates valid/ready stability before its
                    // target command was accepted, abort this unaccepted group.
                    if (!target_accepted && !source_read_matches) begin
                        protocol_error  <= 1'b1;
                        state           <= ST_IDLE;
                        group_lane      <= 2'd0;
                        target_accepted <= 1'b0;
                    end else if (issue_read) begin
                        if (read_target_lane)
                            target_accepted <= 1'b1;

                        if (group_lane == 2'd3) begin
                            state           <= ST_IDLE;
                            group_lane      <= 2'd0;
                            target_accepted <= 1'b0;
                        end else begin
                            group_lane <= group_lane + 2'd1;
                        end
                    end
                end

                ST_WRITE: begin
                    if (!target_accepted && !source_write_matches) begin
                        protocol_error  <= 1'b1;
                        state           <= ST_IDLE;
                        group_lane      <= 2'd0;
                        target_accepted <= 1'b0;
                    end else if (issue_write) begin
                        if (write_target_lane)
                            target_accepted <= 1'b1;

                        if (group_lane == 2'd3) begin
                            state           <= ST_IDLE;
                            group_lane      <= 2'd0;
                            target_accepted <= 1'b0;
                        end else begin
                            group_lane <= group_lane + 2'd1;
                        end
                    end
                end

                default: begin
                    protocol_error  <= 1'b1;
                    state           <= ST_IDLE;
                    group_lane      <= 2'd0;
                    target_accepted <= 1'b0;
                end
            endcase
        end
    end

endmodule
