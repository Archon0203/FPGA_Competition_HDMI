// ================================================================
// Simulation-only APUG011 application-port behavioral model.
// Models the interface semantics needed by sdram_adapter verification:
//   * init delay
//   * busy/refresh stalls
//   * read/write mutual exclusion
//   * aligned 4-word address groups
//   * byte write masks
//   * fixed non-zero read latency with Sdr_rd_en qualifier
// This is NOT a replacement for the encrypted vendor core.
// ================================================================

`timescale 1ns/1ps

module mock_apug011_app_port #(
    parameter integer MEM_WORDS = 4096,
    parameter integer INIT_CYCLES = 8,
    parameter integer READ_LATENCY = 10
) (
    input  wire         clk,
    input  wire         rst,

    input  wire         App_wr_en,
    input  wire [20:0]  App_wr_addr,
    input  wire [31:0]  App_wr_din,
    input  wire [3:0]   App_wr_dm,
    input  wire         App_rd_en,
    input  wire [20:0]  App_rd_addr,

    output reg          Sdr_rd_en,
    output reg  [31:0]  Sdr_rd_dout,
    output reg          Sdr_init_done,
    output wire         Sdr_init_ref_vld,
    output wire         Sdr_busy,

    input  wire         force_refresh,
    input  wire         force_busy,
    input  wire         inject_unsolicited_response,

    output reg          protocol_error,
    output reg  [31:0]  app_read_count,
    output reg  [31:0]  app_write_count,
    output reg  [31:0]  masked_word_count
);

    reg [31:0] mem [0:MEM_WORDS-1];

    reg [31:0] init_count;
    reg [1:0]  group_pos;
    reg [1:0]  group_dir; // 0 none/boundary, 1 read, 2 write
    reg [20:0] last_addr;

    reg [READ_LATENCY-1:0] rd_pipe_valid;
    reg [31:0] rd_pipe_data [0:READ_LATENCY-1];

    assign Sdr_init_ref_vld = Sdr_init_done && force_refresh;
    assign Sdr_busy = Sdr_init_done && force_busy;

    wire command_allowed = Sdr_init_done && !Sdr_init_ref_vld && !Sdr_busy;

    integer i;
    reg [31:0] new_word;
    always @(posedge clk) begin
        if (rst) begin
            init_count        <= 32'd0;
            Sdr_init_done     <= 1'b0;
            Sdr_rd_en         <= 1'b0;
            Sdr_rd_dout       <= 32'd0;
            protocol_error    <= 1'b0;
            app_read_count    <= 32'd0;
            app_write_count   <= 32'd0;
            masked_word_count <= 32'd0;
            group_pos         <= 2'd0;
            group_dir         <= 2'd0;
            last_addr         <= 21'd0;
            rd_pipe_valid     <= {READ_LATENCY{1'b0}};
            for (i = 0; i < READ_LATENCY; i = i + 1)
                rd_pipe_data[i] <= 32'd0;
            for (i = 0; i < MEM_WORDS; i = i + 1)
                mem[i] <= 32'd0;
        end else begin
            if (!Sdr_init_done) begin
                if (init_count + 32'd1 >= INIT_CYCLES)
                    Sdr_init_done <= 1'b1;
                else
                    init_count <= init_count + 32'd1;
            end

            // Shift read response pipeline.
            Sdr_rd_en   <= rd_pipe_valid[READ_LATENCY-1];
            Sdr_rd_dout <= rd_pipe_data[READ_LATENCY-1];
            for (i = READ_LATENCY-1; i > 0; i = i - 1) begin
                rd_pipe_valid[i] <= rd_pipe_valid[i-1];
                rd_pipe_data[i]  <= rd_pipe_data[i-1];
            end
            rd_pipe_valid[0] <= 1'b0;
            rd_pipe_data[0]  <= 32'd0;

            if (inject_unsolicited_response) begin
                Sdr_rd_en   <= 1'b1;
                Sdr_rd_dout <= 32'hDEAD_BEEF;
            end

            if (App_rd_en && App_wr_en)
                protocol_error <= 1'b1;

            // Compatibility rule observed in the official APUG011 reference:
            // App_wr_dm is held at 0000 during reads.  The real SDRAM DQM pins
            // also mask read output, so a read issued while dm!=0 is unsafe.
            if (App_rd_en && (App_wr_dm !== 4'b0000))
                protocol_error <= 1'b1;

            if ((App_rd_en || App_wr_en) && !command_allowed)
                protocol_error <= 1'b1;

            if ((App_rd_en || App_wr_en) && command_allowed) begin
                // APUG011 v1.2 grouping rule: a jump begins at xx00, then the
                // remaining three command addresses are sequential.
                if (group_pos == 2'd0) begin
                    if ((App_rd_en ? App_rd_addr[1:0] : App_wr_addr[1:0]) != 2'b00)
                        protocol_error <= 1'b1;
                    group_dir <= App_rd_en ? 2'd1 : 2'd2;
                end else begin
                    if ((App_rd_en && group_dir != 2'd1) ||
                        (App_wr_en && group_dir != 2'd2))
                        protocol_error <= 1'b1;
                    if ((App_rd_en ? App_rd_addr : App_wr_addr) != last_addr + 21'd1)
                        protocol_error <= 1'b1;
                end

                last_addr <= App_rd_en ? App_rd_addr : App_wr_addr;
                if (group_pos == 2'd3) begin
                    group_pos <= 2'd0;
                    group_dir <= 2'd0;
                end else begin
                    group_pos <= group_pos + 2'd1;
                end

                if (App_wr_en) begin
                    app_write_count <= app_write_count + 32'd1;
                    if (App_wr_dm == 4'b1111)
                        masked_word_count <= masked_word_count + 32'd1;
                    if (App_wr_addr >= MEM_WORDS) begin
                        protocol_error <= 1'b1;
                    end else begin
                        new_word = mem[App_wr_addr];
                        if (!App_wr_dm[0]) new_word[7:0]   = App_wr_din[7:0];
                        if (!App_wr_dm[1]) new_word[15:8]  = App_wr_din[15:8];
                        if (!App_wr_dm[2]) new_word[23:16] = App_wr_din[23:16];
                        if (!App_wr_dm[3]) new_word[31:24] = App_wr_din[31:24];
                        mem[App_wr_addr] <= new_word;
                    end
                end

                if (App_rd_en) begin
                    app_read_count <= app_read_count + 32'd1;
                    rd_pipe_valid[0] <= 1'b1;
                    if (App_rd_addr >= MEM_WORDS) begin
                        rd_pipe_data[0] <= 32'hBAD0_0000 | {11'd0, App_rd_addr};
                        protocol_error <= 1'b1;
                    end else begin
                        rd_pipe_data[0] <= mem[App_rd_addr];
                    end
                end
            end
        end
    end

endmodule
