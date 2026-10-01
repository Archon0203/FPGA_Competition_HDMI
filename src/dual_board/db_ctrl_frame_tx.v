// ============================================================================
// M1 generic UART control-frame transmitter.
// Wire format: 55 A5 opcode length payload[0..length-1] crc8
// CRC-8 polynomial 0x07, init 0x00, over opcode + length + payload only.
// Maximum payload is four bytes in M1; this is enough for image_id/status/
// credit control while keeping the bring-up transport deliberately small.
// ============================================================================
module db_ctrl_frame_tx (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        request,
    input  wire [7:0]  opcode,
    input  wire [2:0]  length,
    input  wire [31:0] payload,
    input  wire        uart_ready,
    output wire        uart_start,
    output reg  [7:0]  uart_data,
    output wire        busy
);
    reg        active;
    reg [3:0]  byte_index;
    reg [7:0]  op_latched;
    reg [2:0]  len_latched;
    reg [31:0] payload_latched;
    reg [7:0]  crc_latched;

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

    function [7:0] frame_crc;
        input [7:0]  op;
        input [2:0]  len;
        input [31:0] pl;
        integer j;
        reg [7:0] c;
        begin
            c = crc8_update(8'h00, op);
            c = crc8_update(c, {5'b00000, len});
            for (j = 0; j < 4; j = j + 1) begin
                if (j < len)
                    c = crc8_update(c, (pl >> (j*8)) & 8'hff);
            end
            frame_crc = c;
        end
    endfunction

    assign busy = active;
    assign uart_start = active && uart_ready;

    always @(*) begin
        case (byte_index)
            4'd0: uart_data = 8'h55;
            4'd1: uart_data = 8'hA5;
            4'd2: uart_data = op_latched;
            4'd3: uart_data = {5'b00000, len_latched};
            default: begin
                if (byte_index < (4 + len_latched))
                    uart_data = (payload_latched >> ((byte_index-4)*8)) & 8'hff;
                else
                    uart_data = crc_latched;
            end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active          <= 1'b0;
            byte_index      <= 4'd0;
            op_latched      <= 8'h00;
            len_latched     <= 3'd0;
            payload_latched <= 32'd0;
            crc_latched     <= 8'h00;
        end else begin
            if (!active) begin
                if (request) begin
                    active          <= 1'b1;
                    byte_index      <= 4'd0;
                    op_latched      <= opcode;
                    len_latched     <= (length > 3'd4) ? 3'd4 : length;
                    payload_latched <= payload;
                    crc_latched     <= frame_crc(opcode, (length > 3'd4) ? 3'd4 : length, payload);
                end
            end else if (uart_ready) begin
                if (byte_index == (4 + len_latched)) begin
                    active     <= 1'b0;
                    byte_index <= 4'd0;
                end else begin
                    byte_index <= byte_index + 1'b1;
                end
            end
        end
    end
endmodule
