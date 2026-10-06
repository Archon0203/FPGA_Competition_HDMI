// COMPACT_RGB888=1 uses header B17E01xx and RGB words with upper byte 00.
// The address starts at zero and advances after every pixel. Explicit ADDR
// words occur only on discontinuities (e.g. each bottom-up BMP row). RX accepts
// both profiles; CRC still covers every transmitted word. Upgrade BOTH boards.
// Addressed-frame bring-up profile. File-order (including bottom-up BMP) is
// preserved with explicit addresses. CRC32 covers header, addresses, pixels
// and (when present) the FAT 8.3 filename + image-info metadata. This profile stages a
// whole image; it cannot sustain 1080p60 video.
//
// Backward compatibility: filename_valid=0 emits the legacy stream:
//   HEADER, {ADDR,PIXEL}*, TAIL, CRC
// With filename_valid=1 the stream is:
//   HEADER, {ADDR,PIXEL}*, "NAME", NAME[0:3], NAME[4:7], NAME[8:10]+PAD,
//   "INFO", {WIDTH,HEIGHT}, {26'd0,BPP}, TAIL, CRC
// NAME and INFO are independently optional and CRC-covered. The receiver also
// accepts the legacy no-metadata form.  Current BMP media uses RGB888/BPP=24.
module m2_remote_frame_tx #(parameter integer COMPACT_RGB888=0)(
    input wire clk, rst_n, frame_begin, input wire [7:0] image_id,
    input wire wr_valid, input wire [20:0] wr_addr, input wire [31:0] wr_data,
    output wire wr_ready, input wire frame_done, frame_error,
    output wire out_valid, output reg [31:0] out_data, input wire out_ready,
    output wire busy,
    input wire filename_valid, input wire [87:0] filename_83,
    input wire info_valid, input wire [15:0] image_width, input wire [15:0] image_height,
    input wire [5:0] image_bpp, input wire prefetch_frame);
    function [31:0] crc_word;
        input [31:0] crc, value;
        integer k; reg [31:0] c;
        begin c=crc; for(k=31;k>=0;k=k-1)
            c={c[30:0],1'b0} ^ ((c[31]^value[k]) ? 32'h04c11db7 : 32'd0);
            crc_word=c;
        end
    endfunction
    localparam [31:0] NAME_MARKER = 32'h4e414d45; // ASCII "NAME"
    localparam [31:0] INFO_MARKER = 32'h494e464f; // ASCII "INFO"
    reg [4:0] state;
    reg [7:0] id;
    reg [31:0] pixel, crc;
    reg [20:0] addr, next_addr;
    reg end_pending, abort_pending;
    reg name_pending, info_pending;
    reg [87:0] name_latched;
    reg [15:0] width_latched, height_latched;
    reg [5:0] bpp_latched;
    reg prefetch_latched;
    assign busy=state!=0;
    assign wr_ready=state==2 && !end_pending && !abort_pending;
    assign out_valid=(state!=0 && state!=2);
    always @(*) begin
        case(state)
            4'd1:  out_data=prefetch_latched ? {24'hb17e02,id} :
                             (COMPACT_RGB888 ? {24'hb17e01,id} : {24'hb17e00,id});
            4'd3:  out_data={11'h400,addr};
            4'd4:  out_data=pixel;
            4'd5:  out_data=NAME_MARKER;
            4'd6:  out_data=name_latched[87:56];
            4'd7:  out_data=name_latched[55:24];
            4'd8:  out_data={name_latched[23:0],8'h00};
            4'd9:  out_data={24'hf17e00,id};
            4'd10: out_data=crc;
            5'd11: out_data=32'he17e0000;
            5'd12: out_data=INFO_MARKER;
            5'd13: out_data={width_latched,height_latched};
            5'd14: out_data={26'd0,bpp_latched};
            default: out_data=0;
        endcase
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=0; id<=0; pixel<=0; addr<=0; next_addr<=0; crc<=32'hffffffff;
            end_pending<=0; abort_pending<=0; name_pending<=0; info_pending<=0;
            name_latched<={11{8'h20}}; width_latched<=0; height_latched<=0; bpp_latched<=0;
            prefetch_latched<=0;
        end else begin
            if(frame_done) begin
                end_pending<=1;
                // A high filename_valid opts into the extended metadata transport.
                if (filename_valid) begin
                    name_pending<=1'b1;
                    name_latched<=filename_83;
                end else begin
                    name_pending<=1'b0;
                end
                if (info_valid) begin
                    info_pending<=1'b1;
                    width_latched<=image_width;
                    height_latched<=image_height;
                    bpp_latched<=image_bpp;
                end else begin
                    info_pending<=1'b0;
                end
            end
            if(frame_error) abort_pending<=1;
            case(state)
                4'd0: if(frame_begin) begin
                    id<=image_id; state<=1; next_addr<=0; crc<=32'hffffffff;
                    end_pending<=0; abort_pending<=0; name_pending<=0; info_pending<=0;
                    name_latched<={11{8'h20}}; width_latched<=0; height_latched<=0; bpp_latched<=0;
                    prefetch_latched <= (prefetch_frame === 1'b1);
                end
                4'd1: if(out_ready) begin crc<=crc_word(crc,out_data); state<=2; end
                5'd2: if(abort_pending) state<=11;
                      else if(end_pending) state<=name_pending ? 5 : (info_pending ? 12 : 9);
                      else if(wr_valid) begin
                          addr<=wr_addr; pixel<=COMPACT_RGB888 ? {8'd0,wr_data[23:0]} : wr_data;
                          state<=(COMPACT_RGB888 && wr_addr==next_addr) ? 4 : 3;
                      end
                4'd3: if(out_ready) begin crc<=crc_word(crc,out_data); state<=4; end
                4'd4: if(out_ready) begin crc<=crc_word(crc,out_data); next_addr<=addr+1'b1; state<=2; end
                4'd5: if(out_ready) begin crc<=crc_word(crc,out_data); state<=6; end
                4'd6: if(out_ready) begin crc<=crc_word(crc,out_data); state<=7; end
                4'd7: if(out_ready) begin crc<=crc_word(crc,out_data); state<=8; end
                5'd8: if(out_ready) begin crc<=crc_word(crc,out_data); state<=info_pending ? 12 : 9; end
                5'd9: if(out_ready) state<=10;
                5'd10: if(out_ready) state<=0;
                5'd11: if(out_ready) state<=0;
                5'd12: if(out_ready) begin crc<=crc_word(crc,out_data); state<=13; end
                5'd13: if(out_ready) begin crc<=crc_word(crc,out_data); state<=14; end
                5'd14: if(out_ready) begin crc<=crc_word(crc,out_data); state<=9; end
                default: state<=0;
            endcase
        end
    end
endmodule

module m2_remote_frame_rx #(parameter integer PIXELS=307200)(
    input wire clk, rst_n,
    input wire in_valid, input wire [31:0] in_data, output wire in_ready,
    output reg frame_begin, frame_done, frame_error, output reg [7:0] image_id,
    output wire wr_valid, output wire [20:0] wr_addr, output wire [31:0] wr_data,
    input wire wr_ready, output wire busy,
    output reg filename_valid, output reg [87:0] filename_83,
    output reg info_valid, output reg [15:0] image_width, output reg [15:0] image_height,
    output reg [5:0] image_bpp, output reg frame_prefetch);
    function [31:0] crc_word;
        input [31:0] crc, value;
        integer k; reg [31:0] c;
        begin c=crc; for(k=31;k>=0;k=k-1)
            c={c[30:0],1'b0} ^ ((c[31]^value[k]) ? 32'h04c11db7 : 32'd0);
            crc_word=c;
        end
    endfunction
    localparam [31:0] NAME_MARKER = 32'h4e414d45;
    localparam [31:0] INFO_MARKER = 32'h494e464f;
    reg [4:0] state;
    reg compact;
    reg [31:0] crc;
    reg [20:0] addr, count;
    reg [87:0] name_candidate;
    reg name_present, info_present;
    reg [15:0] width_candidate, height_candidate;
    reg [5:0] bpp_candidate;
    assign busy=state!=0;
    wire compact_pixel=(state==1) && compact && in_data[31:24]==8'h00 && count<PIXELS && addr<PIXELS;
    assign wr_valid=in_valid && (state==2 || compact_pixel);
    assign wr_addr=addr;
    assign wr_data=in_data;
    assign in_ready=!(state==2 || compact_pixel) || wr_ready;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=0; compact<=0; crc<=32'hffffffff; addr<=0; count<=0; frame_prefetch<=0;
            frame_begin<=0; frame_done<=0; frame_error<=0; image_id<=0;
            filename_valid<=0; filename_83<={11{8'h20}};
            info_valid<=0; image_width<=0; image_height<=0; image_bpp<=0;
            name_candidate<={11{8'h20}}; name_present<=0; info_present<=0;
            width_candidate<=0; height_candidate<=0; bpp_candidate<=0;
        end else begin
            frame_begin<=0; frame_done<=0; frame_error<=0; filename_valid<=0; info_valid<=0;
            if(in_valid && in_ready) begin
                case(state)
                    4'd0: begin
                        if(in_data[31:8]==24'hb17e00 || in_data[31:8]==24'hb17e01 ||
                           in_data[31:8]==24'hb17e02) begin
                            image_id<=in_data[7:0]; count<=0; addr<=0;
                            compact<=(in_data[31:8]!=24'hb17e00);
                            frame_prefetch <= (in_data[31:8]==24'hb17e02);
                            crc<=crc_word(32'hffffffff,in_data);
                            name_candidate<={11{8'h20}}; name_present<=0; info_present<=0;
                            width_candidate<=0; height_candidate<=0; bpp_candidate<=0;
                            frame_begin<=1; state<=1;
                        end
                        // Idle deliberately discards complete but non-header
                        // words so one-sided reset recovery can resynchronize.
                    end
                    4'd1: begin
                        if(in_data[31:8]==24'hb17e00 || in_data[31:8]==24'hb17e01 ||
                           in_data[31:8]==24'hb17e02) begin
                            image_id<=in_data[7:0]; count<=0; addr<=0;
                            compact<=(in_data[31:8]!=24'hb17e00);
                            frame_prefetch <= (in_data[31:8]==24'hb17e02);
                            crc<=crc_word(32'hffffffff,in_data);
                            name_candidate<={11{8'h20}}; name_present<=0; info_present<=0;
                            width_candidate<=0; height_candidate<=0; bpp_candidate<=0;
                            frame_begin<=1; state<=1;
                        end else if(compact_pixel) begin
                            crc<=crc_word(crc,in_data); count<=count+1'b1; addr<=addr+1'b1;
                        end else if(in_data[31:21]==11'h400 && in_data[20:0]<PIXELS && count<PIXELS) begin
                            addr<=in_data[20:0]; crc<=crc_word(crc,in_data); state<=2;
                        end else if(in_data==NAME_MARKER && count==PIXELS) begin
                            crc<=crc_word(crc,in_data); name_present<=1; state<=4;
                        end else if(in_data==INFO_MARKER && count==PIXELS) begin
                            crc<=crc_word(crc,in_data); info_present<=1; state<=9;
                        end else if(in_data=={24'hf17e00,image_id} && count==PIXELS) begin
                            // Legacy sender without filename metadata.
                            name_present<=0; state<=8;
                        end else begin
                            frame_error<=1; state<=0;
                        end
                    end
                    4'd2: begin crc<=crc_word(crc,in_data); count<=count+1'b1; if(compact) addr<=addr+1'b1; state<=1; end
                    4'd4: begin name_candidate[87:56]<=in_data; crc<=crc_word(crc,in_data); state<=5; end
                    4'd5: begin name_candidate[55:24]<=in_data; crc<=crc_word(crc,in_data); state<=6; end
                    5'd6: begin name_candidate[23:0]<=in_data[31:8]; crc<=crc_word(crc,in_data); state<=7; end
                    5'd7: begin
                        if(in_data==INFO_MARKER) begin crc<=crc_word(crc,in_data); info_present<=1; state<=9; end
                        else if(in_data=={24'hf17e00,image_id}) state<=8;
                        else begin frame_error<=1; state<=0; end
                    end
                    4'd8: begin
                        if(in_data==crc) begin
                            frame_done<=1;
                            if(name_present) begin
                                filename_valid<=1;
                                filename_83<=name_candidate;
                            end
                            if(info_present) begin
                                info_valid<=1; image_width<=width_candidate; image_height<=height_candidate; image_bpp<=bpp_candidate;
                            end
                        end else frame_error<=1;
                        state<=0;
                    end
                    5'd9: begin width_candidate<=in_data[31:16]; height_candidate<=in_data[15:0]; crc<=crc_word(crc,in_data); state<=10; end
                    5'd10: begin bpp_candidate<=in_data[5:0]; crc<=crc_word(crc,in_data); state<=11; end
                    5'd11: begin
                        if(in_data=={24'hf17e00,image_id}) state<=8;
                        else begin frame_error<=1; state<=0; end
                    end
                    default: begin frame_error<=1; state<=0; end
                endcase
            end
        end
    end
endmodule
