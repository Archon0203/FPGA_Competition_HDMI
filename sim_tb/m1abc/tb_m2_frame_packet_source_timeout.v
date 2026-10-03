`timescale 1ns/1ps
module tb_m2_frame_packet_source_timeout;
    reg clk=0, rst_n=0, start=0;
    wire source_ready, source_busy, source_done, source_error;
    wire [15:0] credit_level;
    wire mem_rd_valid, packet_valid, packet_last;
    wire [20:0] mem_rd_addr;
    wire [31:0] packet_data;
    always #5 clk=~clk;
    m2_frame_packet_source #(.WIDTH(2),.HEIGHT(2),
        .CREDIT_TIMEOUT_CYCLES(16)) dut (
        .clk(clk),.rst_n(rst_n),.start(start),.frame_ready(1'b1),
        .frame_base(21'd0),.frame_id(16'd1),.image_id(8'd0),
        .credit_add(16'd0),.source_ready(source_ready),
        .source_busy(source_busy),.source_done(source_done),
        .source_error(source_error),.credit_level(credit_level),
        .mem_rd_valid(mem_rd_valid),.mem_rd_addr(mem_rd_addr),
        .mem_rd_ready(1'b1),.mem_rvalid(1'b0),.mem_rdata(32'd0),
        .packet_valid(packet_valid),.packet_data(packet_data),
        .packet_last(packet_last),.packet_ready(1'b1));
    initial begin
        repeat(4) @(negedge clk); rst_n=1;
        @(negedge clk); start=1;
        @(negedge clk); start=0;
        repeat(20) @(negedge clk);
        if(!source_error || !source_ready || source_busy || source_done ||
           mem_rd_valid || packet_valid)
            $fatal(1,"FAIL: no-credit timeout");
        $display("PASS: m2_frame_packet_source no-credit timeout");
        $finish;
    end
endmodule
