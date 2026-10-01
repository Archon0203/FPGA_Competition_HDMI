// 8N1 UART transmitter. The byte is accepted for one clk when ready is high.
module db_uart_tx #(
    parameter integer CLKS_PER_BIT = 434 // 50 MHz / 115200, rounded
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    input  wire [7:0] data,
    output wire       ready,
    output reg        tx
);
    localparam integer CNT_W = 10;
    reg [CNT_W-1:0] count;
    reg [3:0] bit_index;
    reg [9:0] frame;
    reg busy;

    assign ready = ~busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= {CNT_W{1'b0}};
            bit_index <= 4'd0;
            frame <= 10'h3ff;
            busy <= 1'b0;
            tx <= 1'b1;
        end else if (!busy) begin
            tx <= 1'b1;
            count <= {CNT_W{1'b0}};
            bit_index <= 4'd0;
            if (start) begin
                frame <= {1'b1, data, 1'b0};
                busy <= 1'b1;
                tx <= 1'b0;
            end
        end else if (count == CLKS_PER_BIT-1) begin
            count <= {CNT_W{1'b0}};
            if (bit_index == 4'd9) begin
                busy <= 1'b0;
                tx <= 1'b1;
            end else begin
                bit_index <= bit_index + 1'b1;
                tx <= frame[bit_index + 1'b1];
            end
        end else begin
            count <= count + 1'b1;
        end
    end
endmodule
