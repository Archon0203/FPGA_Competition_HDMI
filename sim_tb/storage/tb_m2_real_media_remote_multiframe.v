`timescale 1ns/1ps
module tb_m2_real_media_remote_multiframe;
    reg clk=0, rst_n=0, cmd_valid=0, scan_start=0, sector_error=0;
    reg [7:0] cmd_image_id=0;
    wire cmd_ready, sector_req, sector_ready, sector_consume_ready, din_valid;
    wire [31:0] sector_lba;
    wire [7:0] din;
    wire mem_wr_valid, catalog_valid, descriptor_valid;
    wire [20:0] mem_wr_addr;
    wire [31:0] mem_wr_data;
    wire [7:0] catalog_count, descriptor_image_id, error_code;
    wire [15:0] catalog_epoch, descriptor_width, descriptor_height;
    wire source_ready, source_busy, source_done, source_error;
    reg [7:0] disk [0:7][0:511];
    reg streaming=0;
    reg [2:0] sector_q=0;
    reg [8:0] index_q=0;
    integer image, i,j,checks=0,errors=0,writes=0,done_count=0,error_count=0;
    reg [31:0] pixels [0:3];
    reg [31:0] master_pixels [0:3];
    reg frame_fence=0, packet_start=0, frame_boundary=0;
    reg [15:0] packet_credit=0;
    reg read_response_valid=0;
    reg [31:0] read_response_data=0;
    wire frame_source_ready, frame_source_done, frame_source_error;
    wire [15:0] frame_credit_level;
    wire read_valid, packet_valid, packet_last, packet_ready;
    wire [20:0] read_addr, master_write_addr, front_base;
    wire [31:0] packet_data, master_write_data;
    wire master_write_valid, front_valid, pending_swap, commit_pulse;
    wire [15:0] front_frame_id;
    wire [7:0] front_image_id;
    wire commit_error, protocol_error, link_ready;
    integer master_writes=0;

    always #5 clk=~clk;
    assign sector_ready = streaming;
    assign din_valid = streaming && sector_consume_ready;
    assign din = disk[sector_q][index_q];

    wire service_wr_valid, service_wr_ready, service_done;
    wire [20:0] service_wr_addr;
    wire [31:0] service_wr_data, link_tx_word, link_rx_word;
    wire link_tx_valid, link_tx_ready, link_rx_valid, link_rx_ready;
    wire [6:0] link_pins;
    wire link_req, link_ack, link_error;
    reg rx_clk=0;
    always #7 rx_clk=~rx_clk;
    m2_remote_frame_tx tx(clk,rst_n,cmd_valid && cmd_ready,cmd_image_id,
        service_wr_valid,service_wr_addr,service_wr_data,service_wr_ready,
        service_done,source_error,link_tx_valid,link_tx_word,link_tx_ready,);
    m2_gpio_mailbox_tx ptx(clk,rst_n,link_tx_valid,link_tx_word,link_tx_ready,link_pins,link_req,link_ack);
    // Use one test clock for the memory scoreboard; independent clocks are covered in the PHY test.
    m2_gpio_mailbox_rx prx(clk,rst_n,link_pins,link_req,link_ack,link_rx_valid,link_rx_word,link_rx_ready);
    m2_remote_frame_rx #(.PIXELS(4)) rx(clk,rst_n,link_rx_valid,link_rx_word,link_rx_ready,
        ,source_done,link_error,,mem_wr_valid,mem_wr_addr,mem_wr_data,1'b1,);
    m2_real_media_service #(.WIDTH(2), .HEIGHT(2)) dut (
        .clk(clk), .rst_n(rst_n), .scan_start(scan_start),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready),
        .cmd_image_id(cmd_image_id), .frame_base(21'd0),
        .sector_req(sector_req), .sector_lba(sector_lba),
        .sector_consume_ready(sector_consume_ready),
        .sector_ready(sector_ready), .sector_idle(!streaming),
        .sector_din_valid(din_valid),
        .sector_din(din), .sector_error(sector_error),
        .mem_wr_valid(service_wr_valid), .mem_wr_addr(service_wr_addr),
        .mem_wr_data(service_wr_data), .mem_wr_ready(service_wr_ready),
        .catalog_valid(catalog_valid), .catalog_count(catalog_count),
        .catalog_epoch(catalog_epoch),
        .descriptor_valid(descriptor_valid),
        .descriptor_image_id(descriptor_image_id),
        .descriptor_width(descriptor_width),
        .descriptor_height(descriptor_height),
        .source_ready(source_ready), .source_busy(source_busy),
        .source_done(service_done), .source_error(source_error),
        .error_code(error_code));

    m2_frame_packet_source #(.WIDTH(2), .HEIGHT(2)) u_frame_source (
        .clk(clk), .rst_n(rst_n), .start(packet_start),
        .frame_ready(frame_fence), .frame_base(21'd0),
        .frame_id(16'd1), .image_id(8'd0), .credit_add(packet_credit),
        .source_ready(frame_source_ready), .source_busy(),
        .source_done(frame_source_done), .source_error(frame_source_error),
        .credit_level(frame_credit_level), .mem_rd_valid(read_valid),
        .mem_rd_addr(read_addr), .mem_rd_ready(1'b1),
        .mem_rvalid(read_response_valid), .mem_rdata(read_response_data),
        .packet_valid(packet_valid), .packet_data(packet_data),
        .packet_last(packet_last), .packet_ready(packet_ready));

    m2_master_line_core #(.WIDTH(2), .HEIGHT(2), .BASE_B(4)) u_master (
        .clk(clk), .rst_n(rst_n), .packet_valid(packet_valid),
        .packet_data(packet_data), .packet_last(packet_last),
        .packet_ready(packet_ready), .mem_wr_valid(master_write_valid),
        .mem_wr_addr(master_write_addr), .mem_wr_data(master_write_data),
        .mem_wr_ready(1'b1), .frame_boundary(frame_boundary),
        .front_base(front_base), .front_valid(front_valid),
        .front_frame_id(front_frame_id), .front_image_id(front_image_id),
        .pending_swap(pending_swap), .commit_pulse(commit_pulse),
        .commit_error(commit_error), .protocol_error(protocol_error),
        .link_ready(link_ready));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            streaming <= 0; sector_q <= 0; index_q <= 0;
        end else if (!sector_req) begin
            streaming <= 0; index_q <= 0;
        end else if (!streaming) begin
            streaming <= 1;
            sector_q <= sector_lba[2:0];
            index_q <= 0;
        end else if (sector_consume_ready && index_q == 511) begin
            streaming <= 0;
        end else if (sector_consume_ready) index_q <= index_q + 1'b1;
    end

    always @(posedge clk) if (rst_n) begin
        if (mem_wr_valid) begin
            if (mem_wr_addr < 4) pixels[mem_wr_addr] <= mem_wr_data;
            else begin $display("ERROR: write address %0d",mem_wr_addr); errors=errors+1; end
            writes=writes+1;
        end
        if (source_done) done_count=done_count+1;
        if (source_error) error_count=error_count+1;
        if (source_done) frame_fence <= 1'b1;
        read_response_valid <= read_valid;
        if (read_valid) read_response_data <= pixels[read_addr];
        if (master_write_valid) begin
            if (master_write_addr>=4 && master_write_addr<8)
                master_pixels[master_write_addr-4] <= master_write_data;
            else begin $display("ERROR: master write address %0d",master_write_addr); errors=errors+1; end
            master_writes=master_writes+1;
        end
    end

    task check;
        input cond; input [255:0] label;
        begin checks=checks+1; if (!cond) begin
            errors=errors+1; $display("ERROR: %0s",label);
        end end
    endtask

    task open_image;
        begin
            @(negedge clk); cmd_valid=1;
            @(negedge clk); cmd_valid=0;
        end
    endtask

    initial begin
        for(i=0;i<8;i=i+1) for(j=0;j<512;j=j+1) disk[i][j]=0;
        // MBR, BPB, root entry: partition 1, FAT 2, root 3, file cluster 3 at 4.
        disk[0][450]=8'h0c; disk[0][454]=1;
        disk[1][11]=0; disk[1][12]=2; disk[1][13]=1;
        disk[1][14]=1; disk[1][16]=1; disk[1][36]=1; disk[1][44]=2;
        disk[3][0]=8'h49; disk[3][8]=8'h42; disk[3][9]=8'h4d;
        disk[3][10]=8'h50; disk[3][11]=8'h20;
        disk[3][26]=3; disk[3][28]=70; disk[3][32]=0;
        disk[4][0]=8'h42; disk[4][1]=8'h4d;
        disk[4][2]=70; disk[4][10]=54; disk[4][14]=40;
        disk[4][18]=2; disk[4][22]=2; disk[4][26]=1;
        disk[4][28]=24;
        // Bottom row: red, blue. Top row: green, white. Each row has 2 pad bytes.
        disk[4][54]=0; disk[4][55]=0; disk[4][56]=255;
        disk[4][57]=255; disk[4][58]=0; disk[4][59]=0;
        disk[4][62]=0; disk[4][63]=255; disk[4][64]=0;
        disk[4][65]=255; disk[4][66]=255; disk[4][67]=255;

        // Three additional files with distinct clusters and pixel content.
        for (i=1;i<4;i=i+1) begin
            for(j=0;j<32;j=j+1) disk[3][32*i+j]=disk[3][j];
            disk[3][32*i]=8'h49+i;
            disk[3][32*i+26]=3+i;
            for(j=0;j<512;j=j+1) disk[4+i][j]=disk[4][j];
            disk[4+i][63]=i;
        end
        #22; rst_n=1;
        i=0; while(!cmd_ready && i<3000) begin @(negedge clk); i=i+1; end
        check(cmd_ready && catalog_valid && catalog_count==4,"catalog ready");
        open_image();
        i=0; while(done_count==0 && error_count==0 && i<4000) begin @(negedge clk); i=i+1; end
        check(done_count==1 && error_count==0,"good BMP transaction completes");
        check(descriptor_image_id==0 && descriptor_width==2 && descriptor_height==2,
              "BMP descriptor");
        check(writes==4,"four pixels written");
        check(pixels[0]==32'h0000ff00 && pixels[1]==32'h00ffffff &&
              pixels[2]==32'h00ff0000 && pixels[3]==32'h000000ff,
              "bottom-up BGR converted to display addresses");
        @(negedge clk); packet_start=1; packet_credit=2;
        @(negedge clk); packet_start=0; packet_credit=0;
        i=0; while(!pending_swap && i<300) begin @(negedge clk); i=i+1; end
        check(pending_swap && master_writes==4 && !front_valid &&
              !frame_source_error && !protocol_error && !commit_error,
              "media readback and packet writes candidate only");
        @(negedge clk); frame_boundary=1;
        @(negedge clk); frame_boundary=0;
        repeat(2) @(negedge clk);
        check(front_valid && front_base==4 && front_frame_id==1 &&
              front_image_id==0,"Master publishes only at frame boundary");
        check(master_pixels[0]==pixels[0] && master_pixels[1]==pixels[1] &&
              master_pixels[2]==pixels[2] && master_pixels[3]==pixels[3],
              "TF image words survive packet path");
        // Repeat a successful load with different pixels. Sticky done/ok from
        // frame zero must not terminate this transaction before new file_start.
        disk[4][63]=8'h12;
        i=0; while(!cmd_ready && i<200) begin @(negedge clk); i=i+1; end
        open_image();
        i=0; while(done_count<2 && error_count==0 && i<4000) begin @(negedge clk); i=i+1; end
        check(done_count==2 && error_count==0 && writes==8,
              "second load writes an entire new frame");
        check(pixels[0]==32'h00001200,"second load replaces old pixel content");
        for(image=1;image<4;image=image+1) begin
            i=0; while(!cmd_ready && i<200) begin @(negedge clk); i=i+1; end
            cmd_image_id=image;
            open_image();
            i=0; while(done_count<image+2 && error_count==0 && i<4000) begin @(negedge clk); i=i+1; end
            check(done_count==image+2 && error_count==0 && writes==4*(image+2),
                  "each image writes all pixels without old done flags");
            check(descriptor_image_id==image && pixels[0]==(image<<8),
                  "catalog ID selects distinct cluster and pixel data");
        end
        cmd_image_id=0;
        // Same catalog entry, damaged header: no successful frame completion.
        disk[4][0]=8'h00;
        i=0; while(!cmd_ready && i<200) begin @(negedge clk); i=i+1; end
        open_image();
        i=0; while(error_count==0 && i<4000) begin @(negedge clk); i=i+1; end
        check(error_count==1 && done_count==5,"bad BMP rejected");
        check(front_base==4 && front_frame_id==1,"bad media leaves Master front unchanged");
        if(errors==0) $display("PASS: m2_real_media_remote_multiframe checks=%0d",checks);
        else $fatal(1,"FAIL: m2_real_media_service errors=%0d checks=%0d",errors,checks);
        $finish;
    end
endmodule
