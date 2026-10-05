// Small procedural loading card. No framebuffer or multiplier required.
// Coordinates consume the same registered AXIS raster as APUG092.
module m2_loading_card(input wire clk, input wire rst_n,
    input wire axis_valid, input wire axis_user, input wire axis_last,
    output reg [23:0] rgb);
    reg [9:0] xq, yq;
    wire [9:0] x = axis_user ? 10'd0 : xq;
    wire [9:0] y = axis_user ? 10'd0 : yq;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin xq<=0; yq<=0; end
        else if (axis_valid) begin
            if (axis_last) begin xq<=0; yq<=y+1'b1; end
            else begin xq<=x+1'b1; yq<=y; end
        end
    end
    reg [6:0] glyph_index;
    reg [4:0] glyph_x;
    reg glyph_area;
    reg [23:0] glyph_row;
    reg [3:0] corner_row, inset;
    always @(*) begin
        glyph_index=0; glyph_x=0; glyph_area=0;
        if (y>=224 && y<252) begin
            if (x>=276 && x<300) begin glyph_index=y-224; glyph_x=x-276; glyph_area=1; end
            else if (x>=308 && x<332) begin glyph_index=28+y-224; glyph_x=x-308; glyph_area=1; end
            else if (x>=340 && x<364) begin glyph_index=56+y-224; glyph_x=x-340; glyph_area=1; end
        end
        case (glyph_index)
            7'd0: glyph_row = 24'h000000;
            7'd1: glyph_row = 24'h000000;
            7'd2: glyph_row = 24'h0c0000;
            7'd3: glyph_row = 24'h0c0000;
            7'd4: glyph_row = 24'h0c03fe;
            7'd5: glyph_row = 24'h7fe3fe;
            7'd6: glyph_row = 24'h7fe306;
            7'd7: glyph_row = 24'h0c6306;
            7'd8: glyph_row = 24'h0c6306;
            7'd9: glyph_row = 24'h0c6306;
            7'd10: glyph_row = 24'h0c6306;
            7'd11: glyph_row = 24'h0c6306;
            7'd12: glyph_row = 24'h0c6306;
            7'd13: glyph_row = 24'h0c6306;
            7'd14: glyph_row = 24'h0c6306;
            7'd15: glyph_row = 24'h1c6306;
            7'd16: glyph_row = 24'h186306;
            7'd17: glyph_row = 24'h186306;
            7'd18: glyph_row = 24'h386306;
            7'd19: glyph_row = 24'h306306;
            7'd20: glyph_row = 24'h7063fe;
            7'd21: glyph_row = 24'h6063fe;
            7'd22: glyph_row = 24'he7e306;
            7'd23: glyph_row = 24'h47c306;
            7'd24: glyph_row = 24'h000000;
            7'd25: glyph_row = 24'h000000;
            7'd26: glyph_row = 24'h000000;
            7'd27: glyph_row = 24'h000000;
            7'd28: glyph_row = 24'h000000;
            7'd29: glyph_row = 24'h000000;
            7'd30: glyph_row = 24'h030300;
            7'd31: glyph_row = 24'h030310;
            7'd32: glyph_row = 24'h030338;
            7'd33: glyph_row = 24'h3ffb0e;
            7'd34: glyph_row = 24'h030304;
            7'd35: glyph_row = 24'h030300;
            7'd36: glyph_row = 24'h7fffff;
            7'd37: glyph_row = 24'h030300;
            7'd38: glyph_row = 24'h070300;
            7'd39: glyph_row = 24'h060108;
            7'd40: glyph_row = 24'h7ff99c;
            7'd41: glyph_row = 24'h0c0198;
            7'd42: glyph_row = 24'h198198;
            7'd43: glyph_row = 24'h1981b0;
            7'd44: glyph_row = 24'h3181b0;
            7'd45: glyph_row = 24'h3ff8e0;
            7'd46: glyph_row = 24'h0180c0;
            7'd47: glyph_row = 24'h0181c2;
            7'd48: glyph_row = 24'h01f9e3;
            7'd49: glyph_row = 24'h7d8363;
            7'd50: glyph_row = 24'h018636;
            7'd51: glyph_row = 24'h019c3e;
            7'd52: glyph_row = 24'h01980c;
            7'd53: glyph_row = 24'h000000;
            7'd54: glyph_row = 24'h000000;
            7'd55: glyph_row = 24'h000000;
            7'd56: glyph_row = 24'h000000;
            7'd57: glyph_row = 24'h000000;
            7'd58: glyph_row = 24'h001800;
            7'd59: glyph_row = 24'h001800;
            7'd60: glyph_row = 24'h001800;
            7'd61: glyph_row = 24'h001800;
            7'd62: glyph_row = 24'h3ffffc;
            7'd63: glyph_row = 24'h3ffffc;
            7'd64: glyph_row = 24'h30180c;
            7'd65: glyph_row = 24'h30180c;
            7'd66: glyph_row = 24'h30180c;
            7'd67: glyph_row = 24'h30180c;
            7'd68: glyph_row = 24'h30180c;
            7'd69: glyph_row = 24'h30180c;
            7'd70: glyph_row = 24'h3ffffc;
            7'd71: glyph_row = 24'h3ffffc;
            7'd72: glyph_row = 24'h30180c;
            7'd73: glyph_row = 24'h001800;
            7'd74: glyph_row = 24'h001800;
            7'd75: glyph_row = 24'h001800;
            7'd76: glyph_row = 24'h001800;
            7'd77: glyph_row = 24'h001800;
            7'd78: glyph_row = 24'h001800;
            7'd79: glyph_row = 24'h001800;
            7'd80: glyph_row = 24'h000000;
            7'd81: glyph_row = 24'h000000;
            7'd82: glyph_row = 24'h000000;
            7'd83: glyph_row = 24'h000000;
            default: glyph_row=0;
        endcase
        rgb=24'h101827;
        // Radius-12 circle sampled by row; no multipliers or framebuffer.
        corner_row=12;
        if(y>=192 && y<204) corner_row=y-192;
        else if(y>=276 && y<288) corner_row=287-y;
        case(corner_row)
            0: inset=9;
            1: inset=7;
            2: inset=5;
            3: inset=4;
            4: inset=3;
            5,6: inset=2;
            7,8: inset=1;
            default: inset=0;
        endcase
        if (x>=200+inset && x<440-inset && y>=192 && y<288)
            rgb=24'h25354d;
        if (glyph_area && glyph_row[23-glyph_x]) rgb=24'hf1f5f9;
        if (y>=266 && y<270 && x>=296 && x<344) rgb=24'h38bdf8;
    end
endmodule
