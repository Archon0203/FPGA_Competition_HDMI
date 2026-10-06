// Bottom subtitle overlay for committed M2 images.
// Format: 这是第N张图片，文件名是 XXXXXXXX.EXT
// The current project catalog parses FAT 8.3 short names, so filename_83 is
// the exact 11-byte short-directory name (8-byte base + 3-byte extension).
module m2_image_subtitle(
    input wire clk, input wire rst_n,
    input wire axis_valid, input wire axis_user, input wire axis_last,
    input wire [23:0] background_rgb,
    input wire enable,
    input wire [7:0] image_id,
    input wire [87:0] filename_83,
    output reg [23:0] rgb);

    localparam [9:0] BAR_Y  = 10'd452;
    localparam [9:0] TEXT_Y = 10'd458;

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

    function [7:0] raw_name_byte;
        input [3:0] idx;
        begin
            case(idx)
                0: raw_name_byte=filename_83[87:80];
                1: raw_name_byte=filename_83[79:72];
                2: raw_name_byte=filename_83[71:64];
                3: raw_name_byte=filename_83[63:56];
                4: raw_name_byte=filename_83[55:48];
                5: raw_name_byte=filename_83[47:40];
                6: raw_name_byte=filename_83[39:32];
                7: raw_name_byte=filename_83[31:24];
                8: raw_name_byte=filename_83[23:16];
                9: raw_name_byte=filename_83[15:8];
                10: raw_name_byte=filename_83[7:0];
                default: raw_name_byte=8'h20;
            endcase
        end
    endfunction

    function [7:0] ascii_row;
        input [7:0] ch; input [3:0] row;
        begin
            ascii_row=8'h00;
            case ({ch,row})
                12'h213: ascii_row=8'h30;
                12'h214: ascii_row=8'h30;
                12'h215: ascii_row=8'h30;
                12'h216: ascii_row=8'h30;
                12'h217: ascii_row=8'h10;
                12'h218: ascii_row=8'h10;
                12'h219: ascii_row=8'h10;
                12'h21b: ascii_row=8'h38;
                12'h21c: ascii_row=8'h30;
                12'h233: ascii_row=8'h04;
                12'h234: ascii_row=8'h34;
                12'h235: ascii_row=8'h24;
                12'h236: ascii_row=8'h7e;
                12'h237: ascii_row=8'h2c;
                12'h238: ascii_row=8'h2c;
                12'h239: ascii_row=8'hfe;
                12'h23a: ascii_row=8'h6c;
                12'h23b: ascii_row=8'h68;
                12'h23c: ascii_row=8'h68;
                12'h242: ascii_row=8'h18;
                12'h243: ascii_row=8'h18;
                12'h244: ascii_row=8'h7c;
                12'h245: ascii_row=8'h64;
                12'h246: ascii_row=8'h60;
                12'h247: ascii_row=8'h38;
                12'h248: ascii_row=8'h1c;
                12'h249: ascii_row=8'h06;
                12'h24a: ascii_row=8'h46;
                12'h24b: ascii_row=8'h7e;
                12'h24c: ascii_row=8'h7c;
                12'h24d: ascii_row=8'h18;
                12'h253: ascii_row=8'h84;
                12'h254: ascii_row=8'hcc;
                12'h255: ascii_row=8'h48;
                12'h256: ascii_row=8'h58;
                12'h257: ascii_row=8'hd7;
                12'h258: ascii_row=8'hb5;
                12'h259: ascii_row=8'h2c;
                12'h25a: ascii_row=8'h6c;
                12'h25b: ascii_row=8'h45;
                12'h25c: ascii_row=8'hc7;
                12'h263: ascii_row=8'h78;
                12'h264: ascii_row=8'h78;
                12'h265: ascii_row=8'h48;
                12'h266: ascii_row=8'h78;
                12'h267: ascii_row=8'h71;
                12'h268: ascii_row=8'hf3;
                12'h269: ascii_row=8'hdf;
                12'h26a: ascii_row=8'h9e;
                12'h26b: ascii_row=8'hff;
                12'h26c: ascii_row=8'h7b;
                12'h273: ascii_row=8'h18;
                12'h274: ascii_row=8'h18;
                12'h275: ascii_row=8'h18;
                12'h276: ascii_row=8'h18;
                12'h277: ascii_row=8'h08;
                12'h281: ascii_row=8'h08;
                12'h282: ascii_row=8'h18;
                12'h283: ascii_row=8'h18;
                12'h284: ascii_row=8'h30;
                12'h285: ascii_row=8'h30;
                12'h286: ascii_row=8'h30;
                12'h287: ascii_row=8'h30;
                12'h288: ascii_row=8'h30;
                12'h289: ascii_row=8'h30;
                12'h28a: ascii_row=8'h30;
                12'h28b: ascii_row=8'h10;
                12'h28c: ascii_row=8'h18;
                12'h28d: ascii_row=8'h18;
                12'h291: ascii_row=8'h20;
                12'h292: ascii_row=8'h30;
                12'h293: ascii_row=8'h30;
                12'h294: ascii_row=8'h10;
                12'h295: ascii_row=8'h18;
                12'h296: ascii_row=8'h18;
                12'h297: ascii_row=8'h18;
                12'h298: ascii_row=8'h18;
                12'h299: ascii_row=8'h18;
                12'h29a: ascii_row=8'h18;
                12'h29b: ascii_row=8'h10;
                12'h29c: ascii_row=8'h30;
                12'h29d: ascii_row=8'h20;
                12'h2b4: ascii_row=8'h18;
                12'h2b5: ascii_row=8'h18;
                12'h2b6: ascii_row=8'h18;
                12'h2b7: ascii_row=8'hfe;
                12'h2b8: ascii_row=8'h18;
                12'h2b9: ascii_row=8'h18;
                12'h2ba: ascii_row=8'h18;
                12'h2d6: ascii_row=8'h38;
                12'h2e7: ascii_row=8'h18;
                12'h2e8: ascii_row=8'h18;
                12'h303: ascii_row=8'h3c;
                12'h304: ascii_row=8'h7c;
                12'h305: ascii_row=8'h66;
                12'h306: ascii_row=8'h66;
                12'h307: ascii_row=8'he6;
                12'h308: ascii_row=8'he6;
                12'h309: ascii_row=8'h66;
                12'h30a: ascii_row=8'h66;
                12'h30b: ascii_row=8'h7c;
                12'h30c: ascii_row=8'h38;
                12'h313: ascii_row=8'h38;
                12'h314: ascii_row=8'h78;
                12'h315: ascii_row=8'h18;
                12'h316: ascii_row=8'h18;
                12'h317: ascii_row=8'h18;
                12'h318: ascii_row=8'h18;
                12'h319: ascii_row=8'h18;
                12'h31a: ascii_row=8'h18;
                12'h31b: ascii_row=8'h7e;
                12'h31c: ascii_row=8'h7e;
                12'h323: ascii_row=8'h38;
                12'h324: ascii_row=8'h7c;
                12'h325: ascii_row=8'h0e;
                12'h326: ascii_row=8'h0e;
                12'h327: ascii_row=8'h0c;
                12'h328: ascii_row=8'h0c;
                12'h329: ascii_row=8'h18;
                12'h32a: ascii_row=8'h30;
                12'h32b: ascii_row=8'h7e;
                12'h32c: ascii_row=8'hfe;
                12'h333: ascii_row=8'h7c;
                12'h334: ascii_row=8'h7c;
                12'h335: ascii_row=8'h0e;
                12'h336: ascii_row=8'h0c;
                12'h337: ascii_row=8'h38;
                12'h338: ascii_row=8'h1c;
                12'h339: ascii_row=8'h06;
                12'h33a: ascii_row=8'h06;
                12'h33b: ascii_row=8'hfe;
                12'h33c: ascii_row=8'h7c;
                12'h343: ascii_row=8'h1c;
                12'h344: ascii_row=8'h1c;
                12'h345: ascii_row=8'h3c;
                12'h346: ascii_row=8'h3c;
                12'h347: ascii_row=8'h6c;
                12'h348: ascii_row=8'h6c;
                12'h349: ascii_row=8'hfe;
                12'h34a: ascii_row=8'h7e;
                12'h34b: ascii_row=8'h0c;
                12'h34c: ascii_row=8'h0c;
                12'h353: ascii_row=8'h7e;
                12'h354: ascii_row=8'h7c;
                12'h355: ascii_row=8'h60;
                12'h356: ascii_row=8'h60;
                12'h357: ascii_row=8'h7c;
                12'h358: ascii_row=8'h0e;
                12'h359: ascii_row=8'h06;
                12'h35a: ascii_row=8'h06;
                12'h35b: ascii_row=8'hfc;
                12'h35c: ascii_row=8'h7c;
                12'h363: ascii_row=8'h1c;
                12'h364: ascii_row=8'h3e;
                12'h365: ascii_row=8'h60;
                12'h366: ascii_row=8'h60;
                12'h367: ascii_row=8'h7c;
                12'h368: ascii_row=8'h66;
                12'h369: ascii_row=8'h66;
                12'h36a: ascii_row=8'h66;
                12'h36b: ascii_row=8'h7e;
                12'h36c: ascii_row=8'h3c;
                12'h373: ascii_row=8'h7e;
                12'h374: ascii_row=8'h7e;
                12'h375: ascii_row=8'h0c;
                12'h376: ascii_row=8'h0c;
                12'h377: ascii_row=8'h18;
                12'h378: ascii_row=8'h18;
                12'h379: ascii_row=8'h18;
                12'h37a: ascii_row=8'h18;
                12'h37b: ascii_row=8'h38;
                12'h37c: ascii_row=8'h30;
                12'h383: ascii_row=8'h3c;
                12'h384: ascii_row=8'h7e;
                12'h385: ascii_row=8'h66;
                12'h386: ascii_row=8'h66;
                12'h387: ascii_row=8'h3c;
                12'h388: ascii_row=8'h7c;
                12'h389: ascii_row=8'h66;
                12'h38a: ascii_row=8'h66;
                12'h38b: ascii_row=8'h7e;
                12'h38c: ascii_row=8'h3c;
                12'h393: ascii_row=8'h38;
                12'h394: ascii_row=8'h7c;
                12'h395: ascii_row=8'h66;
                12'h396: ascii_row=8'hc6;
                12'h397: ascii_row=8'h66;
                12'h398: ascii_row=8'h7e;
                12'h399: ascii_row=8'h06;
                12'h39a: ascii_row=8'h06;
                12'h39b: ascii_row=8'h7c;
                12'h39c: ascii_row=8'h78;
                12'h401: ascii_row=8'h7e;
                12'h402: ascii_row=8'he7;
                12'h403: ascii_row=8'h81;
                12'h404: ascii_row=8'h3c;
                12'h405: ascii_row=8'h6c;
                12'h406: ascii_row=8'h6c;
                12'h407: ascii_row=8'h4c;
                12'h408: ascii_row=8'h6d;
                12'h409: ascii_row=8'h7f;
                12'h40b: ascii_row=8'hc0;
                12'h40c: ascii_row=8'hfc;
                12'h413: ascii_row=8'h1c;
                12'h414: ascii_row=8'h3c;
                12'h415: ascii_row=8'h3c;
                12'h416: ascii_row=8'h34;
                12'h417: ascii_row=8'h26;
                12'h418: ascii_row=8'h66;
                12'h419: ascii_row=8'h7e;
                12'h41a: ascii_row=8'h7f;
                12'h41b: ascii_row=8'hc3;
                12'h41c: ascii_row=8'hc3;
                12'h423: ascii_row=8'hfc;
                12'h424: ascii_row=8'hfe;
                12'h425: ascii_row=8'hc6;
                12'h426: ascii_row=8'hce;
                12'h427: ascii_row=8'hfc;
                12'h428: ascii_row=8'hfe;
                12'h429: ascii_row=8'hc6;
                12'h42a: ascii_row=8'hc6;
                12'h42b: ascii_row=8'hfe;
                12'h42c: ascii_row=8'hfc;
                12'h433: ascii_row=8'h3c;
                12'h434: ascii_row=8'h7e;
                12'h435: ascii_row=8'he0;
                12'h436: ascii_row=8'hc0;
                12'h437: ascii_row=8'hc0;
                12'h438: ascii_row=8'hc0;
                12'h439: ascii_row=8'hc0;
                12'h43a: ascii_row=8'he0;
                12'h43b: ascii_row=8'h7e;
                12'h43c: ascii_row=8'h3c;
                12'h443: ascii_row=8'hf8;
                12'h444: ascii_row=8'hfe;
                12'h445: ascii_row=8'hc6;
                12'h446: ascii_row=8'hc6;
                12'h447: ascii_row=8'hc7;
                12'h448: ascii_row=8'hc7;
                12'h449: ascii_row=8'hc6;
                12'h44a: ascii_row=8'hc6;
                12'h44b: ascii_row=8'hfe;
                12'h44c: ascii_row=8'hf8;
                12'h453: ascii_row=8'h7e;
                12'h454: ascii_row=8'h7e;
                12'h455: ascii_row=8'h60;
                12'h456: ascii_row=8'h60;
                12'h457: ascii_row=8'h7e;
                12'h458: ascii_row=8'h7c;
                12'h459: ascii_row=8'h60;
                12'h45a: ascii_row=8'h60;
                12'h45b: ascii_row=8'h7e;
                12'h45c: ascii_row=8'h7e;
                12'h463: ascii_row=8'h7e;
                12'h464: ascii_row=8'h7e;
                12'h465: ascii_row=8'h60;
                12'h466: ascii_row=8'h60;
                12'h467: ascii_row=8'h7c;
                12'h468: ascii_row=8'h7e;
                12'h469: ascii_row=8'h60;
                12'h46a: ascii_row=8'h60;
                12'h46b: ascii_row=8'h60;
                12'h46c: ascii_row=8'h60;
                12'h473: ascii_row=8'h3c;
                12'h474: ascii_row=8'h7e;
                12'h475: ascii_row=8'he0;
                12'h476: ascii_row=8'hc0;
                12'h477: ascii_row=8'hce;
                12'h478: ascii_row=8'hcf;
                12'h479: ascii_row=8'hc3;
                12'h47a: ascii_row=8'he3;
                12'h47b: ascii_row=8'h7f;
                12'h47c: ascii_row=8'h3e;
                12'h483: ascii_row=8'hc3;
                12'h484: ascii_row=8'hc3;
                12'h485: ascii_row=8'hc3;
                12'h486: ascii_row=8'hc3;
                12'h487: ascii_row=8'hff;
                12'h488: ascii_row=8'hff;
                12'h489: ascii_row=8'hc3;
                12'h48a: ascii_row=8'hc3;
                12'h48b: ascii_row=8'hc3;
                12'h48c: ascii_row=8'hc3;
                12'h493: ascii_row=8'h18;
                12'h494: ascii_row=8'h18;
                12'h495: ascii_row=8'h18;
                12'h496: ascii_row=8'h18;
                12'h497: ascii_row=8'h18;
                12'h498: ascii_row=8'h18;
                12'h499: ascii_row=8'h18;
                12'h49a: ascii_row=8'h18;
                12'h49b: ascii_row=8'h18;
                12'h49c: ascii_row=8'h18;
                12'h4a3: ascii_row=8'h0c;
                12'h4a4: ascii_row=8'h0c;
                12'h4a5: ascii_row=8'h0c;
                12'h4a6: ascii_row=8'h0c;
                12'h4a7: ascii_row=8'h0c;
                12'h4a8: ascii_row=8'h0c;
                12'h4a9: ascii_row=8'h0c;
                12'h4aa: ascii_row=8'h4c;
                12'h4ab: ascii_row=8'hfc;
                12'h4ac: ascii_row=8'h78;
                12'h4b3: ascii_row=8'hc6;
                12'h4b4: ascii_row=8'hcc;
                12'h4b5: ascii_row=8'hdc;
                12'h4b6: ascii_row=8'hd8;
                12'h4b7: ascii_row=8'hf8;
                12'h4b8: ascii_row=8'hfc;
                12'h4b9: ascii_row=8'hec;
                12'h4ba: ascii_row=8'hce;
                12'h4bb: ascii_row=8'hc6;
                12'h4bc: ascii_row=8'hc7;
                12'h4c3: ascii_row=8'h60;
                12'h4c4: ascii_row=8'h60;
                12'h4c5: ascii_row=8'h60;
                12'h4c6: ascii_row=8'h60;
                12'h4c7: ascii_row=8'h60;
                12'h4c8: ascii_row=8'h60;
                12'h4c9: ascii_row=8'h60;
                12'h4ca: ascii_row=8'h60;
                12'h4cb: ascii_row=8'h7e;
                12'h4cc: ascii_row=8'h7e;
                12'h4d3: ascii_row=8'hc7;
                12'h4d4: ascii_row=8'hc7;
                12'h4d5: ascii_row=8'hc7;
                12'h4d6: ascii_row=8'hef;
                12'h4d7: ascii_row=8'hef;
                12'h4d8: ascii_row=8'hab;
                12'h4d9: ascii_row=8'hbb;
                12'h4da: ascii_row=8'hbb;
                12'h4db: ascii_row=8'h93;
                12'h4dc: ascii_row=8'h83;
                12'h4e3: ascii_row=8'he3;
                12'h4e4: ascii_row=8'he3;
                12'h4e5: ascii_row=8'hf3;
                12'h4e6: ascii_row=8'hf3;
                12'h4e7: ascii_row=8'hdb;
                12'h4e8: ascii_row=8'hdb;
                12'h4e9: ascii_row=8'hcf;
                12'h4ea: ascii_row=8'hcf;
                12'h4eb: ascii_row=8'hc7;
                12'h4ec: ascii_row=8'hc7;
                12'h4f3: ascii_row=8'h3c;
                12'h4f4: ascii_row=8'h7e;
                12'h4f5: ascii_row=8'he7;
                12'h4f6: ascii_row=8'hc3;
                12'h4f7: ascii_row=8'hc3;
                12'h4f8: ascii_row=8'hc3;
                12'h4f9: ascii_row=8'hc3;
                12'h4fa: ascii_row=8'he7;
                12'h4fb: ascii_row=8'h7e;
                12'h4fc: ascii_row=8'h3c;
                12'h503: ascii_row=8'hfc;
                12'h504: ascii_row=8'hfe;
                12'h505: ascii_row=8'hc6;
                12'h506: ascii_row=8'hc6;
                12'h507: ascii_row=8'hce;
                12'h508: ascii_row=8'hfc;
                12'h509: ascii_row=8'hf8;
                12'h50a: ascii_row=8'hc0;
                12'h50b: ascii_row=8'hc0;
                12'h50c: ascii_row=8'hc0;
                12'h511: ascii_row=8'h3c;
                12'h512: ascii_row=8'h7e;
                12'h513: ascii_row=8'he7;
                12'h514: ascii_row=8'hc3;
                12'h515: ascii_row=8'hc3;
                12'h516: ascii_row=8'hc3;
                12'h517: ascii_row=8'hc3;
                12'h518: ascii_row=8'hc3;
                12'h519: ascii_row=8'h7e;
                12'h51a: ascii_row=8'h3c;
                12'h51b: ascii_row=8'h1c;
                12'h51c: ascii_row=8'h0f;
                12'h51d: ascii_row=8'h03;
                12'h523: ascii_row=8'hfc;
                12'h524: ascii_row=8'hfe;
                12'h525: ascii_row=8'hc6;
                12'h526: ascii_row=8'hc6;
                12'h527: ascii_row=8'hfe;
                12'h528: ascii_row=8'hfc;
                12'h529: ascii_row=8'hcc;
                12'h52a: ascii_row=8'hcc;
                12'h52b: ascii_row=8'hc6;
                12'h52c: ascii_row=8'hc6;
                12'h533: ascii_row=8'h3c;
                12'h534: ascii_row=8'h7e;
                12'h535: ascii_row=8'h60;
                12'h536: ascii_row=8'h70;
                12'h537: ascii_row=8'h3c;
                12'h538: ascii_row=8'h1e;
                12'h539: ascii_row=8'h07;
                12'h53a: ascii_row=8'h47;
                12'h53b: ascii_row=8'h7e;
                12'h53c: ascii_row=8'h3c;
                12'h543: ascii_row=8'hff;
                12'h544: ascii_row=8'hff;
                12'h545: ascii_row=8'h18;
                12'h546: ascii_row=8'h18;
                12'h547: ascii_row=8'h18;
                12'h548: ascii_row=8'h18;
                12'h549: ascii_row=8'h18;
                12'h54a: ascii_row=8'h18;
                12'h54b: ascii_row=8'h18;
                12'h54c: ascii_row=8'h18;
                12'h553: ascii_row=8'hc3;
                12'h554: ascii_row=8'hc3;
                12'h555: ascii_row=8'hc3;
                12'h556: ascii_row=8'hc3;
                12'h557: ascii_row=8'hc3;
                12'h558: ascii_row=8'hc3;
                12'h559: ascii_row=8'hc3;
                12'h55a: ascii_row=8'he6;
                12'h55b: ascii_row=8'h7e;
                12'h55c: ascii_row=8'h3c;
                12'h563: ascii_row=8'hc3;
                12'h564: ascii_row=8'hc3;
                12'h565: ascii_row=8'h66;
                12'h566: ascii_row=8'h66;
                12'h567: ascii_row=8'h66;
                12'h568: ascii_row=8'h66;
                12'h569: ascii_row=8'h3c;
                12'h56a: ascii_row=8'h3c;
                12'h56b: ascii_row=8'h3c;
                12'h56c: ascii_row=8'h18;
                12'h573: ascii_row=8'h18;
                12'h574: ascii_row=8'h99;
                12'h575: ascii_row=8'hbd;
                12'h576: ascii_row=8'hbd;
                12'h577: ascii_row=8'hbd;
                12'h578: ascii_row=8'hbd;
                12'h579: ascii_row=8'he7;
                12'h57a: ascii_row=8'he7;
                12'h57b: ascii_row=8'he7;
                12'h57c: ascii_row=8'he7;
                12'h583: ascii_row=8'he7;
                12'h584: ascii_row=8'h66;
                12'h585: ascii_row=8'h36;
                12'h586: ascii_row=8'h3c;
                12'h587: ascii_row=8'h1c;
                12'h588: ascii_row=8'h3c;
                12'h589: ascii_row=8'h3c;
                12'h58a: ascii_row=8'h6e;
                12'h58b: ascii_row=8'h66;
                12'h58c: ascii_row=8'he7;
                12'h593: ascii_row=8'hc7;
                12'h594: ascii_row=8'he6;
                12'h595: ascii_row=8'h66;
                12'h596: ascii_row=8'h6c;
                12'h597: ascii_row=8'h3c;
                12'h598: ascii_row=8'h38;
                12'h599: ascii_row=8'h18;
                12'h59a: ascii_row=8'h18;
                12'h59b: ascii_row=8'h18;
                12'h59c: ascii_row=8'h18;
                12'h5a3: ascii_row=8'h7f;
                12'h5a4: ascii_row=8'h7e;
                12'h5a5: ascii_row=8'h0e;
                12'h5a6: ascii_row=8'h0c;
                12'h5a7: ascii_row=8'h18;
                12'h5a8: ascii_row=8'h38;
                12'h5a9: ascii_row=8'h30;
                12'h5aa: ascii_row=8'h70;
                12'h5ab: ascii_row=8'h7e;
                12'h5ac: ascii_row=8'hff;
                12'h5e3: ascii_row=8'h18;
                12'h5e4: ascii_row=8'h38;
                12'h5e5: ascii_row=8'h3c;
                12'h5e6: ascii_row=8'h2c;
                12'h5e7: ascii_row=8'h64;
                12'h5e8: ascii_row=8'h66;
                12'h5f8: ascii_row=8'hfe;
                12'h602: ascii_row=8'h20;
                12'h603: ascii_row=8'h30;
                12'h604: ascii_row=8'h18;
                12'h7b2: ascii_row=8'h18;
                12'h7b3: ascii_row=8'h10;
                12'h7b4: ascii_row=8'h10;
                12'h7b5: ascii_row=8'h10;
                12'h7b6: ascii_row=8'h30;
                12'h7b7: ascii_row=8'h70;
                12'h7b8: ascii_row=8'h30;
                12'h7b9: ascii_row=8'h10;
                12'h7ba: ascii_row=8'h10;
                12'h7bb: ascii_row=8'h30;
                12'h7bc: ascii_row=8'h10;
                12'h7bd: ascii_row=8'h18;
                12'h7d2: ascii_row=8'h70;
                12'h7d3: ascii_row=8'h30;
                12'h7d4: ascii_row=8'h10;
                12'h7d5: ascii_row=8'h10;
                12'h7d6: ascii_row=8'h18;
                12'h7d7: ascii_row=8'h1c;
                12'h7d8: ascii_row=8'h18;
                12'h7d9: ascii_row=8'h10;
                12'h7da: ascii_row=8'h10;
                12'h7db: ascii_row=8'h10;
                12'h7dc: ascii_row=8'h30;
                12'h7dd: ascii_row=8'h70;
                12'h7e5: ascii_row=8'h72;
                12'h7e6: ascii_row=8'h7e;
                default: ascii_row=8'h00;
            endcase
        end
    endfunction

    // glyph: 0=这 1=是 2=第 3=张 4=图 5=片 6=， 7=文 8=件 9=名
    function [15:0] zh_row;
        input [3:0] glyph; input [3:0] row;
        begin
            zh_row=16'h0000;
            case ({glyph,row})
                8'h00: zh_row=16'h00c0;
                8'h01: zh_row=16'h60c0;
                8'h02: zh_row=16'h7ffc;
                8'h03: zh_row=16'h3ffc;
                8'h04: zh_row=16'h0030;
                8'h05: zh_row=16'h0730;
                8'h06: zh_row=16'h73f0;
                8'h07: zh_row=16'h71e0;
                8'h08: zh_row=16'h30e0;
                8'h09: zh_row=16'h33f8;
                8'h0a: zh_row=16'h3f1c;
                8'h0b: zh_row=16'h3608;
                8'h0c: zh_row=16'h7c00;
                8'h0d: zh_row=16'hfffc;
                8'h0e: zh_row=16'h43fc;
                8'h11: zh_row=16'h3ff8;
                8'h12: zh_row=16'h3018;
                8'h13: zh_row=16'h3ff8;
                8'h14: zh_row=16'h3018;
                8'h15: zh_row=16'h3ff8;
                8'h17: zh_row=16'h7ffc;
                8'h18: zh_row=16'h7ffc;
                8'h19: zh_row=16'h1980;
                8'h1a: zh_row=16'h39f8;
                8'h1b: zh_row=16'h39f8;
                8'h1c: zh_row=16'h7f80;
                8'h1d: zh_row=16'he7fe;
                8'h1e: zh_row=16'h41fc;
                8'h20: zh_row=16'h3060;
                8'h21: zh_row=16'h3ffe;
                8'h22: zh_row=16'h7df8;
                8'h23: zh_row=16'h6d98;
                8'h24: zh_row=16'h3ff8;
                8'h25: zh_row=16'h3ff8;
                8'h26: zh_row=16'h0318;
                8'h27: zh_row=16'h3ff8;
                8'h28: zh_row=16'h3ff8;
                8'h29: zh_row=16'h3ff8;
                8'h2a: zh_row=16'h3ffc;
                8'h2b: zh_row=16'h0f0c;
                8'h2c: zh_row=16'h1f1c;
                8'h2d: zh_row=16'h7b78;
                8'h2e: zh_row=16'h6330;
                8'h30: zh_row=16'h7980;
                8'h31: zh_row=16'h7d8c;
                8'h32: zh_row=16'h0d98;
                8'h33: zh_row=16'h0db8;
                8'h34: zh_row=16'h7df0;
                8'h35: zh_row=16'h7da0;
                8'h36: zh_row=16'h63fe;
                8'h37: zh_row=16'h63fc;
                8'h38: zh_row=16'h7db0;
                8'h39: zh_row=16'h7db0;
                8'h3a: zh_row=16'h0d98;
                8'h3b: zh_row=16'h0d98;
                8'h3c: zh_row=16'h19fc;
                8'h3d: zh_row=16'h7bee;
                8'h3e: zh_row=16'h7984;
                8'h40: zh_row=16'h7ffc;
                8'h41: zh_row=16'h7ffc;
                8'h42: zh_row=16'h620c;
                8'h43: zh_row=16'h670c;
                8'h44: zh_row=16'h6fec;
                8'h45: zh_row=16'h7eec;
                8'h46: zh_row=16'h67cc;
                8'h47: zh_row=16'h7ffc;
                8'h48: zh_row=16'h7e7c;
                8'h49: zh_row=16'h63cc;
                8'h4a: zh_row=16'h668c;
                8'h4b: zh_row=16'h6fec;
                8'h4c: zh_row=16'h60ec;
                8'h4d: zh_row=16'h7ffc;
                8'h4e: zh_row=16'h7ffc;
                8'h50: zh_row=16'h30c0;
                8'h51: zh_row=16'h30c0;
                8'h52: zh_row=16'h30c0;
                8'h53: zh_row=16'h30c0;
                8'h54: zh_row=16'h3ffc;
                8'h55: zh_row=16'h3ffc;
                8'h56: zh_row=16'h3000;
                8'h57: zh_row=16'h3000;
                8'h58: zh_row=16'h3ff0;
                8'h59: zh_row=16'h3ff0;
                8'h5a: zh_row=16'h3030;
                8'h5b: zh_row=16'h7030;
                8'h5c: zh_row=16'h6030;
                8'h5d: zh_row=16'he030;
                8'h5e: zh_row=16'h4030;
                8'h65: zh_row=16'h1800;
                8'h66: zh_row=16'h1c00;
                8'h67: zh_row=16'h1c00;
                8'h68: zh_row=16'h0c00;
                8'h69: zh_row=16'h1800;
                8'h6a: zh_row=16'h1000;
                8'h71: zh_row=16'h0300;
                8'h72: zh_row=16'h0380;
                8'h73: zh_row=16'h0180;
                8'h74: zh_row=16'h7ffe;
                8'h75: zh_row=16'h7ffc;
                8'h76: zh_row=16'h1830;
                8'h77: zh_row=16'h0c60;
                8'h78: zh_row=16'h0c60;
                8'h79: zh_row=16'h06c0;
                8'h7a: zh_row=16'h07c0;
                8'h7b: zh_row=16'h0380;
                8'h7c: zh_row=16'h0fe0;
                8'h7d: zh_row=16'h3ef8;
                8'h7e: zh_row=16'hf83e;
                8'h7f: zh_row=16'h600c;
                8'h80: zh_row=16'h1860;
                8'h81: zh_row=16'h1b60;
                8'h82: zh_row=16'h3b60;
                8'h83: zh_row=16'h33fc;
                8'h84: zh_row=16'h77fc;
                8'h85: zh_row=16'h7660;
                8'h86: zh_row=16'hf460;
                8'h87: zh_row=16'h7060;
                8'h88: zh_row=16'h37fe;
                8'h89: zh_row=16'h37fc;
                8'h8a: zh_row=16'h3060;
                8'h8b: zh_row=16'h3060;
                8'h8c: zh_row=16'h3060;
                8'h8d: zh_row=16'h3060;
                8'h8e: zh_row=16'h3060;
                8'h91: zh_row=16'h0700;
                8'h92: zh_row=16'h0ff0;
                8'h93: zh_row=16'h1ff8;
                8'h94: zh_row=16'h7830;
                8'h95: zh_row=16'h7060;
                8'h96: zh_row=16'h0ce0;
                8'h97: zh_row=16'h0fc0;
                8'h98: zh_row=16'h0780;
                8'h99: zh_row=16'h3ff8;
                8'h9a: zh_row=16'h7ff8;
                8'h9b: zh_row=16'h5818;
                8'h9c: zh_row=16'h1818;
                8'h9d: zh_row=16'h1ff8;
                8'h9e: zh_row=16'h1ff8;
                8'h9f: zh_row=16'h1818;
                default: zh_row=16'h0000;
            endcase
        end
    endfunction

    reg [3:0] base_len;
    reg [8:0] image_num;
    reg [7:0] num_hundreds, num_tens, num_ones;
    integer rem10;
    reg [1:0] digit_count;
    reg [1:0] num_slot;
    reg [9:0] text_x, num_x, after_num_x, filename_x, text_end_x;
    reg [7:0] text_char;
    reg [3:0] zh_sel;
    reg is_ascii, is_zh;
    reg [3:0] text_row;
    reg [3:0] cell_col;
    reg [3:0] file_slot;
    reg [3:0] ext_slot;
    reg text_dot;
    reg [7:0] ascii_bits;
    reg [15:0] zh_bits;
    reg [23:0] dark_bg;

    always @(*) begin
        // Trim spaces at the end of the 8-byte FAT base name.
        if (raw_name_byte(7)!=8'h20) base_len=8;
        else if (raw_name_byte(6)!=8'h20) base_len=7;
        else if (raw_name_byte(5)!=8'h20) base_len=6;
        else if (raw_name_byte(4)!=8'h20) base_len=5;
        else if (raw_name_byte(3)!=8'h20) base_len=4;
        else if (raw_name_byte(2)!=8'h20) base_len=3;
        else if (raw_name_byte(1)!=8'h20) base_len=2;
        else if (raw_name_byte(0)!=8'h20) base_len=1;
        else base_len=0;

        image_num = {1'b0,image_id} + 9'd1;
        num_hundreds=8'h20; num_tens=8'h20; num_ones=8'h30;
        if (image_num >= 200) begin num_hundreds=8'h32; rem10=image_num-200; end
        else if (image_num >= 100) begin num_hundreds=8'h31; rem10=image_num-100; end
        else rem10=image_num;
        if (rem10 >= 90) begin num_tens=8'h39; rem10=rem10-90; end
        else if (rem10 >= 80) begin num_tens=8'h38; rem10=rem10-80; end
        else if (rem10 >= 70) begin num_tens=8'h37; rem10=rem10-70; end
        else if (rem10 >= 60) begin num_tens=8'h36; rem10=rem10-60; end
        else if (rem10 >= 50) begin num_tens=8'h35; rem10=rem10-50; end
        else if (rem10 >= 40) begin num_tens=8'h34; rem10=rem10-40; end
        else if (rem10 >= 30) begin num_tens=8'h33; rem10=rem10-30; end
        else if (rem10 >= 20) begin num_tens=8'h32; rem10=rem10-20; end
        else if (rem10 >= 10) begin num_tens=8'h31; rem10=rem10-10; end
        num_ones=8'h30+rem10[7:0];

        if (image_num >= 100) begin digit_count=3; text_x=10'd164; end
        else if (image_num >= 10) begin digit_count=2; text_x=10'd168; end
        else begin digit_count=1; text_x=10'd172; end
        num_x=text_x+10'd48;                 // 这是第
        after_num_x=num_x+(digit_count*8);   // N
        filename_x=after_num_x+10'd136;      // 张图片， + gap + 文件名是 + gap
        text_end_x=filename_x+10'd96;

        dark_bg={1'b0,background_rgb[23:17],1'b0,background_rgb[15:9],1'b0,background_rgb[7:1]};
        rgb=background_rgb;
        if (enable && y>=BAR_Y && y<10'd480) rgb=dark_bg;

        text_char=8'h20; zh_sel=0; is_ascii=0; is_zh=0; text_dot=0;
        text_row=0; cell_col=0; file_slot=0; ext_slot=0; num_slot=0;
        ascii_bits=8'h00; zh_bits=16'h0000;
        if (enable && y>=TEXT_Y && y<TEXT_Y+16 && x>=text_x && x<text_end_x) begin
            text_row=y-TEXT_Y;
            if (x<text_x+16) begin is_zh=1; zh_sel=0; cell_col=x-text_x; end            // 这
            else if (x<text_x+32) begin is_zh=1; zh_sel=1; cell_col=x-(text_x+16); end // 是
            else if (x<text_x+48) begin is_zh=1; zh_sel=2; cell_col=x-(text_x+32); end // 第
            else if (x<after_num_x) begin
                is_ascii=1; num_slot=(x-num_x)>>3; cell_col=(x-num_x)&7;
                if (digit_count==1) text_char=num_ones;
                else if (digit_count==2) text_char=(num_slot==0)?num_tens:num_ones;
                else if (num_slot==0) text_char=num_hundreds;
                else if (num_slot==1) text_char=num_tens;
                else text_char=num_ones;
            end
            else if (x<after_num_x+16) begin is_zh=1; zh_sel=3; cell_col=x-after_num_x; end       // 张
            else if (x<after_num_x+32) begin is_zh=1; zh_sel=4; cell_col=x-(after_num_x+16); end  // 图
            else if (x<after_num_x+48) begin is_zh=1; zh_sel=5; cell_col=x-(after_num_x+32); end  // 片
            else if (x<after_num_x+64) begin is_zh=1; zh_sel=6; cell_col=x-(after_num_x+48); end  // ，
            // 8 px gap: after_num_x+64 .. +71
            else if (x>=after_num_x+72 && x<after_num_x+88) begin is_zh=1; zh_sel=7; cell_col=x-(after_num_x+72); end  // 文
            else if (x<after_num_x+104 && x>=after_num_x+88) begin is_zh=1; zh_sel=8; cell_col=x-(after_num_x+88); end // 件
            else if (x<after_num_x+120 && x>=after_num_x+104) begin is_zh=1; zh_sel=9; cell_col=x-(after_num_x+104); end // 名
            else if (x<after_num_x+136 && x>=after_num_x+120) begin is_zh=1; zh_sel=1; cell_col=x-(after_num_x+120); end // 是
            // filename_x equals after_num_x+136. The leading spacing is
            // represented by the right side bearing of the Chinese glyph.
            else if (x>=filename_x && x<filename_x+96) begin
                is_ascii=1; file_slot=(x-filename_x)>>3; cell_col=(x-filename_x)&7;
                if (file_slot < base_len) text_char=raw_name_byte(file_slot);
                else if (file_slot == base_len) text_char=8'h2e;
                else if (file_slot > base_len && file_slot <= base_len+3) begin
                    ext_slot=file_slot-base_len-1;
                    text_char=raw_name_byte(8+ext_slot);
                end else text_char=8'h20;
            end
            zh_bits=zh_row(zh_sel,text_row);
            ascii_bits=ascii_row(text_char,text_row);
            if (is_zh && zh_bits[15-cell_col]) text_dot=1;
            if (is_ascii && ascii_bits[7-cell_col]) text_dot=1;
            if (text_dot) rgb=24'hf8fafc;
        end
    end
endmodule
