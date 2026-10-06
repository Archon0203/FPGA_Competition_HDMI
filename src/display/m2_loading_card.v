// Small procedural loading card. No framebuffer or multiplier required.
// Coordinates consume the same registered AXIS raster as APUG092.
module m2_loading_card(input wire clk, input wire rst_n,
    input wire axis_valid, input wire axis_user, input wire axis_last,
    input wire [23:0] background_rgb,
    input wire overlay_only, input wire card_missing,
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
    reg [7:0] error_index;
    reg [4:0] error_x;
    reg error_area;
    reg [23:0] error_glyph_row;
    integer ci;

    always @(*) begin
        error_index=0; error_x=0; error_area=0;
        for(ci=0;ci<7;ci=ci+1)
            if(x>=222+ci*28 && x<246+ci*28 && y>=224 && y<252) begin
                error_index=ci*28+y-224; error_x=x-(222+ci*28); error_area=1;
            end
        case(error_index)
            8'd0: error_glyph_row=24'h000000;
            8'd1: error_glyph_row=24'h000000;
            8'd2: error_glyph_row=24'h000000;
            8'd3: error_glyph_row=24'h000000;
            8'd4: error_glyph_row=24'h004000;
            8'd5: error_glyph_row=24'h004000;
            8'd6: error_glyph_row=24'h004000;
            8'd7: error_glyph_row=24'h004000;
            8'd8: error_glyph_row=24'h7fffc0;
            8'd9: error_glyph_row=24'h004000;
            8'd10: error_glyph_row=24'h004000;
            8'd11: error_glyph_row=24'h004000;
            8'd12: error_glyph_row=24'h004000;
            8'd13: error_glyph_row=24'hffffe0;
            8'd14: error_glyph_row=24'h00e000;
            8'd15: error_glyph_row=24'h01f000;
            8'd16: error_glyph_row=24'h035000;
            8'd17: error_glyph_row=24'h064800;
            8'd18: error_glyph_row=24'h0c4600;
            8'd19: error_glyph_row=24'h184300;
            8'd20: error_glyph_row=24'h6041c0;
            8'd21: error_glyph_row=24'hc04060;
            8'd22: error_glyph_row=24'h004000;
            8'd23: error_glyph_row=24'h004000;
            8'd24: error_glyph_row=24'h000000;
            8'd25: error_glyph_row=24'h000000;
            8'd26: error_glyph_row=24'h000000;
            8'd27: error_glyph_row=24'h000000;
            8'd28: error_glyph_row=24'h000000;
            8'd29: error_glyph_row=24'h000000;
            8'd30: error_glyph_row=24'h000000;
            8'd31: error_glyph_row=24'h000000;
            8'd32: error_glyph_row=24'h000000;
            8'd33: error_glyph_row=24'h200000;
            8'd34: error_glyph_row=24'h10ffe0;
            8'd35: error_glyph_row=24'h0c8020;
            8'd36: error_glyph_row=24'h048020;
            8'd37: error_glyph_row=24'h008020;
            8'd38: error_glyph_row=24'h008020;
            8'd39: error_glyph_row=24'hf08020;
            8'd40: error_glyph_row=24'h108020;
            8'd41: error_glyph_row=24'h108020;
            8'd42: error_glyph_row=24'h10ffe0;
            8'd43: error_glyph_row=24'h108020;
            8'd44: error_glyph_row=24'h100000;
            8'd45: error_glyph_row=24'h112200;
            8'd46: error_glyph_row=24'h174100;
            8'd47: error_glyph_row=24'h1ec080;
            8'd48: error_glyph_row=24'h390060;
            8'd49: error_glyph_row=24'h120030;
            8'd50: error_glyph_row=24'h040010;
            8'd51: error_glyph_row=24'h000000;
            8'd52: error_glyph_row=24'h000000;
            8'd53: error_glyph_row=24'h000000;
            8'd54: error_glyph_row=24'h000000;
            8'd55: error_glyph_row=24'h000000;
            8'd56: error_glyph_row=24'h000000;
            8'd57: error_glyph_row=24'h000000;
            8'd58: error_glyph_row=24'h000000;
            8'd59: error_glyph_row=24'h000000;
            8'd60: error_glyph_row=24'h000000;
            8'd61: error_glyph_row=24'h000040;
            8'd62: error_glyph_row=24'h3fc040;
            8'd63: error_glyph_row=24'h204440;
            8'd64: error_glyph_row=24'h204440;
            8'd65: error_glyph_row=24'h204440;
            8'd66: error_glyph_row=24'h3fc440;
            8'd67: error_glyph_row=24'h204440;
            8'd68: error_glyph_row=24'h080440;
            8'd69: error_glyph_row=24'h080440;
            8'd70: error_glyph_row=24'h7fc440;
            8'd71: error_glyph_row=24'h084440;
            8'd72: error_glyph_row=24'h084440;
            8'd73: error_glyph_row=24'h084440;
            8'd74: error_glyph_row=24'h184040;
            8'd75: error_glyph_row=24'h104040;
            8'd76: error_glyph_row=24'h304040;
            8'd77: error_glyph_row=24'h2f8780;
            8'd78: error_glyph_row=24'h600000;
            8'd79: error_glyph_row=24'h000000;
            8'd80: error_glyph_row=24'h000000;
            8'd81: error_glyph_row=24'h000000;
            8'd82: error_glyph_row=24'h000000;
            8'd83: error_glyph_row=24'h000000;
            8'd84: error_glyph_row=24'h000000;
            8'd85: error_glyph_row=24'h000000;
            8'd86: error_glyph_row=24'h000000;
            8'd87: error_glyph_row=24'h000000;
            8'd88: error_glyph_row=24'h000000;
            8'd89: error_glyph_row=24'h000040;
            8'd90: error_glyph_row=24'hfff040;
            8'd91: error_glyph_row=24'h0c0440;
            8'd92: error_glyph_row=24'h090440;
            8'd93: error_glyph_row=24'h198440;
            8'd94: error_glyph_row=24'h308440;
            8'd95: error_glyph_row=24'h20c440;
            8'd96: error_glyph_row=24'h7fe440;
            8'd97: error_glyph_row=24'h002440;
            8'd98: error_glyph_row=24'h040440;
            8'd99: error_glyph_row=24'h040440;
            8'd100: error_glyph_row=24'h7fe440;
            8'd101: error_glyph_row=24'h040440;
            8'd102: error_glyph_row=24'h040440;
            8'd103: error_glyph_row=24'h040040;
            8'd104: error_glyph_row=24'h047040;
            8'd105: error_glyph_row=24'h1f8040;
            8'd106: error_glyph_row=24'he00780;
            8'd107: error_glyph_row=24'h000000;
            8'd108: error_glyph_row=24'h000000;
            8'd109: error_glyph_row=24'h000000;
            8'd110: error_glyph_row=24'h000000;
            8'd111: error_glyph_row=24'h000000;
            8'd112: error_glyph_row=24'h000000;
            8'd113: error_glyph_row=24'h000000;
            8'd114: error_glyph_row=24'h000000;
            8'd115: error_glyph_row=24'h000000;
            8'd116: error_glyph_row=24'h000000;
            8'd117: error_glyph_row=24'h000000;
            8'd118: error_glyph_row=24'h7fe000;
            8'd119: error_glyph_row=24'h7fe000;
            8'd120: error_glyph_row=24'h060000;
            8'd121: error_glyph_row=24'h060000;
            8'd122: error_glyph_row=24'h060000;
            8'd123: error_glyph_row=24'h060000;
            8'd124: error_glyph_row=24'h060000;
            8'd125: error_glyph_row=24'h060000;
            8'd126: error_glyph_row=24'h060000;
            8'd127: error_glyph_row=24'h060000;
            8'd128: error_glyph_row=24'h060000;
            8'd129: error_glyph_row=24'h060000;
            8'd130: error_glyph_row=24'h060000;
            8'd131: error_glyph_row=24'h060000;
            8'd132: error_glyph_row=24'h060000;
            8'd133: error_glyph_row=24'h000000;
            8'd134: error_glyph_row=24'h000000;
            8'd135: error_glyph_row=24'h000000;
            8'd136: error_glyph_row=24'h000000;
            8'd137: error_glyph_row=24'h000000;
            8'd138: error_glyph_row=24'h000000;
            8'd139: error_glyph_row=24'h000000;
            8'd140: error_glyph_row=24'h000000;
            8'd141: error_glyph_row=24'h000000;
            8'd142: error_glyph_row=24'h000000;
            8'd143: error_glyph_row=24'h000000;
            8'd144: error_glyph_row=24'h000000;
            8'd145: error_glyph_row=24'h000000;
            8'd146: error_glyph_row=24'h3fc000;
            8'd147: error_glyph_row=24'h3fc000;
            8'd148: error_glyph_row=24'h300000;
            8'd149: error_glyph_row=24'h300000;
            8'd150: error_glyph_row=24'h300000;
            8'd151: error_glyph_row=24'h300000;
            8'd152: error_glyph_row=24'h300000;
            8'd153: error_glyph_row=24'h3fc000;
            8'd154: error_glyph_row=24'h3fc000;
            8'd155: error_glyph_row=24'h300000;
            8'd156: error_glyph_row=24'h300000;
            8'd157: error_glyph_row=24'h300000;
            8'd158: error_glyph_row=24'h300000;
            8'd159: error_glyph_row=24'h300000;
            8'd160: error_glyph_row=24'h300000;
            8'd161: error_glyph_row=24'h000000;
            8'd162: error_glyph_row=24'h000000;
            8'd163: error_glyph_row=24'h000000;
            8'd164: error_glyph_row=24'h000000;
            8'd165: error_glyph_row=24'h000000;
            8'd166: error_glyph_row=24'h000000;
            8'd167: error_glyph_row=24'h000000;
            8'd168: error_glyph_row=24'h000000;
            8'd169: error_glyph_row=24'h000000;
            8'd170: error_glyph_row=24'h000000;
            8'd171: error_glyph_row=24'h000000;
            8'd172: error_glyph_row=24'h000000;
            8'd173: error_glyph_row=24'h008000;
            8'd174: error_glyph_row=24'h008000;
            8'd175: error_glyph_row=24'h00ffc0;
            8'd176: error_glyph_row=24'h008000;
            8'd177: error_glyph_row=24'h008000;
            8'd178: error_glyph_row=24'h008000;
            8'd179: error_glyph_row=24'h008000;
            8'd180: error_glyph_row=24'h7fffe0;
            8'd181: error_glyph_row=24'h000000;
            8'd182: error_glyph_row=24'h008000;
            8'd183: error_glyph_row=24'h00e000;
            8'd184: error_glyph_row=24'h00f000;
            8'd185: error_glyph_row=24'h009c00;
            8'd186: error_glyph_row=24'h008600;
            8'd187: error_glyph_row=24'h008180;
            8'd188: error_glyph_row=24'h0080c0;
            8'd189: error_glyph_row=24'h008000;
            8'd190: error_glyph_row=24'h008000;
            8'd191: error_glyph_row=24'h000000;
            8'd192: error_glyph_row=24'h000000;
            8'd193: error_glyph_row=24'h000000;
            8'd194: error_glyph_row=24'h000000;
            8'd195: error_glyph_row=24'h000000;
            default:error_glyph_row=0;
        endcase
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
        // Standalone mode keeps the original full-screen loading page.
        // Overlay mode is transparent outside the center card so the
        // previously committed framebuffer remains visible underneath.
        rgb = overlay_only ? background_rgb : 24'h101827;
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
        if (x>=((card_missing===1'b1) ? 160 : 200)+inset && x<((card_missing===1'b1) ? 480 : 440)-inset && y>=192 && y<288)
            rgb=24'h25354d;
        if(card_missing===1'b1) begin
            if(error_area && error_glyph_row[23-error_x]) rgb=24'hf1f5f9;
        end else if (glyph_area && glyph_row[23-glyph_x]) rgb=24'hf1f5f9;
        if (y>=266 && y<270 && x>=296 && x<344) rgb=(card_missing===1'b1) ? 24'hf59e0b : 24'h38bdf8;
    end
endmodule
