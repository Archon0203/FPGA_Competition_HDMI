// Conservative eight-digit board display. The active-low select assumption
// matches the supplied HX4S20C examples; status is shown on the right digit.
module db_hex_display (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] status,
    input  wire [7:0] count,
    output reg  [7:0] seg_data,
    output reg  [7:0] seg_sel
);
    reg [15:0] div;
    reg [2:0] digit;
    reg [3:0] nibble;
    reg [11:0] count_bcd;
    integer i;

    function [7:0] hex7;
        input [3:0] n;
        begin
            case (n)
                4'h0: hex7 = 8'hc0; 4'h1: hex7 = 8'hf9;
                4'h2: hex7 = 8'ha4; 4'h3: hex7 = 8'hb0;
                4'h4: hex7 = 8'h99; 4'h5: hex7 = 8'h92;
                4'h6: hex7 = 8'h82; 4'h7: hex7 = 8'hf8;
                4'h8: hex7 = 8'h80; 4'h9: hex7 = 8'h90;
                4'ha: hex7 = 8'h88; 4'hb: hex7 = 8'h83;
                4'hc: hex7 = 8'hc6; 4'hd: hex7 = 8'ha1;
                4'he: hex7 = 8'h86; default: hex7 = 8'h8e;
            endcase
        end
    endfunction

    // Convert the binary frame/request counter to three decimal digits. The
    // shift-add-3 implementation avoids inferred division/modulo hardware.
    always @* begin
        count_bcd = 12'd0;
        for (i = 7; i >= 0; i = i - 1) begin
            if (count_bcd[3:0] >= 5)  count_bcd[3:0]  = count_bcd[3:0]  + 3;
            if (count_bcd[7:4] >= 5)  count_bcd[7:4]  = count_bcd[7:4]  + 3;
            if (count_bcd[11:8] >= 5) count_bcd[11:8] = count_bcd[11:8] + 3;
            count_bcd = {count_bcd[10:0], count[i]};
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div <= 16'd0;
            digit <= 3'd0;
        end else if (div == 16'd4999) begin
            div <= 16'd0;
            digit <= (digit == 3'd7) ? 3'd0 : digit + 1'b1;
        end else begin
            div <= div + 1'b1;
        end
    end

    always @* begin
        seg_sel = 8'b11111111;
        seg_sel[digit] = 1'b0;
        case (digit)
            3'd0: nibble = status[3:0];
            3'd1: nibble = status[7:4];
            3'd2: nibble = count_bcd[3:0];
            3'd3: nibble = count_bcd[7:4];
            3'd4: nibble = count_bcd[11:8];
            default: nibble = 4'h0;
        endcase
        seg_data = hex7(nibble);
    end
endmodule
