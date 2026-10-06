// Top-left translucent rounded image-information overlay for M2 display.
//
// Visible text (compact, no padding around the multiplication sign):
//   RES 640x480       // rendered with a multiplication-sign glyph (0xD7)
//   RGB RGB888 24bit
//
// The framebuffer path in this project accepts 24-bit BI_RGB BMP and presents
// RGB888 pixels to HDMI.  The width/height inputs are the metadata committed
// with the currently displayed image; when either is zero the module falls
// back to the active framebuffer contract (640x480).
module m2_image_info_overlay #(
    parameter integer FALLBACK_WIDTH  = 640,
    parameter integer FALLBACK_HEIGHT = 480
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        axis_valid,
    input  wire        axis_user,
    input  wire        axis_last,
    input  wire [23:0] background_rgb,
    input  wire        enable,
    input  wire [15:0] image_width,
    input  wire [15:0] image_height,
    input  wire [5:0]  image_bpp,
    output reg  [23:0] rgb
);
    localparam [9:0] BOX_X = 10'd12;
    localparam [9:0] BOX_Y = 10'd12;
    localparam [9:0] BOX_W = 10'd208;
    localparam [9:0] BOX_H = 10'd52;
    localparam [9:0] BOX_R = 10'd6;
    localparam [9:0] TEXT_X = 10'd20;
    localparam [9:0] LINE1_Y = 10'd20;
    localparam [9:0] LINE2_Y = 10'd40;
    localparam [7:0] CH_MUL = 8'hD7;

    reg [9:0] xq, yq;
    wire [9:0] x = axis_user ? 10'd0 : xq;
    wire [9:0] y = axis_user ? 10'd0 : yq;

    wire [15:0] width_eff  = (image_width  != 16'd0) ? image_width  : FALLBACK_WIDTH[15:0];
    wire [15:0] height_eff = (image_height != 16'd0) ? image_height : FALLBACK_HEIGHT[15:0];
    wire [5:0] bpp_eff = (image_bpp != 6'd0) ? image_bpp : 6'd24;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            xq <= 10'd0;
            yq <= 10'd0;
        end else if (axis_valid) begin
            if (axis_last) begin
                xq <= 10'd0;
                yq <= y + 10'd1;
            end else begin
                xq <= x + 10'd1;
                yq <= y;
            end
        end
    end

    // Metadata is formatted once in blanking, never divided on the pixel path.
    reg [15:0] width_seen, height_seen;
    reg [5:0] bpp_seen;
    reg [15:0] width_shift, height_shift, bpp_shift;
    reg [19:0] width_work, height_work, bpp_work;
    reg [19:0] width_bcd, height_bcd, bpp_bcd;
    reg [4:0] format_count;
    reg format_busy;
    function [19:0] add3;
        input [19:0] bcd;
        integer n;
        begin
            add3=bcd;
            for(n=0;n<5;n=n+1)
                if(bcd[n*4+:4]>=5) add3[n*4+:4]=bcd[n*4+:4]+4'd3;
        end
    endfunction
    function [19:0] constant_bcd;
        input integer v;
        integer n;
        begin
            constant_bcd=0;
            for(n=0;n<5;n=n+1) begin
                constant_bcd[n*4+:4]=v%10; v=v/10;
            end
        end
    endfunction
    wire [19:0] width_step={add3(width_work),width_shift[15]};
    wire [19:0] height_step={add3(height_work),height_shift[15]};
    wire [19:0] bpp_step={add3(bpp_work),bpp_shift[15]};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            width_seen<=0; height_seen<=0; bpp_seen<=0;
            width_shift<=0; height_shift<=0; bpp_shift<=0;
            width_work<=0; height_work<=0; bpp_work<=0;
            width_bcd<=constant_bcd(FALLBACK_WIDTH);
            height_bcd<=constant_bcd(FALLBACK_HEIGHT);
            bpp_bcd<=20'h00024;
            format_count<=0; format_busy<=0;
        end else if(width_eff!=width_seen || height_eff!=height_seen || bpp_eff!=bpp_seen) begin
            width_seen<=width_eff; height_seen<=height_eff; bpp_seen<=bpp_eff;
            width_shift<=width_eff; height_shift<=height_eff; bpp_shift<={10'd0,bpp_eff};
            width_work<=0; height_work<=0; bpp_work<=0;
            format_count<=0; format_busy<=1;
        end else if(format_busy) begin
            width_work<=width_step; height_work<=height_step; bpp_work<=bpp_step;
            width_shift<=width_shift<<1; height_shift<=height_shift<<1; bpp_shift<=bpp_shift<<1;
            format_count<=format_count+1'b1;
            if(format_count==15) begin
                width_bcd<=width_step; height_bcd<=height_step; bpp_bcd<=bpp_step;
                format_busy<=0;
            end
        end
    end
    function [2:0] dec_digits;
        input [19:0] value;
        begin
            if(value[19:16]!=0) dec_digits=5;
            else if(value[15:12]!=0) dec_digits=4;
            else if(value[11:8]!=0) dec_digits=3;
            else if(value[7:4]!=0) dec_digits=2;
            else dec_digits=1;
        end
    endfunction
    function [7:0] dec_compact_ascii;
        input [19:0] value;
        input [2:0] pos_from_left;
        reg [2:0] digit_index;
        reg [3:0] digit;
        begin
            digit_index=dec_digits(value)-1'b1-pos_from_left;
            case(digit_index)
                4:digit=value[19:16]; 3:digit=value[15:12];
                2:digit=value[11:8]; 1:digit=value[7:4]; default:digit=value[3:0];
            endcase
            dec_compact_ascii={4'h3,digit};
        end
    endfunction

    // Compact 5x7 font. Bit[4] is the left-most pixel.
    function [4:0] font5x7;
        input [7:0] ch;
        input [2:0] row;
        begin
            font5x7 = 5'b00000;
            case (ch)
                "0": case(row) 0:font5x7=5'b01110;1:font5x7=5'b10001;2:font5x7=5'b10011;3:font5x7=5'b10101;4:font5x7=5'b11001;5:font5x7=5'b10001;6:font5x7=5'b01110; endcase
                "1": case(row) 0:font5x7=5'b00100;1:font5x7=5'b01100;2:font5x7=5'b00100;3:font5x7=5'b00100;4:font5x7=5'b00100;5:font5x7=5'b00100;6:font5x7=5'b01110; endcase
                "2": case(row) 0:font5x7=5'b01110;1:font5x7=5'b10001;2:font5x7=5'b00001;3:font5x7=5'b00010;4:font5x7=5'b00100;5:font5x7=5'b01000;6:font5x7=5'b11111; endcase
                "3": case(row) 0:font5x7=5'b11110;1:font5x7=5'b00001;2:font5x7=5'b00001;3:font5x7=5'b01110;4:font5x7=5'b00001;5:font5x7=5'b00001;6:font5x7=5'b11110; endcase
                "4": case(row) 0:font5x7=5'b00010;1:font5x7=5'b00110;2:font5x7=5'b01010;3:font5x7=5'b10010;4:font5x7=5'b11111;5:font5x7=5'b00010;6:font5x7=5'b00010; endcase
                "5": case(row) 0:font5x7=5'b11111;1:font5x7=5'b10000;2:font5x7=5'b10000;3:font5x7=5'b11110;4:font5x7=5'b00001;5:font5x7=5'b00001;6:font5x7=5'b11110; endcase
                "6": case(row) 0:font5x7=5'b01110;1:font5x7=5'b10000;2:font5x7=5'b10000;3:font5x7=5'b11110;4:font5x7=5'b10001;5:font5x7=5'b10001;6:font5x7=5'b01110; endcase
                "7": case(row) 0:font5x7=5'b11111;1:font5x7=5'b00001;2:font5x7=5'b00010;3:font5x7=5'b00100;4:font5x7=5'b01000;5:font5x7=5'b01000;6:font5x7=5'b01000; endcase
                "8": case(row) 0:font5x7=5'b01110;1:font5x7=5'b10001;2:font5x7=5'b10001;3:font5x7=5'b01110;4:font5x7=5'b10001;5:font5x7=5'b10001;6:font5x7=5'b01110; endcase
                "9": case(row) 0:font5x7=5'b01110;1:font5x7=5'b10001;2:font5x7=5'b10001;3:font5x7=5'b01111;4:font5x7=5'b00001;5:font5x7=5'b00001;6:font5x7=5'b01110; endcase
                "R": case(row) 0:font5x7=5'b11110;1:font5x7=5'b10001;2:font5x7=5'b10001;3:font5x7=5'b11110;4:font5x7=5'b10100;5:font5x7=5'b10010;6:font5x7=5'b10001; endcase
                "E": case(row) 0:font5x7=5'b11111;1:font5x7=5'b10000;2:font5x7=5'b10000;3:font5x7=5'b11110;4:font5x7=5'b10000;5:font5x7=5'b10000;6:font5x7=5'b11111; endcase
                "S": case(row) 0:font5x7=5'b01111;1:font5x7=5'b10000;2:font5x7=5'b10000;3:font5x7=5'b01110;4:font5x7=5'b00001;5:font5x7=5'b00001;6:font5x7=5'b11110; endcase
                "G": case(row) 0:font5x7=5'b01110;1:font5x7=5'b10001;2:font5x7=5'b10000;3:font5x7=5'b10111;4:font5x7=5'b10001;5:font5x7=5'b10001;6:font5x7=5'b01110; endcase
                "B": case(row) 0:font5x7=5'b11110;1:font5x7=5'b10001;2:font5x7=5'b10001;3:font5x7=5'b11110;4:font5x7=5'b10001;5:font5x7=5'b10001;6:font5x7=5'b11110; endcase
                // Lower-case glyphs requested for the unit suffix "bit".
                "b": case(row) 0:font5x7=5'b10000;1:font5x7=5'b10000;2:font5x7=5'b11110;3:font5x7=5'b10001;4:font5x7=5'b10001;5:font5x7=5'b10001;6:font5x7=5'b11110; endcase
                "i": case(row) 0:font5x7=5'b00100;1:font5x7=5'b00000;2:font5x7=5'b01100;3:font5x7=5'b00100;4:font5x7=5'b00100;5:font5x7=5'b00100;6:font5x7=5'b01110; endcase
                "t": case(row) 0:font5x7=5'b00100;1:font5x7=5'b00100;2:font5x7=5'b11111;3:font5x7=5'b00100;4:font5x7=5'b00100;5:font5x7=5'b00101;6:font5x7=5'b00010; endcase
                // Multiplication sign (U+00D7 encoded as 8'hD7 in the local font).
                8'hD7: case(row) 0:font5x7=5'b00000;1:font5x7=5'b10001;2:font5x7=5'b01010;3:font5x7=5'b00100;4:font5x7=5'b01010;5:font5x7=5'b10001;6:font5x7=5'b00000; endcase
                default: font5x7=5'b00000;
            endcase
        end
    endfunction

    function [7:0] line1_char;
        input [4:0] idx;
        reg [2:0] wdigits, hdigits;
        reg [4:0] mul_idx, h_start;
        begin
            // Exact compact form: "RES <width>x<height>" where x is rendered
            // as a multiplication-sign glyph and sits directly between digits.
            wdigits = dec_digits(width_bcd);
            hdigits = dec_digits(height_bcd);
            mul_idx = 4 + wdigits;
            h_start = mul_idx + 1'b1;
            line1_char = 8'h20;
            if (idx==0) line1_char="R";
            else if (idx==1) line1_char="E";
            else if (idx==2) line1_char="S";
            else if (idx>=4 && idx<mul_idx)
                line1_char=dec_compact_ascii(width_bcd,idx-4);
            else if (idx==mul_idx)
                line1_char=CH_MUL;
            else if (idx>=h_start && idx<(h_start+hdigits))
                line1_char=dec_compact_ascii(height_bcd,idx-h_start);
        end
    endfunction

    function [7:0] line2_char;
        input [4:0] idx;
        begin
            // "RGB RGB888 24bit" -- lower-case unit suffix by request.
            case(idx)
                0: line2_char="R"; 1: line2_char="G"; 2: line2_char="B";
                3: line2_char=" ";
                4: line2_char="R"; 5: line2_char="G"; 6: line2_char="B";
                7: line2_char="8"; 8: line2_char="8"; 9: line2_char="8";
                10:line2_char=" ";
                11:line2_char = (bpp_bcd[7:4]!=0) ? {4'h3,bpp_bcd[7:4]} : 8'h20;
                12:line2_char = {4'h3,bpp_bcd[3:0]};
                13:line2_char="b"; 14:line2_char="i"; 15:line2_char="t";
                default: line2_char=" ";
            endcase
        end
    endfunction

    // Rounded-rectangle hit test. Corners are quarter circles of radius r.
    function rounded_hit;
        input [9:0] px;
        input [9:0] py;
        input [9:0] left;
        input [9:0] top;
        input [9:0] width;
        input [9:0] height;
        input [9:0] radius;
        reg [9:0] cx, cy;
        reg [2:0] dx, dy;
        reg [6:0] d2;
        integer right_edge, bottom_edge;
        begin
            right_edge = left + width - 1;
            bottom_edge = top + height - 1;
            rounded_hit = 1'b0;
            if ((px >= left) && (px <= right_edge) &&
                (py >= top)  && (py <= bottom_edge)) begin
                if ((px >= left+radius) && (px <= right_edge-radius))
                    rounded_hit = 1'b1;
                else if ((py >= top+radius) && (py <= bottom_edge-radius))
                    rounded_hit = 1'b1;
                else begin
                    cx = (px < left+radius) ? (left+radius) : (right_edge-radius);
                    cy = (py < top+radius)  ? (top+radius)  : (bottom_edge-radius);
                    dx = (px>cx) ? px-cx : cx-px;
                    dy = (py>cy) ? py-cy : cy-py;
                    d2 = dx*dx + dy*dy;
                    rounded_hit = (d2 <= (radius==6 ? 36 : 25));
                end
            end
        end
    endfunction

    reg [7:0] ch;
    reg [4:0] glyph;
    reg [4:0] char_idx;
    reg [3:0] cell_x;
    reg [2:0] glyph_row;
    reg text_on;
    reg in_box;
    reg in_inner_box;
    reg on_border;
    reg [7:0] r_dim, g_dim, b_dim;
    reg [7:0] r_lite, g_lite, b_lite;

    always @(*) begin
        in_box = enable && rounded_hit(x,y,BOX_X,BOX_Y,BOX_W,BOX_H,BOX_R);
        in_inner_box = enable && rounded_hit(x,y,BOX_X+1'b1,BOX_Y+1'b1,
                                            BOX_W-2'd2,BOX_H-2'd2,BOX_R-1'b1);
        on_border = in_box && !in_inner_box;
        text_on = 1'b0;
        ch = 8'h20;
        glyph = 5'b00000;
        char_idx = 5'd0;
        cell_x = 4'd0;
        glyph_row = 3'd0;

        // Each glyph is 5x7 doubled to 10x14 with a 2-pixel cell gap.
        if (enable && x>=TEXT_X && x<TEXT_X+10'd192 && y>=LINE1_Y && y<LINE1_Y+10'd14) begin
            char_idx = (x-TEXT_X) / 12;
            cell_x = (x-TEXT_X) % 12;
            glyph_row = (y-LINE1_Y) >> 1;
            ch = line1_char(char_idx);
            glyph = font5x7(ch,glyph_row);
            if (cell_x < 10)
                text_on = glyph[4-(cell_x>>1)];
        end else if (enable && x>=TEXT_X && x<TEXT_X+10'd192 && y>=LINE2_Y && y<LINE2_Y+10'd14) begin
            char_idx = (x-TEXT_X) / 12;
            cell_x = (x-TEXT_X) % 12;
            glyph_row = (y-LINE2_Y) >> 1;
            ch = line2_char(char_idx);
            glyph = font5x7(ch,glyph_row);
            if (cell_x < 10)
                text_on = glyph[4-(cell_x>>1)];
        end

        // 50% black translucent fill. The 50% white rounded border is also
        // blended with the underlying image, while text remains crisp white.
        r_dim = background_rgb[23:16] >> 1;
        g_dim = background_rgb[15:8]  >> 1;
        b_dim = background_rgb[7:0]   >> 1;
        r_lite = (background_rgb[23:16] >> 1) + 8'd127;
        g_lite = (background_rgb[15:8]  >> 1) + 8'd127;
        b_lite = (background_rgb[7:0]   >> 1) + 8'd127;

        rgb = background_rgb;
        if (in_box)
            rgb = on_border ? {r_lite,g_lite,b_lite} : {r_dim,g_dim,b_dim};
        if (text_on)
            rgb = 24'hF8FAFC;
    end
endmodule
