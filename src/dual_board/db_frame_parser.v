// Minimal M1 control frame parser: 55 A5 opcode length=0 crc8.
// The parser intentionally has no media payload path; M1 only proves roles,
// GPIO direction, reset recovery and a small control protocol.
module db_frame_parser (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       byte_valid,
    input  wire [7:0] byte_data,
    output reg        frame_valid,
    output reg [7:0]  opcode,
    output reg        frame_error
);
    reg [2:0] state;
    reg [7:0] op_reg;
    reg [7:0] crc_reg;

    function [7:0] crc8_next;
        input [7:0] crc;
        input [7:0] value;
        integer i;
        reg [7:0] c;
        begin
            c = crc ^ value;
            for (i = 0; i < 8; i = i + 1)
                c = c[7] ? ((c << 1) ^ 8'h07) : (c << 1);
            crc8_next = c;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= 3'd0;
            op_reg <= 8'h00;
            crc_reg <= 8'h00;
            opcode <= 8'h00;
            frame_valid <= 1'b0;
            frame_error <= 1'b0;
        end else begin
            frame_valid <= 1'b0;
            frame_error <= 1'b0;
            if (byte_valid) begin
                case (state)
                    3'd0: state <= (byte_data == 8'h55) ? 3'd1 : 3'd0;
                    3'd1: state <= (byte_data == 8'hA5) ? 3'd2 : 3'd0;
                    3'd2: begin op_reg <= byte_data; crc_reg <= crc8_next(8'h00, byte_data); state <= 3'd3; end
                    3'd3: state <= (byte_data == 8'h00) ? 3'd4 : 3'd0;
                    3'd4: begin
                        state <= 3'd0;
                        if (byte_data == crc_reg) begin
                            opcode <= op_reg;
                            frame_valid <= 1'b1;
                        end else begin
                            frame_error <= 1'b1;
                        end
                    end
                    default: state <= 3'd0;
                endcase
            end
        end
    end
endmodule
