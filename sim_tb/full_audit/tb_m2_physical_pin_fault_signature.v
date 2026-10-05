`timescale 1ns/1ps
// Reproduces the exact board signature caused by a missing logical link_data[3]:
// the four-phase mailbox drains normally, but the B17E header is corrupted to
// B15E and m2_remote_frame_rx remains idle with no frame_begin/error.
module tb_m2_physical_pin_fault_signature;
    reg tx_clk=0, rx_clk=0, tx_rst_n=0, rx_rst_n=0;
    always #5 tx_clk=~tx_clk;
    always #7 rx_clk=~rx_clk;

    reg in_valid=0;
    reg [31:0] in_data=0;
    wire in_ready;
    wire [6:0] tx_pins;
    wire req, ack;
    reg fault_d3_low=0;
    wire [6:0] rx_pins = fault_d3_low ? {tx_pins[6:4],1'b0,tx_pins[2:0]} : tx_pins;
    wire mb_valid, mb_ready;
    wire [31:0] mb_word;
    wire frame_begin, frame_done, frame_error;
    wire [7:0] image_id;
    integer begin_count=0, err_count=0, word_count=0;
    reg [31:0] last_word=0;

    m2_gpio_mailbox_tx u_tx(
        .clk(tx_clk),.rst_n(tx_rst_n),.in_valid(in_valid),.in_data(in_data),.in_ready(in_ready),
        .data(tx_pins),.req(req),.ack(ack));
    m2_gpio_mailbox_rx u_rx(
        .clk(rx_clk),.rst_n(rx_rst_n),.data(rx_pins),.req(req),.ack(ack),
        .out_valid(mb_valid),.out_data(mb_word),.out_ready(mb_ready));
    m2_remote_frame_rx #(.PIXELS(4)) u_frame(
        .clk(rx_clk),.rst_n(rx_rst_n),.in_valid(mb_valid),.in_data(mb_word),.in_ready(mb_ready),
        .frame_begin(frame_begin),.frame_done(frame_done),.frame_error(frame_error),.image_id(image_id),
        .wr_valid(),.wr_addr(),.wr_data(),.wr_ready(1'b1),.busy());

    always @(posedge rx_clk) begin
        if (mb_valid && mb_ready) begin word_count=word_count+1; last_word=mb_word; end
        if (frame_begin) begin_count=begin_count+1;
        if (frame_error) err_count=err_count+1;
    end

    task send_word;
        input [31:0] value;
        integer guard;
        begin
            guard=0;
            @(negedge tx_clk);
            while(!in_ready && guard<1000) begin @(negedge tx_clk); guard=guard+1; end
            if(!in_ready) $fatal(1,"timeout waiting mailbox input ready");
            in_data=value; in_valid=1;
            @(negedge tx_clk); in_valid=0;
            guard=0;
            while(!in_ready && guard<5000) begin @(negedge tx_clk); guard=guard+1; end
            if(!in_ready) $fatal(1,"mailbox failed to drain word %h",value);
        end
    endtask

    task reset_both;
        begin
            tx_rst_n=0; rx_rst_n=0; in_valid=0;
            repeat(5) @(negedge tx_clk);
            tx_rst_n=1; rx_rst_n=1;
            repeat(8) @(negedge rx_clk);
        end
    endtask

    initial begin
        reset_both();
        fault_d3_low=0;
        send_word(32'hB17E005A);
        repeat(20) @(posedge rx_clk);
        if(begin_count!=1 || image_id!=8'h5A || err_count!=0)
            $fatal(1,"normal header failed begin=%0d id=%h err=%0d word=%h",begin_count,image_id,err_count,last_word);

        // Re-run with only logical data[3] forced low.  This is what happens
        // when J1-6 is wired but the RTL pin constraint puts data[3] on L12/J2.
        reset_both(); begin_count=0; err_count=0; word_count=0; last_word=0;
        fault_d3_low=1;
        send_word(32'hB17E005A);
        repeat(30) @(posedge rx_clk);
        if(word_count!=1) $fatal(1,"fault case mailbox did not drain; words=%0d",word_count);
        if(last_word!==32'hB15E0052)
            $fatal(1,"unexpected stuck-d3 signature got=%h expected=B15E0052",last_word);
        if(begin_count!=0 || err_count!=0)
            $fatal(1,"fault case should be silently ignored in IDLE begin=%0d err=%0d",begin_count,err_count);
        $display("PASS: missing link_data[3] reproduces board signature: B17E005A -> %h, TX drains, RX frame_begin stays 0",last_word);
        $finish;
    end

    initial begin #1000000; $fatal(1,"watchdog physical pin fault signature"); end
endmodule
