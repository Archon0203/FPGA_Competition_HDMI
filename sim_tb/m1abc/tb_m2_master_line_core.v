`timescale 1ns/1ps
module tb_m2_master_line_core;
    reg clk=0, rst_n=0, cmd_valid=0, frame_boundary=0;
    reg [15:0] credit_add=0;
    wire cmd_ready, packet_start, src_valid, src_ready;
    wire [15:0] frame_id, line_index;
    wire [7:0] image_id;
    wire [31:0] src_word, packet_data, mem_wr_data;
    wire packet_valid, packet_last, packet_ready, tx_busy;
    wire mem_wr_valid, front_valid, pending_swap, commit_pulse;
    wire [20:0] mem_wr_addr, front_base;
    wire [15:0] front_frame_id;
    wire [7:0] front_image_id;
    wire commit_error, protocol_error, link_ready;
    integer writes=0, errors=0, wait_count=0;
    integer row=0, col=0;
    reg [31:0] expected_word;
    reg [7:0] blue;

    always #5 clk=~clk;
    m2_media_line_source #(.IMAGE_WIDTH(4), .IMAGE_HEIGHT(3),
                           .WORDS_PER_LINE(4)) source (
        .clk(clk),.rst_n(rst_n),.cmd_valid(cmd_valid),.cmd_ready(cmd_ready),
        .cmd_image_id(8'd2),.cmd_play(1'b1),.cmd_pause(1'b0),
        .credit_add(credit_add),.catalog_valid(),.catalog_count(),
        .catalog_epoch(),.descriptor_valid(),.descriptor_image_id(),
        .descriptor_width(),.descriptor_height(),.source_ready(),
        .source_busy(),.source_done(),.source_error(),.credit_level(),
        .packet_start(packet_start),.frame_id(frame_id),.image_id(image_id),
        .line_index(line_index),.line_start(),.line_end(),.frame_end(),
        .data_valid(src_valid),.data_ready(src_ready),.data_word(src_word));
    m2_line_packet_tx #(.PAYLOAD_WORDS(4)) tx (
        .clk(clk),.rst_n(rst_n),.line_start(packet_start),
        .frame_id(frame_id),.image_id(image_id),.line_index(line_index),
        .payload_valid(src_valid),.payload_data(src_word),
        .payload_ready(src_ready),.out_valid(packet_valid),
        .out_data(packet_data),.out_last(packet_last),
        .out_ready(packet_ready),.busy(tx_busy),.packet_done(),.sequence());
    m2_master_line_core #(.WIDTH(4),.HEIGHT(3),.BASE_B(12)) dut (
        .clk(clk),.rst_n(rst_n),.packet_valid(packet_valid),
        .packet_data(packet_data),.packet_last(packet_last),
        .packet_ready(packet_ready),.mem_wr_valid(mem_wr_valid),
        .mem_wr_addr(mem_wr_addr),.mem_wr_data(mem_wr_data),
        .mem_wr_ready(1'b1),.frame_boundary(frame_boundary),
        .front_base(front_base),.front_valid(front_valid),
        .front_frame_id(front_frame_id),.front_image_id(front_image_id),
        .pending_swap(pending_swap),.commit_pulse(commit_pulse),
        .commit_error(commit_error),.protocol_error(protocol_error),
        .link_ready(link_ready));

    always @(posedge clk) if(rst_n) begin
        if(commit_error || protocol_error) begin
            $display("ERROR: receiver/commit error"); errors=errors+1;
        end
        if(mem_wr_valid) begin
            blue=2+row+col;
            expected_word={8'h00,(8'd2 ^ row[7:0]),col[7:0],blue};
            if(mem_wr_addr !== 12+row*4+col || mem_wr_data !== expected_word) begin
                $display("ERROR: write %0d addr=%0d data=%h expected=%h",
                         writes,mem_wr_addr,mem_wr_data,expected_word);
                errors=errors+1;
            end
            writes=writes+1;
            if(col==3) begin col=0; row=row+1; end else col=col+1;
        end
    end

    initial begin
        repeat(4) @(negedge clk); rst_n=1;
        @(negedge clk); cmd_valid=1; credit_add=3;
        @(negedge clk); cmd_valid=0; credit_add=0;
        while(!pending_swap && wait_count<500) begin
            @(negedge clk); wait_count=wait_count+1;
        end
        if(!pending_swap || writes!=12 || front_valid) begin
            $display("ERROR: no fenced candidate writes=%0d",writes); errors=errors+1;
        end
        @(negedge clk); frame_boundary=1;
        @(negedge clk); frame_boundary=0;
        repeat(2) @(negedge clk);
        if(!front_valid || front_base!=12 || front_image_id!=2 ||
           front_frame_id==0 || !link_ready) begin
            $display("ERROR: front commit"); errors=errors+1;
        end
        if(errors==0) $display("PASS: m2_master_line_core packet-to-front writes=%0d",writes);
        else $fatal(1,"FAIL: m2_master_line_core errors=%0d",errors);
        $finish;
    end
endmodule
