`timescale 1ns/1ps
module tb_m2_caption_cache;
    reg clk=0,rst_n=0,begin_load=0,commit=0,restore=0,filename_valid=0,info_valid=0;
    reg [2:0] slot=0,target=0;
    reg [7:0] image=0,query=0;
    reg [87:0] name=0;
    reg [15:0] width=640,height=480;
    wire [7:0] displayed;
    wire [87:0] displayed_name;
    wire [15:0] displayed_width,displayed_height;
    wire [5:0] bpp,valid;
    wire hit;wire [2:0] found;
    integer i;
    always #5 clk=~clk;
    m2_caption_commit dut(.clk(clk),.rst_n(rst_n),.load_begin(begin_load),.load_image_id(image),
        .filename_valid(filename_valid),.filename_83(name),.image_info_valid(info_valid),
        .image_width(width),.image_height(height),.image_bpp(6'd24),.commit_pulse(commit),
        .load_slot(slot),.cached_commit(restore),.cached_slot(target),.query_image_id(query),
        .cache_hit(hit),.cache_slot(found),.cache_valid(valid),.displayed_image_id(displayed),
        .displayed_filename_83(displayed_name),.displayed_image_width(displayed_width),
        .displayed_image_height(displayed_height),.displayed_image_bpp(bpp));
    initial begin
        repeat(3) @(negedge clk);rst_n=1;
        for(i=0;i<6;i=i+1) begin
            slot=i;image=i;begin_load=1;@(negedge clk);begin_load=0;
            name={80'h4142434445464748494a,8'h30+i[7:0]};width=640+i;height=480+i;
            filename_valid=1;info_valid=1;@(negedge clk);filename_valid=0;info_valid=0;
            query=i; #1;if(hit) $fatal(1,"incomplete bank must not be cached");
            commit=1;@(negedge clk);commit=0;
        end
        for(i=5;i>=0;i=i-1) begin
            query=i;#1;if(!hit || found!=i) $fatal(1,"cache lookup %0d",i);
            target=found;restore=1;@(negedge clk);restore=0;
            if(displayed!=i || displayed_width!=640+i || displayed_height!=480+i ||
               displayed_name[7:0]!=8'h30+i || bpp!=24) $fatal(1,"cached metadata mismatch %0d",i);
        end
        slot=3;image=9;begin_load=1;@(negedge clk);begin_load=0;
        query=3;#1;if(hit) $fatal(1,"evicted bank valid during rewrite");
        if(displayed!=0 || displayed_name[7:0]!="0") $fatal(1,"rewrite changed front metadata");
        $display("PASS: six-bank caption cache, atomic restore, eviction invalidation");$finish;
    end
    initial begin #10000;$fatal(1,"caption cache watchdog");end
endmodule
