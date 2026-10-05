`timescale 1ns/1ps
// Deep transport regression: full 640x480 addressed frame, asynchronous clocks,
// four-phase GPIO mailbox, deterministic RX backpressure, CRC, no duplicate/missing addresses.
module tb_m2_full_frame_mailbox_640x480;
    localparam integer PIXELS=307200;
    reg tx_clk=0, rx_clk=0, tx_rst_n=0, rx_rst_n=0;
    always #3 tx_clk=~tx_clk;
    always #4 rx_clk=~rx_clk;

    reg frame_begin=0, frame_done=0, frame_error=0;
    reg [7:0] image_id=8'h2A;
    reg wr_valid=0;
    reg [20:0] wr_addr=0;
    reg [31:0] wr_data=0;
    wire wr_ready;
    wire tx_valid, tx_ready, tx_busy;
    wire [31:0] tx_word;
    wire [6:0] pins;
    wire req, ack;
    wire mb_valid, mb_ready;
    wire [31:0] mb_word;
    wire rx_begin, rx_done, rx_error, rx_wr_valid, rx_busy;
    wire [7:0] rx_id;
    wire [20:0] rx_wr_addr;
    wire [31:0] rx_wr_data;
    reg rx_wr_ready=0;
    reg [15:0] lfsr=16'hACE1;
    reg [PIXELS-1:0] seen;
    integer recv_count=0, duplicates=0, data_errors=0, begin_count=0, done_count=0, error_count=0;
    integer i, guard;

    function [31:0] pattern;
        input [20:0] a;
        begin pattern={3'b000,a[20:16],a[15:8]^8'hA5,a[7:0]^8'h5A,a[7:0]+a[15:8]}; end
    endfunction

    m2_remote_frame_tx u_ftx(.clk(tx_clk),.rst_n(tx_rst_n),.frame_begin(frame_begin),.image_id(image_id),
        .wr_valid(wr_valid),.wr_addr(wr_addr),.wr_data(wr_data),.wr_ready(wr_ready),
        .frame_done(frame_done),.frame_error(frame_error),.out_valid(tx_valid),.out_data(tx_word),.out_ready(tx_ready),.busy(tx_busy));
    m2_gpio_mailbox_tx u_mtx(.clk(tx_clk),.rst_n(tx_rst_n),.in_valid(tx_valid),.in_data(tx_word),.in_ready(tx_ready),.data(pins),.req(req),.ack(ack));
    m2_gpio_mailbox_rx u_mrx(.clk(rx_clk),.rst_n(rx_rst_n),.data(pins),.req(req),.ack(ack),.out_valid(mb_valid),.out_data(mb_word),.out_ready(mb_ready));
    m2_remote_frame_rx #(.PIXELS(PIXELS)) u_frx(.clk(rx_clk),.rst_n(rx_rst_n),.in_valid(mb_valid),.in_data(mb_word),.in_ready(mb_ready),
        .frame_begin(rx_begin),.frame_done(rx_done),.frame_error(rx_error),.image_id(rx_id),
        .wr_valid(rx_wr_valid),.wr_addr(rx_wr_addr),.wr_data(rx_wr_data),.wr_ready(rx_wr_ready),.busy(rx_busy));

    always @(posedge rx_clk or negedge rx_rst_n) begin
        if(!rx_rst_n) begin lfsr<=16'hACE1; rx_wr_ready<=0; end
        else begin
            lfsr <= {lfsr[14:0],lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};
            // Roughly 75% ready, with deterministic bursts of backpressure.
            rx_wr_ready <= lfsr[0] | lfsr[1];
        end
    end

    always @(posedge rx_clk) if(rx_rst_n) begin
        if(rx_begin) begin_count=begin_count+1;
        if(rx_done) done_count=done_count+1;
        if(rx_error) error_count=error_count+1;
        if(rx_wr_valid && rx_wr_ready) begin
            if(rx_wr_addr>=PIXELS) $fatal(1,"out-of-range address %0d",rx_wr_addr);
            if(seen[rx_wr_addr]) duplicates=duplicates+1;
            seen[rx_wr_addr]=1'b1;
            if(rx_wr_data!==pattern(rx_wr_addr)) begin
                data_errors=data_errors+1;
                if(data_errors<8) $display("DATA ERROR addr=%0d got=%h exp=%h",rx_wr_addr,rx_wr_data,pattern(rx_wr_addr));
            end
            recv_count=recv_count+1;
        end
    end

    initial begin
        seen={PIXELS{1'b0}};
        repeat(10) @(negedge tx_clk); tx_rst_n=1;
        repeat(10) @(negedge rx_clk); rx_rst_n=1;
        @(negedge tx_clk); frame_begin=1;
        @(negedge tx_clk); frame_begin=0;
        for(i=0;i<PIXELS;i=i+1) begin
            guard=0;
            while(!wr_ready && guard<200000) begin @(negedge tx_clk); guard=guard+1; end
            if(!wr_ready) $fatal(1,"timeout wr_ready pixel=%0d",i);
            wr_addr=i[20:0]; wr_data=pattern(i[20:0]); wr_valid=1;
            @(negedge tx_clk); wr_valid=0;
        end
        guard=0;
        while(!wr_ready && guard<200000) begin @(negedge tx_clk); guard=guard+1; end
        @(negedge tx_clk); frame_done=1;
        @(negedge tx_clk); frame_done=0;
        guard=0;
        while(done_count==0 && error_count==0 && guard<2000000) begin @(negedge rx_clk); guard=guard+1; end
        if(error_count!=0 || done_count!=1 || begin_count!=1 || rx_id!=image_id || recv_count!=PIXELS || duplicates!=0 || data_errors!=0)
            $fatal(1,"full-frame fail begin=%0d done=%0d err=%0d id=%h recv=%0d dup=%0d dataerr=%0d",begin_count,done_count,error_count,rx_id,recv_count,duplicates,data_errors);
        $display("PASS: full 640x480 remote frame through async GPIO mailbox pixels=%0d begin=%0d done=%0d",recv_count,begin_count,done_count);
        $finish;
    end

    initial begin #2000000000; $fatal(1,"watchdog full 640x480 mailbox recv=%0d",recv_count); end
endmodule
