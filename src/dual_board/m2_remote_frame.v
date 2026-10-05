// Addressed-frame bring-up profile. File-order (including bottom-up BMP) is
// preserved with explicit addresses. CRC32 covers header, addresses and pixels.
// This profile stages a whole image; it cannot sustain 1080p60 video.
module m2_remote_frame_tx(
    input wire clk, rst_n, frame_begin, input wire [7:0] image_id,
    input wire wr_valid, input wire [20:0] wr_addr, input wire [31:0] wr_data,
    output wire wr_ready, input wire frame_done, frame_error,
    output wire out_valid, output reg [31:0] out_data, input wire out_ready,
    output wire busy);
    function [31:0] crc_word;
        input [31:0] crc, value;
        integer k; reg [31:0] c;
        begin c=crc; for(k=31;k>=0;k=k-1)
            c={c[30:0],1'b0} ^ ((c[31]^value[k]) ? 32'h04c11db7 : 32'd0);
            crc_word=c;
        end
    endfunction
    reg [2:0] state;
    reg [7:0] id;
    reg [31:0] pixel, crc;
    reg [20:0] addr;
    reg end_pending, abort_pending;
    assign busy=state!=0;
    assign wr_ready=state==2 && !end_pending && !abort_pending;
    assign out_valid=(state==1 || state==3 || state==4 || state==5 || state==6 || state==7);
    always @(*) begin
        case(state)
            1: out_data={24'hb17e00,id};
            3: out_data={11'h400,addr};
            4: out_data=pixel;
            5: out_data={24'hf17e00,id};
            6: out_data=crc;
            7: out_data=32'he17e0000;
            default: out_data=0;
        endcase
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin state<=0; id<=0; pixel<=0; addr<=0; crc<=32'hffffffff; end_pending<=0; abort_pending<=0; end
        else begin
            if(frame_done) end_pending<=1;
            if(frame_error) abort_pending<=1;
            case(state)
                0: if(frame_begin) begin id<=image_id; state<=1; crc<=32'hffffffff; end_pending<=0; abort_pending<=0; end
                1: if(out_ready) begin crc<=crc_word(crc,out_data); state<=2; end
                2: if(abort_pending) state<=7;
                   else if(end_pending) state<=5;
                   else if(wr_valid) begin addr<=wr_addr; pixel<=wr_data; state<=3; end
                3: if(out_ready) begin crc<=crc_word(crc,out_data); state<=4; end
                4: if(out_ready) begin crc<=crc_word(crc,out_data); state<=2; end
                5: if(out_ready) state<=6;
                6: if(out_ready) state<=0;
                7: if(out_ready) state<=0;
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
    input wire wr_ready, output wire busy);
    function [31:0] crc_word;
        input [31:0] crc, value;
        integer k; reg [31:0] c;
        begin c=crc; for(k=31;k>=0;k=k-1)
            c={c[30:0],1'b0} ^ ((c[31]^value[k]) ? 32'h04c11db7 : 32'd0);
            crc_word=c;
        end
    endfunction
    reg [1:0] state;
    reg [31:0] crc;
    reg [20:0] addr, count;
    assign busy=state!=0;
    assign wr_valid=in_valid && state==2;
    assign wr_addr=addr;
    assign wr_data=in_data;
    assign in_ready=(state!=2) || wr_ready;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin state<=0; crc<=32'hffffffff; addr<=0; count<=0; frame_begin<=0; frame_done<=0; frame_error<=0; image_id<=0; end
        else begin
            frame_begin<=0; frame_done<=0; frame_error<=0;
            if(in_valid && in_ready) begin
                case(state)
                    0,1: begin
                        if(in_data[31:8]==24'hb17e00) begin
                            image_id<=in_data[7:0]; count<=0;
                            crc<=crc_word(32'hffffffff,in_data); frame_begin<=1; state<=1;
                        end else if(state==1 && in_data[31:21]==11'h400 && in_data[20:0]<PIXELS && count<PIXELS) begin
                            addr<=in_data[20:0]; crc<=crc_word(crc,in_data); state<=2;
                        end else if(state==1 && in_data=={24'hf17e00,image_id} && count==PIXELS) state<=3;
                        else begin frame_error<=1; state<=0; end
                    end
                    2: begin crc<=crc_word(crc,in_data); count<=count+1'b1; state<=1; end
                    3: begin
                        if(in_data==crc) frame_done<=1; else frame_error<=1;
                        state<=0;
                    end
                endcase
            end
        end
    end
endmodule
