// 8N1 UART receiver with two-flop input synchronizer and correct 1.5-bit
// first-data sampling. This is the corrected receiver intended to replace
// the earlier project receiver that sampled D0 too early.
module db_uart_rx #(
    parameter integer CLKS_PER_BIT = 434
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg        valid,
    output reg [7:0]  data,
    output reg        framing_error,
    output reg        rx_activity
);
    localparam [2:0] ST_IDLE  = 3'd0;
    localparam [2:0] ST_START = 3'd1;
    localparam [2:0] ST_DATA  = 3'd2;
    localparam [2:0] ST_STOP  = 3'd3;

    reg [2:0]  state;
    reg [15:0] sample_count;
    reg [2:0]  bit_index;
    reg [7:0]  shift;
    reg        rx_meta;
    reg        rx_sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            sample_count  <= 16'd0;
            bit_index     <= 3'd0;
            shift         <= 8'h00;
            rx_meta       <= 1'b1;
            rx_sync       <= 1'b1;
            valid         <= 1'b0;
            data          <= 8'h00;
            framing_error <= 1'b0;
            rx_activity   <= 1'b0;
        end else begin
            rx_meta       <= rx;
            rx_sync       <= rx_meta;
            valid         <= 1'b0;
            framing_error <= 1'b0;
            rx_activity   <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (!rx_sync) begin
                        rx_activity <= 1'b1;
                        if (CLKS_PER_BIT <= 2)
                            sample_count <= 16'd0;
                        else
                            sample_count <= (CLKS_PER_BIT / 2) - 1;
                        state <= ST_START;
                    end
                end

                ST_START: begin
                    if (sample_count != 0) begin
                        sample_count <= sample_count - 1'b1;
                    end else if (!rx_sync) begin
                        // Confirm start bit near its center. D0 is sampled one
                        // whole bit later: approximately 1.5 bits after edge.
                        sample_count <= CLKS_PER_BIT - 1;
                        bit_index    <= 3'd0;
                        state        <= ST_DATA;
                    end else begin
                        state <= ST_IDLE;
                    end
                end

                ST_DATA: begin
                    if (sample_count != 0) begin
                        sample_count <= sample_count - 1'b1;
                    end else begin
                        shift[bit_index] <= rx_sync;
                        sample_count <= CLKS_PER_BIT - 1;
                        if (bit_index == 3'd7)
                            state <= ST_STOP;
                        else
                            bit_index <= bit_index + 1'b1;
                    end
                end

                ST_STOP: begin
                    if (sample_count != 0) begin
                        sample_count <= sample_count - 1'b1;
                    end else begin
                        state <= ST_IDLE;
                        if (rx_sync) begin
                            data  <= shift;
                            valid <= 1'b1;
                        end else begin
                            framing_error <= 1'b1;
                        end
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
