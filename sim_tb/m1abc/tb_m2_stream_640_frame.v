`timescale 1ns/1ps
module tb_m2_stream_640_frame;
    reg clk=0, rst_n=0, start=0, frame_boundary=0;
    reg [15:0] credit_add=0;
    reg [15:0] cycles=0;
    reg read_response_valid=0;
    reg [31:0] read_response_data=0;
    wire mem_rd_valid, packet_valid, packet_last, packet_ready;
    wire [20:0] mem_rd_addr, mem_wr_addr, front_base;
    wire [31:0] packet_data, mem_wr_data;
    wire mem_wr_valid, front_valid, pending_swap, commit_pulse;
    wire [15:0] front_frame_id;
    wire [7:0] front_image_id;
    wire source_ready, source_busy, source_done, source_error;
    wire [15:0] credit_level;
    wire commit_error, protocol_error, link_ready;
    wire mem_wr_ready = cycles[2:0] != 3'd3;
    integer writes=0, errors=0, wait_count=0;

    function [31:0] pixel_for_address;
        input [20:0] addr;
        integer row,col;
        reg [7:0] r,g,b;
        begin
            row=addr/640; col=addr%640;
            r=row; g=col; b=row+col;
            pixel_for_address={8'h00,r,g,b};
        end
    endfunction

    always #5 clk=~clk;
    m2_frame_packet_source source (
        .clk(clk),.rst_n(rst_n),.start(start),.frame_ready(1'b1),
        .frame_base(21'd0),.frame_id(16'd9),.image_id(8'd3),
        .credit_add(credit_add),.source_ready(source_ready),
        .source_busy(source_busy),.source_done(source_done),
        .source_error(source_error),.credit_level(credit_level),
        .mem_rd_valid(mem_rd_valid),.mem_rd_addr(mem_rd_addr),
        .mem_rd_ready(1'b1),.mem_rvalid(read_response_valid),
        .mem_rdata(read_response_data),.packet_valid(packet_valid),
        .packet_data(packet_data),.packet_last(packet_last),
        .packet_ready(packet_ready));
    m2_master_line_core master (
        .clk(clk),.rst_n(rst_n),.packet_valid(packet_valid),
        .packet_data(packet_data),.packet_last(packet_last),
        .packet_ready(packet_ready),.mem_wr_valid(mem_wr_valid),
        .mem_wr_addr(mem_wr_addr),.mem_wr_data(mem_wr_data),
        .mem_wr_ready(mem_wr_ready),.frame_boundary(frame_boundary),
        .front_base(front_base),.front_valid(front_valid),
        .front_frame_id(front_frame_id),.front_image_id(front_image_id),
        .pending_swap(pending_swap),.commit_pulse(commit_pulse),
        .commit_error(commit_error),.protocol_error(protocol_error),
        .link_ready(link_ready));

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            cycles<=0; read_response_valid<=0; read_response_data<=0;
        end else begin
            cycles<=cycles+1'b1;
            read_response_valid<=mem_rd_valid;
            if(mem_rd_valid) read_response_data<=pixel_for_address(mem_rd_addr);
        end
    end
    always @(posedge clk) if(rst_n) begin
        if(source_error || commit_error || protocol_error) begin
            if(errors<8) $display("ERROR: source or receiver fault at write %0d",writes);
            errors=errors+1;
        end
        if(mem_wr_valid && mem_wr_ready) begin
            if(mem_wr_addr !== 307200+writes ||
               mem_wr_data !== pixel_for_address(writes)) begin
                if(errors<8) $display("ERROR: write %0d addr=%0d data=%h",writes,mem_wr_addr,mem_wr_data);
                errors=errors+1;
            end
            writes=writes+1;
        end
    end

    initial begin
        repeat(4) @(negedge clk); rst_n=1;
        @(negedge clk); start=1; credit_add=480;
        @(negedge clk); start=0; credit_add=0;
        while(!pending_swap && wait_count<2500000) begin
            @(negedge clk); wait_count=wait_count+1;
        end
        if(!pending_swap || writes!=307200 || front_valid || errors!=0) begin
            $fatal(1,"FAIL: 640 stream candidate writes=%0d wait=%0d errors=%0d",
                   writes,wait_count,errors);
        end
        @(negedge clk); frame_boundary=1;
        @(negedge clk); frame_boundary=0;
        repeat(2) @(negedge clk);
        if(!front_valid || front_base!=307200 || front_frame_id!=9 ||
           front_image_id!=3 || !link_ready || errors!=0)
            $fatal(1,"FAIL: 640 frame commit base=%0d id=%0d errors=%0d",
                   front_base,front_frame_id,errors);
        $display("PASS: m2_stream_640_frame writes=%0d cycles=%0d",writes,wait_count);
        $finish;
    end
endmodule
