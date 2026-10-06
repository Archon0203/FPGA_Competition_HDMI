`timescale 1ns/1ps
module tb_m2_loading_card #(parameter integer ERROR_PAGE=0);
    reg clk=0,rst=1;
    always #5 clk=~clk;
    wire valid,user,last;
    wire [23:0] unused,rgb;
    integer f,n=0,white=0,card=0;
    hdmi_official_baseline_source raster(clk,rst,user,valid,last,unused);
    m2_loading_card dut(.clk(clk),.rst_n(!rst),.axis_valid(valid),.axis_user(user),
        .axis_last(last),.background_rgb(24'd0),.overlay_only(1'b0),.card_missing(ERROR_PAGE!=0),.rgb(rgb));
    initial begin
        f=$fopen(ERROR_PAGE ? "missing_card.ppm" : "loading_card.ppm","w");
        $fwrite(f,"P3\n640 480\n255\n");
        repeat(4) @(negedge clk);rst=0;
        while(n<307200) begin
            @(negedge clk);
            if(valid) begin
                $fwrite(f,"%0d %0d %0d\n",rgb[23:16],rgb[15:8],rgb[7:0]);
                if(rgb==24'hf1f5f9) white=white+1;
                if(rgb==24'h25354d) card=card+1;
                n=n+1;
            end
        end
        $fclose(f);
        if(white<100 || card<(ERROR_PAGE?28000:20000) || card>(ERROR_PAGE?31000:24000)) $fatal(1,"loading UI pixel geometry");
        $display("PASS: loading card raster, pixels=%0d glyph_pixels=%0d",n,white);
        $finish;
    end
    initial begin #6000000; $fatal(1,"watchdog"); end
endmodule
