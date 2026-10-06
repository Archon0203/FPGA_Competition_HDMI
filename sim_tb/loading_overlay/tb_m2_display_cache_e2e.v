`timescale 1ns/1ps
// Real display core, remote parser, CDC writer, SDRAM cache, raster and overlays.
// Only vendor physical boundaries are behavioral models; the GPIO PHY has its
// own asynchronous/backpressure regression.
module tb_m2_display_cache_e2e;
    reg clk=0,rst_n=0,start=0,wv=0,done=0;
    always #10 clk=~clk;
    wire media_clk,media_rst_n,txv,txr,wr,txbusy,published;
    reg [7:0] id=0;
    reg [20:0] addr=0;
    reg [31:0] pixel=0;
    wire [31:0] word;
    reg qv=0;reg [7:0] qid=0;wire qr,rv,rh;
    reg tx_prefetch=1'b0;
    reg card_missing=0;
    wire [87:0] name={80'h5049435455524530424d,8'h30+id};
    integer preserved=0,pixels=0,x,y,k,guard;
    time query_time;
    m2_remote_frame_tx #(.COMPACT_RGB888(1)) tx(.clk(media_clk),.rst_n(media_rst_n),
        .frame_begin(start),.image_id(id),.wr_valid(wv),.wr_addr(addr),.wr_data(pixel),
        .wr_ready(wr),.frame_done(done),.frame_error(1'b0),
        .out_valid(txv),.out_data(word),.out_ready(txr),.busy(txbusy),
        .filename_valid(done),.filename_83(name),.info_valid(done),
        .image_width(16'd640),.image_height(16'd480),.image_bpp(6'd24),
        .prefetch_frame(tx_prefetch));
    m2_frame_display_core #(.REMOTE_INPUT(1)) dut(.clk(clk),.rst_n(rst_n),
        .uart_rx(1'b1),.sd_miso(1'b1),.remote_valid(txv),.remote_data(word),.remote_ready(txr),
        .remote_published(published),.media_clock(media_clk),.media_reset_n(media_rst_n),
        .cache_query_valid(qv),.cache_query_image_id(qid),.cache_query_ready(qr),
        .cache_reply_valid(rv),.cache_reply_hit(rh),.cache_reply_ready(1'b1),
        .card_missing(card_missing));
    defparam dut.u_hdmi_supervisor.RESET_HOLD_CYCLES=20;

    always @(negedge media_clk) if(media_rst_n && dut.front_valid && dut.loading_active && dut.baseline_axis_valid) begin
        if(dut.axis_data_pre_subtitle!==dut.framebuffer_axis_data)
            $fatal(1,"loading UI appeared over picture during reload");
        preserved=preserved+1;
    end
    task send_frame;
        input [7:0] image;
        input [23:0] color;
        begin
            @(negedge media_clk);id=image;start=1;
            @(negedge media_clk);start=0;
            for(k=0;k<307200;k=k+1) begin
                while(!wr) @(negedge media_clk);
                addr=k;pixel={8'd0,color};wv=1;
                @(negedge media_clk);wv=0;
            end
            while(!wr) @(negedge media_clk);
            done=1;@(negedge media_clk);done=0;
            wait(!txbusy);wait(published);
        end
    endtask
    task check_picture;
        input [7:0] image;
        input [23:0] color;
        begin
            @(negedge media_clk);
            while(!(dut.baseline_axis_valid && dut.baseline_axis_user)) @(negedge media_clk);
            x=0;y=0;pixels=0;
            while(pixels<307200) begin
                if(dut.baseline_axis_valid) begin
                    if(!dut.fb_pixel_valid || dut.framebuffer_axis_data!==color)
                        $fatal(1,"mixed/unaligned framebuffer image=%0d x=%0d y=%0d rgb=%h",image,x,y,dut.framebuffer_axis_data);
                    if(y>=80 && y<400 && dut.axis_data!==color) $fatal(1,"unexpected loading/overlay in picture center");
                    pixels=pixels+1;
                    if(x==639) begin x=0;y=y+1;end else x=x+1;
                end
                @(negedge media_clk);
            end
            if(dut.displayed_caption_image_id!=image || dut.displayed_caption_filename_83[7:0]!=8'h30+image)
                $fatal(1,"caption does not match displayed pixels");
        end
    endtask
    task cached_switch;
        input [7:0] image;
        begin
            @(negedge media_clk);qid=image;qv=1;query_time=$time;
            while(!qr) @(negedge media_clk);
            @(negedge media_clk);qv=0;
            wait(rv);if(!rh) $fatal(1,"expected cached image");
            if($time-query_time>34000000) $fatal(1,"cached switch exceeded two raster frames");
            $display("CACHE_LATENCY_NS: image=%0d ns=%0d",image,$time-query_time);
            @(negedge media_clk);
        end
    endtask
    task prefetch_frame;
        input [7:0] image;
        input [23:0] color;
        begin
            @(negedge media_clk);id=image;tx_prefetch=1;start=1;
            @(negedge media_clk);start=0;
            for(k=0;k<307200;k=k+1) begin
                while(!wr) @(negedge media_clk);
                addr=k;pixel={8'd0,color};wv=1;
                @(negedge media_clk);wv=0;
            end
            while(!wr) @(negedge media_clk);
            done=1;@(negedge media_clk);done=0;tx_prefetch=0;
            wait(dut.prefetch_publish_sticky);
            if(dut.displayed_caption_image_id==image)
                $fatal(1,"prefetch changed the displayed image before an explicit switch");
            $display("PREFETCH_READY: image=%0d cache_valid=%b",image,dut.cache_valid);
        end
    endtask
    initial begin
        repeat(5) @(negedge clk);rst_n=1;wait(media_rst_n);
        repeat(5) @(negedge media_clk);
        if(dut.use_framebuffer || dut.axis_data_pre_subtitle!==dut.loading_rgb) $fatal(1,"startup must show Loading UI");
        send_frame(0,24'h215579);check_picture(0,24'h215579);
        prefetch_frame(1,24'h973D52);
        cached_switch(1);check_picture(1,24'h973D52);
        send_frame(2,24'h416C35);check_picture(2,24'h416C35);
        cached_switch(0);check_picture(0,24'h215579);
        cached_switch(2);check_picture(2,24'h416C35);
        if(preserved==0 || dut.p1_05a_error) $fatal(1,"reload preservation or framebuffer health");
        card_missing=1;@(negedge media_clk);
        if(dut.axis_data_pre_subtitle!==dut.loading_rgb) $fatal(1,"missing TF card page not selected");
        card_missing=0;
        $display("PASS: display core startup, three banks, seamless reload, cache pixels/captions, missing-card UI mux");$finish;
    end
    initial begin #500000000;$fatal(1,"display E2E watchdog front=%b load=%b error=%b code=%h",dut.front_valid,dut.loading_active,dut.p1_05a_error,dut.media_failure_code);end
endmodule
