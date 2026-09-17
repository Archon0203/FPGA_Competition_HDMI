// ================================================================
// Module  : p1_sdram_cached_adapter
// Purpose : P1-05A sequential-video optimized abstract memory ->
//           APUG011 application-side adapter.
//
// Why this exists:
//   The frozen P1-02 sdram_adapter preserves arbitrary single-word semantics
//   by expanding every abstract read into a complete aligned 4-word APUG011
//   group and discarding the other three returned lanes.  That is correct for
//   sparse/random accesses, but wastes 75% of provider read bandwidth for the
//   sequential framebuffer pattern 0,1,2,3,4,...
//
//   This P1-specific adapter keeps the same abstract valid/ready interface but
//   caches the complete 4-word APUG011 read group.  The first access to a group
//   performs one physical 4-word fill; the following three sequential accesses
//   are served from the cache without repeating the physical group.
//
// Constraints:
//   * APUG011 grouping contract is unchanged: a provider read group starts at
//     address xx00 and issues exactly four sequential App_rd_en words.
//   * Writes retain the proven P1-02 masked 4-word behavior, but the
//     abstract request is first captured in a one-entry register slice so
//     upstream address/data are not part of the APUG011 timing cone.
//   * Vendor protected sources are untouched.
//   * This module is a P1-05 candidate and does not change the frozen
//     sdram_adapter used by P1-02 regressions.
// ================================================================

module p1_sdram_cached_adapter #(
    // Production P1-05A build disables diagnostic counters/checks from the
    // 150 MHz timing cone. Unit/integration simulations keep the default 1.
    parameter integer ENABLE_RUNTIME_DIAGNOSTICS = 1
) (
    input  wire         clk,
    input  wire         rst_n,

    // ---------------- Abstract memory side ----------------
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
    output reg  [31:0]  app_write_word_count_debug,
    output reg  [31:0]  read_cache_hit_count_debug,
    output reg  [31:0]  read_cache_miss_count_debug
);

    localparam [1:0] ST_IDLE      = 2'd0;
    localparam [1:0] ST_READ_FILL = 2'd1;
    localparam [1:0] ST_WRITE     = 2'd2;

    reg [1:0] state;

    // ------------------------------------------------------------
    // Provider availability / health.
    // ------------------------------------------------------------
    reg init_seen;

    wire provider_available = Sdr_init_done &&
                              !Sdr_init_ref_vld &&
                              !Sdr_busy;

    assign ready_for_traffic = Sdr_init_done && !provider_fault;
    assign App_ref_req       = 1'b0;

    // ------------------------------------------------------------
    // 4-word read cache.
    // ------------------------------------------------------------
    reg        cache_valid;
    reg [18:0] cache_group_tag;
    reg [31:0] cache_data0;
    reg [31:0] cache_data1;
    reg [31:0] cache_data2;
    reg [31:0] cache_data3;

    wire [18:0] incoming_group_tag = mem_rd_addr[20:2];
    wire        incoming_cache_hit = cache_valid &&
                                     (incoming_group_tag == cache_group_tag);

    // One abstract read is active on a miss while the complete provider group
    // is fetched.  Cache hits can be accepted every cycle once back in IDLE.
    reg [1:0]  miss_lane;
    reg [20:0] read_group_base;
    reg [2:0]  read_issue_count;
    reg [2:0]  read_resp_count;

    reg        mem_rvalid_reg;
    reg [31:0] mem_rdata_reg;

    assign mem_rvalid = mem_rvalid_reg;
    assign mem_rdata  = mem_rdata_reg;

    wire can_accept_read = (state == ST_IDLE) &&
                           Sdr_init_done &&
                           !provider_fault &&
                           mem_rd_valid &&
                           (incoming_cache_hit || provider_available);

    assign mem_rd_ready = can_accept_read;

    wire rd_accept = mem_rd_valid && mem_rd_ready;
    wire rd_accept_hit  = rd_accept && incoming_cache_hit;
    wire rd_accept_miss = rd_accept && !incoming_cache_hit;

    function [31:0] cache_lane_data;
        input [1:0] lane;
        begin
            case (lane)
                2'd0: cache_lane_data = cache_data0;
                2'd1: cache_lane_data = cache_data1;
                2'd2: cache_lane_data = cache_data2;
                default: cache_lane_data = cache_data3;
            endcase
        end
    endfunction

    // Provider read fill: issue exactly one aligned 4-word APUG011 group.
    wire issue_read_word = (state == ST_READ_FILL) &&
                           provider_available &&
                           (read_issue_count < 3'd4);

    assign App_rd_en   = issue_read_word;
    assign App_rd_addr = read_group_base + {{18{1'b0}}, read_issue_count};

    // Accept a returned provider word only when it belongs to the current
    // in-flight group.  Same-cycle issue+response is tolerated even though the
    // official core has non-zero latency.
    wire [3:0] issued_after_this_cycle =
        {1'b0, read_issue_count} + (issue_read_word ? 4'd1 : 4'd0);

    wire read_response_legal = (state == ST_READ_FILL) &&
                               Sdr_rd_en &&
                               ({1'b0, read_resp_count} < issued_after_this_cycle) &&
                               (read_resp_count < 3'd4);

    wire final_group_response = read_response_legal &&
                                (read_resp_count == 3'd3);

    // Select the requested word when the last physical lane returns.  If the
    // requested lane itself is lane 3, use Sdr_rd_dout directly because the
    // nonblocking cache write becomes visible only after this clock edge.
    wire [31:0] miss_response_data =
        (miss_lane == 2'd0) ? cache_data0 :
        (miss_lane == 2'd1) ? cache_data1 :
        (miss_lane == 2'd2) ? cache_data2 :
                              Sdr_rd_dout;

    // ------------------------------------------------------------
    // Registered abstract-write request slice.
    //
    // The upstream valid/ready transaction is accepted once in ST_IDLE and
    // address/data are captured locally.  The following APUG011 masked
    // 4-word group is then generated exclusively from these registers.
    // This deliberately removes the old write-source data/address compare
    // from the 150 MHz feedback path into mem_wr_ready / writer state.
    // ------------------------------------------------------------
    reg [1:0]  write_group_lane;
    reg [20:0] write_group_base;
    reg [1:0]  write_target_lane;
    reg [31:0] write_data;

    wire can_accept_write = (state == ST_IDLE) &&
                            provider_available &&
                            !provider_fault &&
                            !mem_rd_valid;

    assign mem_wr_ready = can_accept_write;
    wire wr_accept = mem_wr_valid && mem_wr_ready;

    wire issue_write_word = (state == ST_WRITE) &&
                            provider_available;

    wire write_target_word = (write_group_lane == write_target_lane);

    assign App_wr_en   = issue_write_word;
    assign App_wr_addr = write_group_base + {19'd0, write_group_lane};
    assign App_wr_din  = write_target_word ? write_data : 32'd0;
    assign App_wr_dm   = issue_write_word
                       ? (write_target_word ? 4'b0000 : 4'b1111)
                       : 4'b0000;

    // ------------------------------------------------------------
    // Main control / diagnostics.
    // ------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                       <= ST_IDLE;
            init_seen                   <= 1'b0;

            cache_valid                 <= 1'b0;
            cache_group_tag             <= 19'd0;
            cache_data0                 <= 32'd0;
            cache_data1                 <= 32'd0;
            cache_data2                 <= 32'd0;
            cache_data3                 <= 32'd0;

            miss_lane                   <= 2'd0;
            read_group_base             <= 21'd0;
            read_issue_count            <= 3'd0;
            read_resp_count             <= 3'd0;

            mem_rvalid_reg              <= 1'b0;
            mem_rdata_reg               <= 32'd0;

            write_group_lane            <= 2'd0;
            write_group_base            <= 21'd0;
            write_target_lane           <= 2'd0;
            write_data                  <= 32'd0;

            protocol_error              <= 1'b0;
            provider_fault              <= 1'b0;
            contention_seen             <= 1'b0;
            read_outstanding_debug      <= 16'd0;
            read_accept_count_debug     <= 32'd0;
            write_accept_count_debug    <= 32'd0;
            app_read_word_count_debug   <= 32'd0;
            app_write_word_count_debug  <= 32'd0;
            read_cache_hit_count_debug  <= 32'd0;
            read_cache_miss_count_debug <= 32'd0;
        end else begin
            // Response is a one-cycle pulse.
            mem_rvalid_reg <= 1'b0;

            if (Sdr_init_done)
                init_seen <= 1'b1;
            if (init_seen && !Sdr_init_done)
                provider_fault <= 1'b1;

            // The provider response check is functional: an unsolicited or
            // out-of-window provider response must still raise the sticky
            // protocol error. The remaining counters/checks are diagnostics
            // only and are excluded from the production 150 MHz timing cone.
            if (Sdr_rd_en && !read_response_legal)
                protocol_error <= 1'b1;

            if (ENABLE_RUNTIME_DIAGNOSTICS) begin
                if (mem_rd_valid && mem_wr_valid)
                    contention_seen <= 1'b1;

                if (rd_accept) begin
                    read_accept_count_debug <= read_accept_count_debug + 32'd1;
                    if (rd_accept_hit)
                        read_cache_hit_count_debug <= read_cache_hit_count_debug + 32'd1;
                    else
                        read_cache_miss_count_debug <= read_cache_miss_count_debug + 32'd1;
                end

                if (wr_accept)
                    write_accept_count_debug <= write_accept_count_debug + 32'd1;

                if (issue_read_word)
                    app_read_word_count_debug <= app_read_word_count_debug + 32'd1;
                if (issue_write_word)
                    app_write_word_count_debug <= app_write_word_count_debug + 32'd1;

                // App_rd_en/App_wr_en are mutually exclusive by state. Keep
                // this assertion in simulation/debug builds without allowing
                // it to become a 150 MHz shared combinational cone.
                if (App_rd_en && App_wr_en)
                    protocol_error <= 1'b1;

                case ({rd_accept, (rd_accept_hit || final_group_response)})
                    2'b10: read_outstanding_debug <= read_outstanding_debug + 16'd1;
                    2'b01: begin
                        if (read_outstanding_debug != 16'd0)
                            read_outstanding_debug <= read_outstanding_debug - 16'd1;
                    end
                    default: read_outstanding_debug <= read_outstanding_debug;
                endcase

                if ((rd_accept_hit || final_group_response) &&
                    (read_outstanding_debug == 16'd0) &&
                    !rd_accept)
                    protocol_error <= 1'b1;
            end

            // Cache-hit response: one cycle after abstract acceptance.
            if (rd_accept_hit) begin
                mem_rvalid_reg <= 1'b1;
                mem_rdata_reg  <= cache_lane_data(mem_rd_addr[1:0]);
            end

            // Capture provider read data in order.
            if (read_response_legal) begin
                case (read_resp_count[1:0])
                    2'd0: cache_data0 <= Sdr_rd_dout;
                    2'd1: cache_data1 <= Sdr_rd_dout;
                    2'd2: cache_data2 <= Sdr_rd_dout;
                    2'd3: cache_data3 <= Sdr_rd_dout;
                endcase

                if (final_group_response) begin
                    cache_valid     <= 1'b1;
                    cache_group_tag <= read_group_base[20:2];
                    read_resp_count <= 3'd0;

                    mem_rvalid_reg <= 1'b1;
                    mem_rdata_reg  <= miss_response_data;
                    state          <= ST_IDLE;
                end else begin
                    read_resp_count <= read_resp_count + 3'd1;
                end
            end

            if (issue_read_word)
                read_issue_count <= read_issue_count + 3'd1;

            case (state)
                ST_IDLE: begin
                    write_group_lane <= 2'd0;
                    read_issue_count <= 3'd0;
                    read_resp_count  <= 3'd0;

                    // Strict display-read priority, matching sdram_arbiter.
                    if (rd_accept_miss) begin
                        miss_lane       <= mem_rd_addr[1:0];
                        read_group_base <= {mem_rd_addr[20:2], 2'b00};
                        cache_valid     <= 1'b0;
                        state           <= ST_READ_FILL;
                    end else if (wr_accept) begin
                        // One-entry registered write request slice.
                        write_group_base  <= {mem_wr_addr[20:2], 2'b00};
                        write_target_lane <= mem_wr_addr[1:0];
                        write_data        <= mem_wr_data;
                        write_group_lane  <= 2'd0;
                        cache_valid       <= 1'b0;
                        state             <= ST_WRITE;
                    end
                end

                ST_READ_FILL: begin
                    // Completion is handled by final_group_response above.
                    // The counters are structurally bounded by issue/read
                    // qualification; keep the redundant assertion only in
                    // diagnostic simulation builds.
                    if (ENABLE_RUNTIME_DIAGNOSTICS &&
                        (read_issue_count > 3'd4 || read_resp_count > 3'd4))
                        protocol_error <= 1'b1;
                end

                ST_WRITE: begin
                    // Once accepted, the upstream request may advance
                    // immediately.  The complete provider transaction is
                    // driven only from the registered request fields above.
                    if (issue_write_word) begin
                        if (write_group_lane == 2'd3) begin
                            state            <= ST_IDLE;
                            write_group_lane <= 2'd0;
                        end else begin
                            write_group_lane <= write_group_lane + 2'd1;
                        end
                    end
                end

                default: begin
                    protocol_error <= 1'b1;
                    state          <= ST_IDLE;
                    cache_valid    <= 1'b0;
                end
            endcase
        end
    end

endmodule
