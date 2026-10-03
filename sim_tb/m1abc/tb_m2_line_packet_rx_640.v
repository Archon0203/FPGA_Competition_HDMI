`timescale 1ns/1ps
module tb_m2_line_packet_rx_640;
    reg clk=0, rst_n=0, tx_start=0, corrupt=0, bad_length=0;
    reg [15:0] payload_index=0;
    reg [7:0] packet_index=0;
    reg [15:0] cycle_count=0;
    wire in_ready, tx_valid, tx_last, tx_busy, tx_done, tx_payload_ready;
    wire [31:0] tx_data;
    wire [7:0] tx_sequence;
    wire line_valid, line_start, line_end, frame_end, frame_accept;
    wire [31:0] line_data;
    wire [15:0] frame_id, line_index;
    wire [7:0] image_id, expected_sequence;
    wire protocol_error, link_ready;
    wire line_ready = cycle_count[2:0] != 3'd3;
    wire meta2 = tx_valid && tx_data[31:24] == 8'd2 &&
                 tx_data[15:0] == 16'd640;
    wire [31:0] rx_data = (corrupt && tx_last) ? (tx_data ^ 32'd1) :
                          (bad_length && meta2) ? (tx_data ^ 32'd1) : tx_data;
    integer errors=0, accepted=0, packets=0, crc_errors=0;
    reg held=0;
    reg [31:0] held_data;
    reg held_start, held_end;

    always #5 clk=~clk;
    m2_line_packet_tx #(.PAYLOAD_WORDS(640)) tx (
        .clk(clk), .rst_n(rst_n), .line_start(tx_start),
        .frame_id(16'd7), .image_id(8'd2), .line_index(16'd0),
        .payload_valid(1'b1), .payload_data({packet_index,8'h00,payload_index}),
        .payload_ready(tx_payload_ready), .out_valid(tx_valid),
        .out_data(tx_data), .out_last(tx_last), .out_ready(in_ready),
        .busy(tx_busy), .packet_done(tx_done), .sequence(tx_sequence));
    m2_line_packet_rx #(.LINE_WORDS(640), .FRAME_LINES(1)) rx (
        .clk(clk), .rst_n(rst_n), .in_valid(tx_valid), .in_data(rx_data),
        .in_last(tx_last), .in_ready(in_ready),
        .line_valid(line_valid), .line_data(line_data), .line_ready(line_ready),
        .line_start(line_start), .line_end(line_end), .frame_end(frame_end),
        .frame_id(frame_id), .line_index(line_index), .image_id(image_id),
        .frame_accept(frame_accept), .protocol_error(protocol_error),
        .link_ready(link_ready), .expected_sequence(expected_sequence));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            payload_index <= 0; packet_index <= 0; cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1'b1;
            if (tx_start) payload_index <= 0;
            else if (tx_payload_ready) payload_index <= payload_index + 1'b1;
            if (tx_done) packet_index <= packet_index + 1'b1;
        end
    end

    always @(posedge clk) if (rst_n) begin
        if (protocol_error) crc_errors=crc_errors+1;
        if (held && (!line_valid || line_data !== held_data ||
                     line_start !== held_start || line_end !== held_end)) begin
            $display("ERROR: line changed under backpressure"); errors=errors+1;
        end
        held = line_valid && !line_ready;
        if (held) begin
            held_data=line_data; held_start=line_start; held_end=line_end;
        end
        if (line_valid && line_ready) begin
            if (line_data !== {((packets==0)?8'd0:
                                  (packets==1)?8'd2:8'd4),8'h00,accepted[15:0]}) begin
                $display("ERROR: pixel %0d value %h",accepted,line_data); errors=errors+1;
            end
            if (line_start !== (accepted==0) ||
                line_end !== (accepted==639) ||
                frame_end !== (accepted==639)) begin
                $display("ERROR: line sideband at %0d",accepted); errors=errors+1;
            end
            accepted=accepted+1;
            if (accepted==640) begin accepted=0; packets=packets+1; end
        end
    end

    task send_packet;
        input [1:0] mode;
        integer wait_count;
        begin
            @(negedge clk); corrupt=(mode==1); bad_length=(mode==2); tx_start=1;
            @(negedge clk); tx_start=0;
            wait_count=0;
            while (!tx_done && wait_count<5000) begin
                @(negedge clk); wait_count=wait_count+1;
            end
            if (wait_count==5000) begin $display("ERROR: TX timeout"); errors=errors+1; end
            @(negedge clk);
        end
    endtask

    initial begin
        repeat(4) @(negedge clk); rst_n=1;
        send_packet(0);
        repeat(900) @(negedge clk);
        if (packets!=1 || accepted!=0) begin
            $display("ERROR: first full line missing"); errors=errors+1;
        end
        send_packet(1);
        repeat(30) @(negedge clk);
        if (packets!=1 || crc_errors==0) begin
            $display("ERROR: corrupt line released or CRC not flagged"); errors=errors+1;
        end
        send_packet(0);
        repeat(900) @(negedge clk);
        if (packets!=2 || accepted!=0 || expected_sequence!=3) begin
            $display("ERROR: recovery failed packets=%0d seq=%0d",packets,expected_sequence);
            errors=errors+1;
        end
        send_packet(2);
        repeat(30) @(negedge clk);
        if(packets!=2 || crc_errors<2) begin
            $display("ERROR: bad length packet not rejected"); errors=errors+1;
        end
        send_packet(0);
        repeat(900) @(negedge clk);
        if(packets!=3 || accepted!=0 || expected_sequence!=5) begin
            $display("ERROR: length recovery failed packets=%0d seq=%0d",packets,expected_sequence);
            errors=errors+1;
        end
        if(errors==0) $display("PASS: m2_line_packet_rx_640 lines=%0d crc_errors=%0d",packets,crc_errors);
        else $fatal(1,"FAIL: m2_line_packet_rx_640 errors=%0d",errors);
        $finish;
    end
endmodule
