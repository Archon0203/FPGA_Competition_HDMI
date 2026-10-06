`timescale 1ns/1ps
module tb_m2_remote_frame_filename #(parameter integer COMPACT=0, BOTTOM_UP=0);
    reg clk=0, rst_n=0;
    reg start=0, wvalid=0, done=0, err=0;
    reg [7:0] id=0;
    reg [20:0] addr=0;
    reg [31:0] data=0;
    reg tx_filename_valid=0;
    reg [87:0] tx_filename_83={11{8'h20}};
    reg tx_info_valid=0;
    reg [15:0] tx_width=640, tx_height=480;
    reg [5:0] tx_bpp=24;
    wire wready, tvalid, tready, txbusy;
    wire [31:0] tdata;
    reg corrupt_name=0, corrupt_info=0;
    wire [31:0] link_data = (corrupt_name && tx.state==5'd6) ? (tdata ^ 32'h00000001) :
                            (corrupt_info && tx.state==5'd13) ? (tdata ^ 32'h00010000) : tdata;

    wire rready, frame_begin, frame_done, frame_error;
    wire [7:0] rx_id;
    wire rx_filename_valid;
    wire [87:0] rx_filename_83;
    wire rx_info_valid;
    wire [15:0] rx_width, rx_height;
    wire [5:0] rx_bpp;
    wire rx_wr_valid;
    wire [20:0] rx_wr_addr;
    wire [31:0] rx_wr_data;
    integer errors=0, checks=0, rx_pixels=0, words=0;
    reg seen_done=0, seen_error=0, seen_name=0, seen_info=0;
    reg [87:0] seen_filename={11{8'h20}};
    reg [15:0] seen_width=0, seen_height=0; reg [5:0] seen_bpp=0;

    always #5 clk=~clk;
    m2_remote_frame_tx #(.COMPACT_RGB888(COMPACT)) tx(
        .clk(clk),.rst_n(rst_n),.frame_begin(start),.image_id(id),
        .wr_valid(wvalid),.wr_addr(addr),.wr_data(data),.wr_ready(wready),
        .frame_done(done),.frame_error(err),.out_valid(tvalid),.out_data(tdata),
        .out_ready(tready),.busy(txbusy),.filename_valid(tx_filename_valid),
        .filename_83(tx_filename_83), .info_valid(tx_info_valid),
        .image_width(tx_width), .image_height(tx_height), .image_bpp(tx_bpp));
    m2_remote_frame_rx #(.PIXELS(4)) rx(
        .clk(clk),.rst_n(rst_n),.in_valid(tvalid),.in_data(link_data),.in_ready(tready),
        .frame_begin(frame_begin),.frame_done(frame_done),.frame_error(frame_error),.image_id(rx_id),
        .wr_valid(rx_wr_valid),.wr_addr(rx_wr_addr),.wr_data(rx_wr_data),.wr_ready(1'b1),.busy(),
        .filename_valid(rx_filename_valid),.filename_83(rx_filename_83),
        .info_valid(rx_info_valid), .image_width(rx_width), .image_height(rx_height), .image_bpp(rx_bpp));

    always @(posedge clk) begin
        if(!rst_n) begin words<=0; rx_pixels<=0; seen_done<=0; seen_error<=0; seen_name<=0; seen_info<=0; seen_filename<={11{8'h20}}; seen_width<=0; seen_height<=0; seen_bpp<=0; end
        else begin
            if(tvalid && tready) words<=words+1;
            if(rx_wr_valid) begin
                if(rx_wr_addr!==(BOTTOM_UP ? ((rx_pixels<2)?rx_pixels+2:rx_pixels-2) : rx_pixels)) begin $display("ERROR: pixel addr got=%0d exp=%0d",rx_wr_addr,rx_pixels); errors<=errors+1; end
                if(rx_wr_data!==(32'h00220000+rx_wr_addr)) begin $display("ERROR: pixel data/order");errors<=errors+1; end
                rx_pixels<=rx_pixels+1;
            end
            if(frame_done) seen_done<=1;
            if(frame_error) seen_error<=1;
            if(rx_filename_valid) begin seen_name<=1; seen_filename<=rx_filename_83; end
            if(rx_info_valid) begin seen_info<=1; seen_width<=rx_width; seen_height<=rx_height; seen_bpp<=rx_bpp; end
        end
    end

    task expect;
        input condition; input [255:0] label;
        begin checks=checks+1; if(!condition) begin errors=errors+1; $display("ERROR: %0s",label); end end
    endtask
    task reset_case;
        begin
            @(negedge clk); rst_n=0; start=0; wvalid=0; done=0; err=0; tx_filename_valid=0; tx_info_valid=0; corrupt_name=0; corrupt_info=0;
            repeat(3) @(negedge clk); rst_n=1; repeat(2) @(negedge clk);
        end
    endtask
    task send_frame;
        input [7:0] image;
        input has_name;
        input [87:0] name;
        input has_info;
        integer k;
        begin
            id=image; tx_filename_83=name;
            @(negedge clk); start=1;
            @(negedge clk); start=0;
            for(k=0;k<4;k=k+1) begin
                while(!wready) @(negedge clk);
                addr=BOTTOM_UP ? ((k<2)?k+2:k-2) : k; data=32'h00220000+addr; wvalid=1;
                @(negedge clk); wvalid=0;
            end
            while(!wready) @(negedge clk);
            tx_filename_valid=has_name; tx_info_valid=has_info; done=1;
            @(negedge clk); done=0; tx_filename_valid=0; tx_info_valid=0;
            k=0; while(txbusy && k<200) begin @(negedge clk); k=k+1; end
            repeat(5) @(negedge clk);
        end
    endtask

    initial begin
        reset_case();
        send_frame(8'd3,1'b1,"PHOTO003BMP",1'b1);
        expect(seen_done && !seen_error,"extended frame completes without error");
        expect(seen_name && seen_filename=="PHOTO003BMP","filename metadata delivered after CRC");
        expect(seen_info && seen_width==640 && seen_height==480 && seen_bpp==24,"resolution/RGB metadata delivered after CRC");
        expect(rx_pixels==4 && rx_id==3,"pixels and image id preserved");
        expect(words==(COMPACT ? (BOTTOM_UP?16:14) : 18), "exact transport word reduction including metadata");

        reset_case();
        send_frame(8'd4,1'b0,{11{8'h20}},1'b0);
        expect(seen_done && !seen_error,"legacy no-name frame still accepted");
        expect(!seen_name,"legacy frame does not assert filename_valid");
        expect(!seen_info,"legacy frame does not assert info_valid");
        expect(rx_pixels==4,"legacy frame pixels preserved");

        reset_case();
        corrupt_name=1;
        send_frame(8'd5,1'b1,"BROKEN  BMP",1'b1);
        expect(!seen_done && seen_error,"corrupted filename metadata is rejected by CRC");
        expect(!seen_name,"corrupt metadata is never published");
        expect(!seen_info,"CRC failure suppresses image-info metadata too");

        reset_case();
        corrupt_info=1;
        send_frame(8'd6,1'b1,"INFOBAD BMP",1'b1);
        expect(!seen_done && seen_error,"corrupted resolution metadata is rejected by CRC");
        expect(!seen_info && !seen_name,"corrupt INFO prevents all metadata publication");

        if(errors==0) $display("PASS: m2_remote_frame_filename checks=%0d",checks);
        else $display("FAIL: m2_remote_frame_filename errors=%0d checks=%0d",errors,checks);
        $finish;
    end
endmodule
