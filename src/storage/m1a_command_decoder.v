`include "m1a_protocol.vh"

// Decodes one byte stream into a CRC-checked M1A command.
module m1a_command_decoder (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       byte_valid,
    input  wire [7:0] byte_data,
    output wire       byte_ready,
    output reg        cmd_valid,
    input  wire       cmd_ready,
    output reg  [7:0] cmd_opcode,
    output reg [31:0] cmd_arg,
    output reg        error_valid,
    output reg  [7:0] error_code
);
    localparam [2:0] S_WAIT=3'd0, S_OPCODE=3'd1, S_LENGTH=3'd2,
                     S_PAYLOAD=3'd3, S_CRC_HI=3'd4, S_CRC_LO=3'd5,
                     S_HOLD=3'd6;
    reg [2:0] state;
    reg [7:0] opcode_reg, length_reg, payload_count;
    reg [31:0] payload_reg;
    reg [15:0] crc_reg, crc_received;

    assign byte_ready = (state != S_HOLD);

    function [15:0] crc16_byte;
        input [15:0] crc_in;
        input [7:0] data_in;
        reg [15:0] c;
        integer i;
        begin
            c = crc_in ^ {data_in, 8'h00};
            for (i = 0; i < 8; i = i + 1)
                if (c[15]) c = {c[14:0], 1'b0} ^ 16'h1021;
                else c = {c[14:0], 1'b0};
            crc16_byte = c;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_WAIT;
            opcode_reg <= 8'd0;
            length_reg <= 8'd0;
            payload_count <= 8'd0;
            payload_reg <= 32'd0;
            crc_reg <= `M1A_CRC_INIT;
            crc_received <= 16'd0;
            cmd_valid <= 1'b0;
            cmd_opcode <= 8'd0;
            cmd_arg <= 32'd0;
            error_valid <= 1'b0;
            error_code <= 8'd0;
        end else begin
            error_valid <= 1'b0;
            if (state == S_HOLD) begin
                if (cmd_ready) begin
                    cmd_valid <= 1'b0;
                    state <= S_WAIT;
                end
            end else if (byte_valid) begin
                case (state)
                    S_WAIT: begin
                        if (byte_data == `M1A_FRAME_SOF) state <= S_OPCODE;
                    end
                    S_OPCODE: begin
                        opcode_reg <= byte_data;
                        crc_reg <= crc16_byte(`M1A_CRC_INIT, byte_data);
                        state <= S_LENGTH;
                    end
                    S_LENGTH: begin
                        if (byte_data > 8'd4) begin
                            error_valid <= 1'b1;
                            error_code <= `M1A_ERR_BAD_LENGTH;
                            state <= S_WAIT;
                        end else begin
                            length_reg <= byte_data;
                            payload_count <= 8'd0;
                            payload_reg <= 32'd0;
                            crc_reg <= crc16_byte(crc_reg, byte_data);
                            state <= (byte_data == 0) ? S_CRC_HI : S_PAYLOAD;
                        end
                    end
                    S_PAYLOAD: begin
                        payload_reg <= {payload_reg[23:0], byte_data};
                        crc_reg <= crc16_byte(crc_reg, byte_data);
                        if (payload_count + 1'b1 >= length_reg) state <= S_CRC_HI;
                        else payload_count <= payload_count + 1'b1;
                    end
                    S_CRC_HI: begin
                        crc_received[15:8] <= byte_data;
                        state <= S_CRC_LO;
                    end
                    S_CRC_LO: begin
                        crc_received[7:0] <= byte_data;
                        if ({crc_received[15:8], byte_data} == crc_reg) begin
                            cmd_valid <= 1'b1;
                            cmd_opcode <= opcode_reg;
                            cmd_arg <= payload_reg;
                            state <= S_HOLD;
                        end else begin
                            error_valid <= 1'b1;
                            error_code <= `M1A_ERR_BAD_CRC;
                        end
                        if ({crc_received[15:8], byte_data} != crc_reg)
                            state <= S_WAIT;
                    end
                    default: state <= S_WAIT;
                endcase
            end
        end
    end
endmodule
