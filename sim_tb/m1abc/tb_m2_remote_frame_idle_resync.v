`timescale 1ns/1ps
module tb_m2_remote_frame_idle_resync;
    reg clk=0, rst_n=0;
    reg in_valid=0;
    reg [31:0] in_data=0;
    wire in_ready;
    wire frame_begin, frame_done, frame_error;
    wire [7:0] image_id;
    wire wr_valid;
    wire [20:0] wr_addr;
    wire [31:0] wr_data;
    reg wr_ready=1;
    wire busy;
    integer errors=0;
    integer error_pulses=0;
    integer begin_pulses=0;
    integer done_pulses=0;

    always #20 clk=~clk;

    m2_remote_frame_rx #(.PIXELS(1)) dut(
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_data(in_data),
        .in_ready(in_ready), .frame_begin(frame_begin), .frame_done(frame_done),
        .frame_error(frame_error), .image_id(image_id), .wr_valid(wr_valid),
        .wr_addr(wr_addr), .wr_data(wr_data), .wr_ready(wr_ready), .busy(busy));

    function [31:0] crc_word;
        input [31:0] crc, value;
        integer k; reg [31:0] c;
        begin
            c=crc;
            for(k=31;k>=0;k=k-1)
                c={c[30:0],1'b0} ^ ((c[31]^value[k]) ? 32'h04c11db7 : 32'd0);
            crc_word=c;
        end
    endfunction

    always @(posedge clk) begin
        if(frame_error) error_pulses=error_pulses+1;
        if(frame_begin) begin_pulses=begin_pulses+1;
        if(frame_done) done_pulses=done_pulses+1;
    end

    task push;
        input [31:0] w;
        begin
            @(negedge clk);
            while(!in_ready) @(negedge clk);
            in_data=w; in_valid=1;
            @(negedge clk);
            in_valid=0;
        end
    endtask

    reg [31:0] crc;
    initial begin
        repeat(4) @(negedge clk);
        rst_n=1;

        // Simulate stale complete words left after a one-sided mailbox reset.
        push(32'h12345678);
        push(32'h40000000);
        push(32'hdeadbeef);
        repeat(3) @(posedge clk);
        if(error_pulses!=0) begin
            $display("FAIL: idle garbage raised frame_error pulses=%0d",error_pulses);
            errors=errors+1;
        end

        // Then send one valid one-pixel frame.  It must be accepted normally.
        crc=32'hffffffff;
        push(32'hb17e0005); crc=crc_word(crc,32'hb17e0005);
        push({11'h400,21'd0}); crc=crc_word(crc,{11'h400,21'd0});
        push(32'h00abcdef); crc=crc_word(crc,32'h00abcdef);
        push(32'hf17e0005);
        push(crc);
        repeat(5) @(posedge clk);

        if(begin_pulses!=1 || done_pulses!=1 || error_pulses!=0 || image_id!=8'h05) begin
            $display("FAIL: resync begin=%0d done=%0d err=%0d id=%0d",begin_pulses,done_pulses,error_pulses,image_id);
            errors=errors+1;
        end
        if(errors==0)
            $display("PASS: remote-frame idle garbage is discarded and next header resynchronizes");
        else
            $fatal(1,"idle resync errors=%0d",errors);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1,"watchdog");
    end
endmodule
