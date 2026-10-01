// Serializer for a zero-payload control frame: 55 A5 opcode 00 crc8.
module db_frame_tx (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       request,
    input  wire [7:0] opcode,
    input  wire       uart_ready,
    output wire       uart_start,
    output wire [7:0] uart_data,
    output wire       busy
);
    function [7:0] crc8;
        input [7:0] value;
        integer i;
        reg [7:0] c;
        begin
            c = value;
            for (i = 0; i < 8; i = i + 1)
                c = c[7] ? ((c << 1) ^ 8'h07) : (c << 1);
            crc8 = c;
        end
    endfunction

    reg [2:0] index;
    reg active;
    reg [7:0] op_latched;
    assign busy = active;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            index <= 3'd0;
            active <= 1'b0;
            op_latched <= 8'h00;
        end else begin
            if (!active) begin
                if (request) begin
                    active <= 1'b1;
                    index <= 3'd0;
                    op_latched <= opcode;
                end
            end else if (uart_ready) begin
                if (index == 3'd4) begin
                    active <= 1'b0;
                    index <= 3'd0;
                end else begin
                    index <= index + 1'b1;
                end
            end
        end
    end

    assign uart_start = active && uart_ready;
    assign uart_data = (index == 3'd0) ? 8'h55 :
                       (index == 3'd1) ? 8'hA5 :
                       (index == 3'd2) ? op_latched :
                       (index == 3'd3) ? 8'h00 : crc8(op_latched);
endmodule
