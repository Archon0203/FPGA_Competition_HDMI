`timescale 1ns/1ps

// ================================================================
// Simulation-only ordered SDRAM model for P0 mock-chain verification.
// - 32-bit word addressed
// - independent bounded command stalls
// - ordered read-response queue with bounded latency/stalls
// - no reset clear of memory contents
// ================================================================
module mock_sdram #(
    parameter integer DEPTH_WORDS = 400000,
    parameter integer MAX_PENDING_READS = 32,
    parameter integer MIN_READ_LATENCY = 1,
    parameter integer MAX_READ_LATENCY = 7
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        wr_valid,
    input  wire [20:0] wr_addr,
    input  wire [31:0] wr_data,
    output wire        wr_ready,

    input  wire        rd_valid,
    input  wire [20:0] rd_addr,
    output wire        rd_ready,
    output reg         rvalid,
    output reg  [31:0] rdata,

    input  wire        random_stalls_enable,
    input  wire        force_wr_stall,
    input  wire        force_rd_stall,
    input  wire        force_resp_stall,

    output reg         range_error,
    output reg         queue_error,
    output reg         write_commit_pulse,
    output reg [20:0]  write_commit_addr,
    output reg [31:0]  write_commit_data,
    output reg         read_response_pulse,
    output reg [20:0]  read_response_addr,
    output wire [15:0] pending_reads_debug
);

    reg [31:0] mem [0:DEPTH_WORDS-1];

    reg [20:0] read_addr_q [0:MAX_PENDING_READS-1];
    integer    read_delay_q [0:MAX_PENDING_READS-1];
    integer q_head;
    integer q_tail;
    integer q_count;

    reg [15:0] lfsr;

    wire wr_addr_ok = (wr_addr < DEPTH_WORDS);
    wire rd_addr_ok = (rd_addr < DEPTH_WORDS);
    wire queue_has_space = (q_count < MAX_PENDING_READS);

    // Bounded pseudo-random stalls. With random_stalls_enable=0 the model is
    // always command-ready (subject to address/queue legality).
    wire random_wr_ready = lfsr[0] || lfsr[2] || lfsr[5];
    wire random_rd_ready = lfsr[1] || lfsr[3] || lfsr[6];
    wire random_resp_go  = lfsr[4] || lfsr[7] || lfsr[9];

    assign wr_ready = !force_wr_stall && wr_addr_ok &&
                      (!random_stalls_enable || random_wr_ready);
    assign rd_ready = !force_rd_stall && rd_addr_ok && queue_has_space &&
                      (!random_stalls_enable || random_rd_ready);

    wire wr_accept = wr_valid && wr_ready;
    wire rd_accept = rd_valid && rd_ready;

    wire head_ready = (q_count > 0) && (read_delay_q[q_head] <= 0);
    wire response_go = head_ready && !force_resp_stall &&
                       (!random_stalls_enable || random_resp_go);

    assign pending_reads_debug = q_count[15:0];

    function integer next_index;
        input integer idx;
        input integer limit;
        begin
            if (idx + 1 >= limit)
                next_index = 0;
            else
                next_index = idx + 1;
        end
    endfunction

    function integer latency_from_lfsr;
        input [15:0] value;
        integer span;
        begin
            if (MAX_READ_LATENCY <= MIN_READ_LATENCY) begin
                latency_from_lfsr = MIN_READ_LATENCY;
            end else begin
                span = MAX_READ_LATENCY - MIN_READ_LATENCY + 1;
                latency_from_lfsr = MIN_READ_LATENCY + (value % span);
            end
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q_head              <= 0;
            q_tail              <= 0;
            q_count             <= 0;
            lfsr                <= 16'h1ACE;
            rvalid              <= 1'b0;
            rdata               <= 32'd0;
            range_error         <= 1'b0;
            queue_error         <= 1'b0;
            write_commit_pulse  <= 1'b0;
            write_commit_addr   <= 21'd0;
            write_commit_data   <= 32'd0;
            read_response_pulse <= 1'b0;
            read_response_addr  <= 21'd0;
        end else begin
            // x^16 + x^14 + x^13 + x^11 + 1
            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};

            rvalid              <= 1'b0;
            write_commit_pulse  <= 1'b0;
            read_response_pulse <= 1'b0;

            if (wr_valid && !wr_addr_ok)
                range_error <= 1'b1;
            if (rd_valid && !rd_addr_ok)
                range_error <= 1'b1;
            if ((q_count < 0) || (q_count > MAX_PENDING_READS))
                queue_error <= 1'b1;
            if (wr_accept) begin
                mem[wr_addr]       <= wr_data;
                write_commit_pulse <= 1'b1;
                write_commit_addr  <= wr_addr;
                write_commit_data  <= wr_data;
            end

            if (rd_accept) begin
                read_addr_q[q_tail]  <= rd_addr;
                read_delay_q[q_tail] <= latency_from_lfsr(lfsr);
                q_tail <= next_index(q_tail, MAX_PENDING_READS);
            end

            if ((q_count > 0) && !response_go && (read_delay_q[q_head] > 0))
                read_delay_q[q_head] <= read_delay_q[q_head] - 1;

            if (response_go) begin
                rvalid              <= 1'b1;
                rdata               <= mem[read_addr_q[q_head]];
                read_response_pulse <= 1'b1;
                read_response_addr  <= read_addr_q[q_head];
                q_head <= next_index(q_head, MAX_PENDING_READS);
            end

            case ({rd_accept, response_go})
                2'b10: q_count <= q_count + 1;
                2'b01: q_count <= q_count - 1;
                default: q_count <= q_count;
            endcase
        end
    end

endmodule
