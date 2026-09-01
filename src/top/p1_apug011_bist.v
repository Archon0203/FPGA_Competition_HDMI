// ================================================================
// 模块   : p1_apug011_bist
// 功能   : P1-02B TD synthesis/P&R 专用的极小 SDRAM 自检流量源。
//           只用于让 sdram_arbiter -> sdram_adapter -> APUG011 ->
//           EG_PHY_SDRAM_2M_32 在综合/P&R 中保持真实可观察数据路径。
//           不属于最终业务播放逻辑，也不改变 P0 frozen contract。
//
// 流程：等待 backend_ready -> 写 addr5/addr8 -> 读 addr5/addr8 -> 比较。
// ================================================================

module p1_apug011_bist (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        backend_ready,

    output reg         wr_valid,
    output reg  [20:0] wr_addr,
    output reg  [31:0] wr_data,
    input  wire        wr_ready,

    output reg         rd_valid,
    output reg  [20:0] rd_addr,
    input  wire        rd_ready,
    input  wire        rd_rvalid,
    input  wire [31:0] rd_rdata,

    input  wire        arb_protocol_error,
    input  wire        adapter_protocol_error,
    input  wire        provider_fault,

    output reg         done,
    output reg         pass,
    output reg         fail,
    output reg  [3:0]  state_debug
);

    localparam [3:0] ST_WAIT_INIT = 4'd0;
    localparam [3:0] ST_WR0       = 4'd1;
    localparam [3:0] ST_WR1       = 4'd2;
    localparam [3:0] ST_RD0_REQ   = 4'd3;
    localparam [3:0] ST_RD0_WAIT  = 4'd4;
    localparam [3:0] ST_RD1_REQ   = 4'd5;
    localparam [3:0] ST_RD1_WAIT  = 4'd6;
    localparam [3:0] ST_PASS      = 4'd7;
    localparam [3:0] ST_FAIL      = 4'd8;

    localparam [20:0] ADDR0 = 21'd5;
    localparam [20:0] ADDR1 = 21'd8;
    localparam [31:0] DATA0 = 32'h1122_3344;
    localparam [31:0] DATA1 = 32'hA5A5_5A5A;

    reg [3:0] state;

    always @(*) begin
        wr_valid = 1'b0;
        wr_addr  = 21'd0;
        wr_data  = 32'd0;
        rd_valid = 1'b0;
        rd_addr  = 21'd0;

        case (state)
            ST_WR0: begin
                wr_valid = 1'b1;
                wr_addr  = ADDR0;
                wr_data  = DATA0;
            end
            ST_WR1: begin
                wr_valid = 1'b1;
                wr_addr  = ADDR1;
                wr_data  = DATA1;
            end
            ST_RD0_REQ: begin
                rd_valid = 1'b1;
                rd_addr  = ADDR0;
            end
            ST_RD1_REQ: begin
                rd_valid = 1'b1;
                rd_addr  = ADDR1;
            end
            default: begin
                wr_valid = 1'b0;
                rd_valid = 1'b0;
            end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ST_WAIT_INIT;
            done        <= 1'b0;
            pass        <= 1'b0;
            fail        <= 1'b0;
            state_debug <= ST_WAIT_INIT;
        end else begin
            state_debug <= state;

            if (arb_protocol_error || adapter_protocol_error || provider_fault) begin
                state <= ST_FAIL;
            end else begin
                case (state)
                    ST_WAIT_INIT: begin
                        if (backend_ready)
                            state <= ST_WR0;
                    end

                    ST_WR0: begin
                        if (wr_ready)
                            state <= ST_WR1;
                    end

                    ST_WR1: begin
                        if (wr_ready)
                            state <= ST_RD0_REQ;
                    end

                    ST_RD0_REQ: begin
                        if (rd_ready) begin
                            if (rd_rvalid) begin
                                if (rd_rdata == DATA0)
                                    state <= ST_RD1_REQ;
                                else
                                    state <= ST_FAIL;
                            end else begin
                                state <= ST_RD0_WAIT;
                            end
                        end
                    end

                    ST_RD0_WAIT: begin
                        if (rd_rvalid) begin
                            if (rd_rdata == DATA0)
                                state <= ST_RD1_REQ;
                            else
                                state <= ST_FAIL;
                        end
                    end

                    ST_RD1_REQ: begin
                        if (rd_ready) begin
                            if (rd_rvalid) begin
                                if (rd_rdata == DATA1)
                                    state <= ST_PASS;
                                else
                                    state <= ST_FAIL;
                            end else begin
                                state <= ST_RD1_WAIT;
                            end
                        end
                    end

                    ST_RD1_WAIT: begin
                        if (rd_rvalid) begin
                            if (rd_rdata == DATA1)
                                state <= ST_PASS;
                            else
                                state <= ST_FAIL;
                        end
                    end

                    ST_PASS: begin
                        done <= 1'b1;
                        pass <= 1'b1;
                        fail <= 1'b0;
                    end

                    ST_FAIL: begin
                        done <= 1'b1;
                        pass <= 1'b0;
                        fail <= 1'b1;
                    end

                    default: begin
                        state <= ST_FAIL;
                    end
                endcase
            end
        end
    end

endmodule
