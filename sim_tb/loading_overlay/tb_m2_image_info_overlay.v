`timescale 1ns/1ps
module tb_m2_image_info_overlay;
    reg clk=0, rst_n=0;
    reg axis_valid=0, axis_user=0, axis_last=0;
    reg [23:0] background_rgb=24'h804020;
    reg enable=0;
    reg [15:0] image_width=16'd640, image_height=16'd480;
    reg [5:0] image_bpp=6'd24;
    wire [23:0] rgb;
    integer x,y;
    integer errors=0, checks=0;
    integer white_l1=0, white_l2=0;
    integer box_changed=0, outside_changed=0;
    integer rounded_corner_leaks=0;

    always #5 clk=~clk;
    m2_image_info_overlay dut(
        .clk(clk),.rst_n(rst_n),.axis_valid(axis_valid),.axis_user(axis_user),.axis_last(axis_last),
        .background_rgb(background_rgb),.enable(enable),
        .image_width(image_width),.image_height(image_height),.image_bpp(image_bpp),.rgb(rgb));

    task expect;
        input condition; input [383:0] label;
        begin checks=checks+1; if(!condition) begin errors=errors+1; $display("ERROR: %0s",label); end end
    endtask

    task check_640_text_contract;
        begin
            expect(dut.line1_char(0)=="R" && dut.line1_char(1)=="E" && dut.line1_char(2)=="S", "RES prefix");
            expect(dut.line1_char(3)==" ", "single space after RES");
            expect(dut.line1_char(4)=="6" && dut.line1_char(5)=="4" && dut.line1_char(6)=="0", "width is compact 640");
            expect(dut.line1_char(7)==8'hD7, "multiplication sign is directly after width");
            expect(dut.line1_char(8)=="4" && dut.line1_char(9)=="8" && dut.line1_char(10)=="0", "height is directly after multiplication sign");
            expect(dut.line1_char(11)==" ", "no stale padded height characters");
            expect(dut.line2_char(11)=="2" && dut.line2_char(12)=="4", "24-bit numeric field");
            expect(dut.line2_char(13)=="b" && dut.line2_char(14)=="i" && dut.line2_char(15)=="t", "bit suffix is lower-case");
            expect(dut.font5x7(8'hD7,3)!=5'b00000, "multiplication-sign glyph exists");
            expect(dut.font5x7("b",3)!=5'b00000 && dut.font5x7("i",3)!=5'b00000 && dut.font5x7("t",3)!=5'b00000, "lower-case bit glyphs exist");
        end
    endtask

    task check_1920_text_contract;
        begin
            expect(dut.line1_char(4)=="1" && dut.line1_char(5)=="9" && dut.line1_char(6)=="2" && dut.line1_char(7)=="0", "width is compact 1920");
            expect(dut.line1_char(8)==8'hD7, "1920 multiplication sign position");
            expect(dut.line1_char(9)=="1" && dut.line1_char(10)=="0" && dut.line1_char(11)=="8" && dut.line1_char(12)=="0", "height is compact 1080");
            expect(dut.line1_char(13)==" ", "1920x1080 has no trailing padded digits");
        end
    endtask

    task run_frame;
        begin
            white_l1=0; white_l2=0; box_changed=0; outside_changed=0; rounded_corner_leaks=0;
            for(y=0;y<480;y=y+1) begin
                for(x=0;x<640;x=x+1) begin
                    @(negedge clk);
                    axis_valid=1; axis_user=(x==0 && y==0); axis_last=(x==639);
                    #1;
                    if (x>=12 && x<220 && y>=12 && y<64) begin
                        if(rgb!==background_rgb) box_changed=box_changed+1;
                        if(rgb==24'hF8FAFC && y>=20 && y<34) white_l1=white_l1+1;
                        if(rgb==24'hF8FAFC && y>=40 && y<54) white_l2=white_l2+1;
                        // The four extreme rectangle corners must be cut away.
                        if (((x==12 || x==219) && (y==12 || y==63)) && rgb!==background_rgb)
                            rounded_corner_leaks=rounded_corner_leaks+1;
                    end else if(rgb!==background_rgb) outside_changed=outside_changed+1;
                    if (x==0 && y==0 && rgb!==24'h804020) begin $display("ERROR: outside origin changed %h",rgb); errors=errors+1; end
                    // Top-left extreme corner is outside the rounded silhouette.
                    if (x==12 && y==12 && rgb!==24'h804020) begin $display("ERROR: rounded corner should pass through, got %h",rgb); errors=errors+1; end
                    // Top edge after the radius is the blended border.
                    if (x==18 && y==12 && rgb!==24'hBF9F8F) begin $display("ERROR: rounded top border got %h",rgb); errors=errors+1; end
                    // Interior remains the same 50% translucent fill as before.
                    if (x==18 && y==18 && rgb!==24'h402010) begin $display("ERROR: translucent fill got %h",rgb); errors=errors+1; end
                end
            end
            @(negedge clk); axis_valid=0; axis_user=0; axis_last=0;
        end
    endtask

    initial begin
        #12; rst_n=1;
        // Disabled = exact pass-through.
        @(negedge clk); axis_valid=1; axis_user=1; enable=0; #1;
        expect(rgb==24'h804020,"disabled info overlay is transparent");
        @(negedge clk); axis_valid=0;

        enable=1; image_width=640; image_height=480;
        repeat(20) @(negedge clk);
        check_640_text_contract();
        run_frame();
        expect(outside_changed==0,"overlay never modifies pixels outside top-left bounding box");
        expect(rounded_corner_leaks==0,"all four extreme corners are transparent for rounded box");
        expect(box_changed>7800,"rounded translucent box visibly modifies its footprint");
        expect(white_l1>100,"compact 640 multiplication 480 resolution text renders");
        expect(white_l2>110,"RGB888/24bit lower-case text renders");

        // Non-640 dimensions must compactly move the multiplication sign.
        @(negedge clk); rst_n=0; axis_valid=0; @(negedge clk); rst_n=1;
        image_width=1920; image_height=1080;
        repeat(20) @(negedge clk);
        check_1920_text_contract();
        run_frame();
        expect(white_l1>110,"dynamic compact 1920 multiplication 1080 text renders");
        expect(white_l2>110,"RGB888/24bit remains for alternate resolution metadata");
        expect(outside_changed==0,"alternate metadata still stays within rounded box bounds");
        expect(rounded_corner_leaks==0,"rounded corners remain transparent with alternate metadata");

        if(errors==0) $display("PASS: m2_image_info_overlay checks=%0d",checks);
        else $display("FAIL: m2_image_info_overlay errors=%0d checks=%0d",errors,checks);
        $finish;
    end
endmodule
