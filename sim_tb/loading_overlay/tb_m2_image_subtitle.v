`timescale 1ns/1ps
module tb_m2_image_subtitle;
    reg clk=0, rst_n=0;
    reg axis_valid=0, axis_user=0, axis_last=0;
    reg [23:0] background_rgb=24'h804020;
    reg enable=0;
    reg [7:0] image_id=0;
    reg [87:0] filename_83="PIC1    BMP";
    wire [23:0] rgb;
    integer errors=0, checks=0;
    integer x,y,i;
    integer fname_count[0:11];
    integer num_count[0:2];
    integer zh_count[0:9];
    integer label_white;
    integer tx, nx, anx, fx, digits;

    always #5 clk=~clk;
    m2_image_subtitle dut(
        .clk(clk),.rst_n(rst_n),.axis_valid(axis_valid),.axis_user(axis_user),.axis_last(axis_last),
        .background_rgb(background_rgb),.enable(enable),.image_id(image_id),
        .filename_83(filename_83),.rgb(rgb));

    task expect;
        input condition; input [255:0] label;
        begin checks=checks+1; if(!condition) begin errors=errors+1; $display("ERROR: %0s",label); end end
    endtask

    task run_frame;
        begin
            for(i=0;i<12;i=i+1) fname_count[i]=0;
            for(i=0;i<3;i=i+1) num_count[i]=0;
            for(i=0;i<10;i=i+1) zh_count[i]=0;
            if(image_id>=99) begin digits=3; tx=164; end
            else if(image_id>=9) begin digits=2; tx=168; end
            else begin digits=1; tx=172; end
            nx=tx+48; anx=nx+digits*8; fx=anx+136;
            label_white=0;
            for(y=0;y<480;y=y+1) begin
                for(x=0;x<640;x=x+1) begin
                    @(negedge clk);
                    axis_valid=1;
                    axis_user=(x==0 && y==0);
                    axis_last=(x==639);
                    #1;
                    if (enable && y==451 && x==0 && rgb!==24'h804020) begin
                        $display("ERROR: row above subtitle changed rgb=%h",rgb); errors=errors+1;
                    end
                    if (enable && y==452 && x==0 && rgb!==24'h402010) begin
                        $display("ERROR: subtitle bar darkening rgb=%h",rgb); errors=errors+1;
                    end
                    if (rgb==24'hf8fafc && y>=458 && y<474) begin
                        if(x>=nx && x<nx+digits*8) num_count[(x-nx)>>3]=num_count[(x-nx)>>3]+1;
                        if(x>=fx && x<fx+96) fname_count[(x-fx)>>3]=fname_count[(x-fx)>>3]+1;
                        if(x>=tx && x<fx) label_white=label_white+1;
                        if(x>=tx && x<tx+16) zh_count[0]=zh_count[0]+1;
                        else if(x<tx+32 && x>=tx+16) zh_count[1]=zh_count[1]+1;
                        else if(x<tx+48 && x>=tx+32) zh_count[2]=zh_count[2]+1;
                        else if(x>=anx && x<anx+16) zh_count[3]=zh_count[3]+1;
                        else if(x<anx+32 && x>=anx+16) zh_count[4]=zh_count[4]+1;
                        else if(x<anx+48 && x>=anx+32) zh_count[5]=zh_count[5]+1;
                        else if(x<anx+64 && x>=anx+48) zh_count[6]=zh_count[6]+1;
                        else if(x>=anx+72 && x<anx+88) zh_count[7]=zh_count[7]+1;
                        else if(x<anx+104 && x>=anx+88) zh_count[8]=zh_count[8]+1;
                        else if(x<anx+120 && x>=anx+104) zh_count[9]=zh_count[9]+1;
                    end
                end
            end
            @(negedge clk); axis_valid=0; axis_user=0; axis_last=0;
        end
    endtask

    initial begin
        #12; rst_n=1;
        // Disabled overlay must be fully transparent.
        @(negedge clk); axis_valid=1; axis_user=1; axis_last=0; enable=0; #1;
        expect(rgb==24'h804020,"disabled subtitle is transparent");
        @(negedge clk); axis_valid=0;

        // Frame 1: 第 1 张图片 文件名:PIC1.BMP
        enable=1; image_id=0; filename_83="PIC1    BMP";
        run_frame();
        expect(label_white>100,"literal Chinese caption glyphs render");
        for(i=0;i<10;i=i+1) expect(zh_count[i]>0,"every required Chinese glyph position renders");
        expect(num_count[0]>0 && num_count[1]==0 && num_count[2]==0,"image #1 uses exactly one digit");
        for(i=0;i<8;i=i+1) expect(fname_count[i]>0,"PIC1.BMP expected filename slot renders");
        for(i=8;i<12;i=i+1) expect(fname_count[i]==0,"PIC1.BMP trailing filename slots blank");

        // Frame 2: 第 12 张图片 文件名:LONGNAME.BMP
        image_id=11; filename_83="LONGNAMEBMP";
        run_frame();
        expect(num_count[0]>0 && num_count[1]>0 && num_count[2]==0,"image #12 renders exactly two digits");
        for(i=0;i<12;i=i+1) expect(fname_count[i]>0,"LONGNAME.BMP fills all 12 filename slots");

        if(errors==0) $display("PASS: m2_image_subtitle checks=%0d",checks);
        else $display("FAIL: m2_image_subtitle errors=%0d checks=%0d",errors,checks);
        $finish;
    end
endmodule
