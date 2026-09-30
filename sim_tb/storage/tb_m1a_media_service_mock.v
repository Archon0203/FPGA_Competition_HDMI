`timescale 1ns/1ps
`include "m1a_protocol.vh"

module tb_m1a_media_service_mock;
    reg clk=0, rst_n=0, cmd_valid=0, packet_ready=0;
    reg [7:0] cmd_opcode=0; reg [31:0] cmd_arg=0;
    wire cmd_ready, catalog_valid, descriptor_valid, status_valid, source_ready, source_busy, source_done, source_error, media_valid, media_line_start, media_line_end, media_frame_end;
    wire [7:0] catalog_count, descriptor_image_id, status_code, status_error, packet_image_id;
    wire [15:0] catalog_epoch, descriptor_width, descriptor_height, descriptor_frame_count, media_frame_id, media_line_index, credit_level;
    wire [1:0] descriptor_type; wire [31:0] descriptor_duration, media_data;
    integer errors=0, checks=0, packet_count=0;
    reg was_stalled=0;
    reg [31:0] held_data;
    reg held_line_start,held_line_end,held_frame_end;
    reg [15:0] held_frame_id,held_line_index;
    reg [7:0] held_image_id;
    always #5 clk=~clk;
    m1a_media_service_mock #(.MOCK_LINES(3),.WORDS_PER_LINE(2),.CATALOG_COUNT(4)) dut(
        .clk(clk),.rst_n(rst_n),.cmd_valid(cmd_valid),.cmd_opcode(cmd_opcode),.cmd_arg(cmd_arg),.cmd_ready(cmd_ready),
        .catalog_valid(catalog_valid),.catalog_count(catalog_count),.catalog_epoch(catalog_epoch),.descriptor_valid(descriptor_valid),
        .descriptor_image_id(descriptor_image_id),.descriptor_type(descriptor_type),.descriptor_width(descriptor_width),.descriptor_height(descriptor_height),.descriptor_frame_count(descriptor_frame_count),.descriptor_duration(descriptor_duration),
        .status_valid(status_valid),.status_code(status_code),.status_error(status_error),.source_ready(source_ready),.source_busy(source_busy),.source_done(source_done),.source_error(source_error),.credit_level(credit_level),
        .media_valid(media_valid),.media_ready(packet_ready),.media_data(media_data),.media_line_start(media_line_start),.media_line_end(media_line_end),.media_frame_end(media_frame_end),.media_frame_id(media_frame_id),.media_image_id(packet_image_id),.media_line_index(media_line_index));

    task cmd; input [7:0] op; input [31:0] arg; begin
        @(negedge clk); cmd_opcode=op; cmd_arg=arg; cmd_valid=1;
        while(!cmd_ready) @(negedge clk);
        @(negedge clk); cmd_valid=0;
    end endtask

    always @(posedge clk) begin
        if (was_stalled) begin
            checks=checks+1;
            if (!media_valid || media_data!==held_data || media_line_start!==held_line_start ||
                media_line_end!==held_line_end || media_frame_end!==held_frame_end ||
                media_frame_id!==held_frame_id || packet_image_id!==held_image_id ||
                media_line_index!==held_line_index) begin
                $display("ERROR media payload/sideband changed under backpressure"); errors=errors+1;
            end
        end
        was_stalled = media_valid && !packet_ready;
        if (was_stalled) begin
            held_data=media_data; held_line_start=media_line_start;
            held_line_end=media_line_end; held_frame_end=media_frame_end;
            held_frame_id=media_frame_id; held_image_id=packet_image_id;
            held_line_index=media_line_index;
        end
        if(media_valid && packet_ready) begin
            packet_count=packet_count+1;
            checks=checks+1;
            if(packet_count==1 && !media_line_start) begin $display("ERROR missing line start"); errors=errors+1; end
            if(packet_count==2 && !media_line_end) begin $display("ERROR missing line end"); errors=errors+1; end
            if(media_frame_end) begin checks=checks+1; end
        end
    end

    initial begin
        #20; rst_n=1; repeat(2) @(posedge clk);
        checks=checks+1; if(!catalog_valid || catalog_count!=4) begin $display("ERROR catalog"); errors=errors+1; end
        cmd(`M1A_CMD_OPEN,32'h2); @(posedge clk);
        checks=checks+1; if(!descriptor_valid || descriptor_image_id!=2 || descriptor_width!=640) begin $display("ERROR descriptor"); errors=errors+1; end
        cmd(`M1A_CMD_CREDIT,32'd3); cmd(`M1A_CMD_PLAY,0);
        repeat(2) @(negedge clk); packet_ready=0; repeat(3) @(negedge clk);
        checks=checks+1; if(!media_valid) begin $display("ERROR media beat not held"); errors=errors+1; end
        packet_ready=1; wait(source_done); checks=checks+1; if(packet_count!=6) begin $display("ERROR frame count=%0d",packet_count); errors=errors+1; end
        if(errors==0) $display("PASS: m1a_media_service_mock checks=%0d packets=%0d",checks,packet_count); else $display("FAIL: %0d errors",errors);
        $finish;
    end
endmodule
