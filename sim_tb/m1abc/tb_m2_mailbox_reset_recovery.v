`timescale 1ns/1ps
module tb_m2_mailbox_reset_recovery;
    reg tx_clk=0, rx_clk=0;
    always #20 tx_clk=~tx_clk; // 25 MHz
    always #17 rx_clk=~rx_clk; // intentionally asynchronous

    reg tx_rst_n=0, rx_rst_n=0;
    reg in_valid=0;
    reg [31:0] in_data=0;
    wire in_ready;
    wire [6:0] pins;
    wire req, ack;
    wire out_valid;
    wire [31:0] out_data;
    reg out_ready=1;

    integer received=0;
    reg [31:0] last_word=0;

    m2_gpio_mailbox_tx u_tx(
        .clk(tx_clk), .rst_n(tx_rst_n),
        .in_valid(in_valid), .in_data(in_data), .in_ready(in_ready),
        .data(pins), .req(req), .ack(ack));

    m2_gpio_mailbox_rx u_rx(
        .clk(rx_clk), .rst_n(rx_rst_n),
        .data(pins), .req(req), .ack(ack),
        .out_valid(out_valid), .out_data(out_data), .out_ready(out_ready));

    always @(posedge rx_clk) begin
        if(out_valid && out_ready) begin
            received = received + 1;
            last_word = out_data;
        end
    end

    task send_word;
        input [31:0] value;
        begin
            // Always align the stimulus to a TX falling edge before asserting
            // valid.  The previous version could enter this task while
            // in_ready was already high (for example immediately after the
            // RX reset-release sequence), assert/deassert in_valid entirely
            // between two TX rising edges, and therefore never present a
            // valid transfer to the DUT.  That was a testbench race, not a
            // mailbox deadlock.
            @(negedge tx_clk);
            while(!in_ready) @(negedge tx_clk);
            in_data=value;
            in_valid=1;
            @(negedge tx_clk);
            in_valid=0;
        end
    endtask

    task wait_word;
        input [31:0] value;
        integer base_count;
        begin
            base_count=received;
            while(received==base_count) @(posedge rx_clk);
            if(last_word!==value)
                $fatal(1,"expected %08x got %08x",value,last_word);
        end
    endtask

    initial begin
        repeat(5) @(negedge tx_clk);
        tx_rst_n=1;
        repeat(3) @(negedge rx_clk);
        rx_rst_n=1;

        // Basic word mapping after independently released resets.
        send_word(32'h12345678);
        wait_word(32'h12345678);

        // Reset only the receiver while a word is in flight.  The interrupted
        // word may be discarded, but the next explicit start-of-word must
        // restore framing without resetting the transmitter.
        send_word(32'hA5A55A5A);
        wait(req===1'b1);
        repeat(2) @(negedge rx_clk);
        rx_rst_n=0;
        repeat(3) @(negedge rx_clk);
        rx_rst_n=1;
        send_word(32'hB17E0003);
        wait_word(32'hB17E0003);

        // Reset only the transmitter while another word is in flight.  The
        // four-phase handshake must first return ack low, then deliver the
        // next word from symbol 0 with no stale-toggle loss.
        send_word(32'hCAFEBABE);
        wait(req===1'b1);
        repeat(2) @(negedge tx_clk);
        tx_rst_n=0;
        repeat(3) @(negedge tx_clk);
        tx_rst_n=1;
        send_word(32'hF17E0003);
        wait_word(32'hF17E0003);

        // Exercise output backpressure after recovery.  A complete 32-bit word
        // takes six symbols, and each symbol crosses the asynchronous req/ack
        // synchronizers.  Do not assume a fixed small number of RX clocks from
        // the input handshake to out_valid; first wait for the completed word,
        // then hold it stalled and verify that both valid and data remain stable.
        out_ready=0;
        send_word(32'h89ABCDEF);
        begin : wait_backpressured_word
            integer wait_cycles;
            reg [31:0] held_word;
            wait_cycles = 0;
            while(!out_valid && wait_cycles < 500) begin
                @(negedge rx_clk);
                wait_cycles = wait_cycles + 1;
            end
            if(!out_valid)
                $fatal(1,"timeout waiting for backpressured output word");
            if(out_data!==32'h89ABCDEF)
                $fatal(1,"backpressured output mismatch: got %08x",out_data);

            held_word = out_data;
            repeat(20) begin
                @(negedge rx_clk);
                if(!out_valid || out_data!==held_word)
                    $fatal(1,"output word did not remain stable under backpressure");
            end
        end
        out_ready=1;
        repeat(4) @(posedge rx_clk);

        $display("PASS: mailbox survives independent TX/RX reset and backpressure");
        $finish;
    end

    initial begin
        #5000000;
        $fatal(1,"watchdog");
    end
endmodule
