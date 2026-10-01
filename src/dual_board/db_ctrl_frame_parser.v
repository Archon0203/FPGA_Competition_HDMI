// ============================================================================
// M1 generic UART control-frame parser.
// Wire format: 55 A5 opcode length payload[0..length-1] crc8
// CRC-8 polynomial 0x07, init 0x00, over opcode + length + payload only.
// Maximum payload length accepted in M1 is four bytes.
// ============================================================================
module db_ctrl_frame_parser (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        byte_valid,
    input  wire [7:0]  byte_data,
    output reg         frame_valid,
    output reg  [7:0]  opcode,
    output reg  [2:0]  length,
    output reg  [31:0] payload,
    output reg         frame_error
);
    localparam [2:0] ST_55      = 3'd0;
    localparam [2:0] ST_A5      = 3'd1;
    localparam [2:0] ST_OPCODE  = 3'd2;
    localparam [2:0] ST_LENGTH  = 3'd3;
    localparam [2:0] ST_PAYLOAD = 3'd4;
    localparam [2:0] ST_CRC     = 3'd5;

    reg [2:0]  state;
    reg [7:0]  op_reg;
    reg [2:0]  len_reg;
    reg [2:0]  payload_index;
    reg [31:0] payload_reg;
    reg [7:0]  crc_reg;

    function [7:0] crc8_update;
        input [7:0] crc;
        input [7:0] value;
        integer i;
        reg [7:0] c;
        begin
            c = crc ^ value;
            for (i = 0; i < 8; i = i + 1)
                c = c[7] ? ((c << 1) ^ 8'h07) : (c << 1);
            crc8_update = c;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_55;
            op_reg        <= 8'h00;
            len_reg       <= 3'd0;
            payload_index <= 3'd0;
            payload_reg   <= 32'd0;
            crc_reg       <= 8'h00;
            frame_valid   <= 1'b0;
            opcode        <= 8'h00;
            length        <= 3'd0;
            payload       <= 32'd0;
            frame_error   <= 1'b0;
        end else begin
            frame_valid <= 1'b0;
            frame_error <= 1'b0;

            if (byte_valid) begin
                case (state)
                    ST_55: begin
                        if (byte_data == 8'h55)
                            state <= ST_A5;
                    end

                    ST_A5: begin
                        if (byte_data == 8'hA5)
                            state <= ST_OPCODE;
                        else if (byte_data == 8'h55)
                            state <= ST_A5;
                        else
                            state <= ST_55;
                    end

                    ST_OPCODE: begin
                        op_reg  <= byte_data;
                        crc_reg <= crc8_update(8'h00, byte_data);
                        state   <= ST_LENGTH;
                    end

                    ST_LENGTH: begin
                        if (byte_data[7:3] != 5'b00000 || byte_data[2:0] > 3'd4) begin
                            frame_error <= 1'b1;
                            state <= ST_55;
                        end else begin
                            len_reg       <= byte_data[2:0];
                            payload_index <= 3'd0;
                            payload_reg   <= 32'd0;
                            crc_reg       <= crc8_update(crc_reg, byte_data);
                            state         <= (byte_data[2:0] == 0) ? ST_CRC : ST_PAYLOAD;
                        end
                    end

                    ST_PAYLOAD: begin
                        case (payload_index)
                            3'd0: payload_reg[7:0]   <= byte_data;
                            3'd1: payload_reg[15:8]  <= byte_data;
                            3'd2: payload_reg[23:16] <= byte_data;
                            3'd3: payload_reg[31:24] <= byte_data;
                            default: ;
                        endcase
                        crc_reg <= crc8_update(crc_reg, byte_data);
                        if (payload_index + 1'b1 >= len_reg) begin
                            state <= ST_CRC;
                        end else begin
                            payload_index <= payload_index + 1'b1;
                        end
                    end

                    ST_CRC: begin
                        state <= ST_55;
                        if (byte_data == crc_reg) begin
                            opcode      <= op_reg;
                            length      <= len_reg;
                            payload     <= payload_reg;
                            frame_valid <= 1'b1;
                        end else begin
                            frame_error <= 1'b1;
                        end
                    end

                    default: state <= ST_55;
                endcase
            end
        end
    end
endmodule
