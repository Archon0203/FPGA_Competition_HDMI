`timescale 1ns/1ps
module tb_m2_caption_commit;
    reg clk=0, rst_n=0;
    reg load_begin=0, filename_valid=0, image_info_valid=0, commit_pulse=0;
    reg [7:0] load_image_id=0;
    reg [87:0] filename_83={11{8'h20}};
    reg [15:0] image_width=0, image_height=0;
    reg [5:0] image_bpp=0;
    wire [7:0] displayed_image_id;
    wire [87:0] displayed_filename_83;
    wire [15:0] displayed_image_width, displayed_image_height;
    wire [5:0] displayed_image_bpp;
    integer errors=0, checks=0;

    always #5 clk=~clk;
    m2_caption_commit dut(
        .clk(clk),.rst_n(rst_n),.load_begin(load_begin),.load_image_id(load_image_id),
        .filename_valid(filename_valid),.filename_83(filename_83),
        .image_info_valid(image_info_valid),.image_width(image_width),.image_height(image_height),.image_bpp(image_bpp),
        .commit_pulse(commit_pulse),.displayed_image_id(displayed_image_id),
        .displayed_filename_83(displayed_filename_83),
        .displayed_image_width(displayed_image_width),.displayed_image_height(displayed_image_height),
        .displayed_image_bpp(displayed_image_bpp));

    task expect;
        input condition; input [255:0] label;
        begin checks=checks+1; if(!condition) begin
            errors=errors+1; $display("ERROR: %0s",label);
        end end
    endtask
    task pulse_load;
        input [7:0] id;
        begin @(negedge clk); load_image_id=id; load_begin=1; @(negedge clk); load_begin=0; end
    endtask
    task pulse_metadata;
        input [87:0] name; input [15:0] w; input [15:0] h; input [5:0] bpp;
        begin
            @(negedge clk); filename_83=name; filename_valid=1; image_width=w; image_height=h; image_bpp=bpp; image_info_valid=1;
            @(negedge clk); filename_valid=0; image_info_valid=0;
        end
    endtask
    task pulse_commit;
        begin @(negedge clk); commit_pulse=1; @(negedge clk); commit_pulse=0; end
    endtask

    initial begin
        #12; rst_n=1;
        pulse_load(8'd0);
        pulse_metadata("FIRST   BMP",16'd640,16'd480,6'd24);
        expect(displayed_filename_83=={11{8'h20}},"first filename hidden before commit");
        expect(displayed_image_width==0 && displayed_image_height==0,"first resolution hidden before commit");
        pulse_commit(); #1;
        expect(displayed_image_id==0,"first image id committed");
        expect(displayed_filename_83=="FIRST   BMP","first filename committed");
        expect(displayed_image_width==640 && displayed_image_height==480 && displayed_image_bpp==24,"first image info committed");

        pulse_load(8'd1);
        expect(displayed_image_id==0 && displayed_filename_83=="FIRST   BMP","old caption preserved while next image loads");
        expect(displayed_image_width==640 && displayed_image_height==480,"old resolution preserved while next image loads");
        pulse_metadata("SECOND  BMP",16'd800,16'd600,6'd24);
        expect(displayed_filename_83=="FIRST   BMP","new filename must not leak before framebuffer switch");
        expect(displayed_image_width==640 && displayed_image_height==480,"new resolution must not leak before framebuffer switch");
        pulse_commit(); #1;
        expect(displayed_image_id==1,"second image id committed");
        expect(displayed_filename_83=="SECOND  BMP","second filename committed");
        expect(displayed_image_width==800 && displayed_image_height==600 && displayed_image_bpp==24,"second image info committed");

        // Defensive same-cycle metadata+commit behavior.
        @(negedge clk);
        load_image_id=8'd11; filename_83="TWELVE  BMP";
        image_width=16'd1920; image_height=16'd1080; image_bpp=6'd24;
        load_begin=1; filename_valid=1; image_info_valid=1; commit_pulse=1;
        @(negedge clk);
        load_begin=0; filename_valid=0; image_info_valid=0; commit_pulse=0; #1;
        expect(displayed_image_id==11,"same-cycle load id wins at commit");
        expect(displayed_filename_83=="TWELVE  BMP","same-cycle filename wins at commit");
        expect(displayed_image_width==1920 && displayed_image_height==1080 && displayed_image_bpp==24,"same-cycle image info wins at commit");

        if(errors==0) $display("PASS: m2_caption_commit checks=%0d",checks);
        else $display("FAIL: m2_caption_commit errors=%0d checks=%0d",errors,checks);
        $finish;
    end
endmodule
