`timescale 1ns/1ps
module tb_m2_real_media_uart_bridge;
    reg clk=0, rst_n=0;
    always #10 clk=~clk;
    reg rx_frame_valid=0, rx_frame_error=0, rx_framing_error=0;
    reg [7:0] rx_frame_opcode=0; reg [2:0] rx_frame_length=0;
    reg [31:0] rx_frame_payload=0; reg frame_tx_busy=0;
    reg catalog_valid=0; reg [7:0] catalog_count=0;
    reg source_busy=0, source_done=0, source_valid=0, source_error=0; reg [7:0] source_error_code=0;
    reg [7:0] selected_image_id=0;
    wire frame_tx_request; wire [7:0] frame_tx_opcode; wire [2:0] frame_tx_length;
    wire [31:0] frame_tx_payload; wire open_request; wire [7:0] open_image_id;
    wire link_seen, fault, command_toggle, reply_toggle;
    integer checks=0;

    m2_real_media_uart_bridge dut(
      .clk(clk),.rst_n(rst_n),.rx_frame_valid(rx_frame_valid),
      .rx_frame_opcode(rx_frame_opcode),.rx_frame_length(rx_frame_length),
      .rx_frame_payload(rx_frame_payload),.rx_frame_error(rx_frame_error),
      .rx_framing_error(rx_framing_error),.frame_tx_busy(frame_tx_busy),
      .frame_tx_request(frame_tx_request),.frame_tx_opcode(frame_tx_opcode),
      .frame_tx_length(frame_tx_length),.frame_tx_payload(frame_tx_payload),
      .catalog_valid(catalog_valid),.catalog_count(catalog_count),
      .source_busy(source_busy),.source_done(source_done),.source_valid(source_valid),
      .source_error(source_error),
      .source_error_code(source_error_code),.selected_image_id(selected_image_id),
      .open_request(open_request),.open_image_id(open_image_id),.link_seen(link_seen),
      .fault(fault),.command_toggle(command_toggle),.reply_toggle(reply_toggle));

    task send_frame; input [7:0] op; input [2:0] len; input [31:0] payload; begin
      @(negedge clk); rx_frame_opcode=op; rx_frame_length=len; rx_frame_payload=payload; rx_frame_valid=1;
      @(negedge clk); rx_frame_valid=0;
    end endtask
    task expect_reply; input [7:0] op; input [7:0] status; input [7:0] err; begin
      while(!frame_tx_request) @(posedge clk);
      if(frame_tx_opcode!==op || frame_tx_length!==4 || frame_tx_payload[7:0]!==status || frame_tx_payload[31:24]!==err) begin
        $display("FAIL reply op=%h len=%0d payload=%h",frame_tx_opcode,frame_tx_length,frame_tx_payload); $fatal;
      end
      checks=checks+1; @(posedge clk);
    end endtask

    initial begin
      repeat(3) @(posedge clk); rst_n=1;
      catalog_valid=1; catalog_count=5; selected_image_id=0;
      send_frame(8'h00,0,0); expect_reply(8'h80,8'h01,0);
      send_frame(8'h01,1,32'd3);
      while(!open_request) @(posedge clk);
      if(open_image_id!==3) $fatal; checks=checks+1;
      expect_reply(8'h81,8'h02,0);
      // source_done may be a one-cycle pulse.  The bridge must still report
      // DONE later from the persistent source_valid/media_succeeded state.
      selected_image_id=3; source_valid=1; source_done=0;
      send_frame(8'h09,0,0); expect_reply(8'h89,8'h04,0);
      source_valid=0; source_error=1; source_error_code=8'h3c;
      send_frame(8'h00,0,0); expect_reply(8'h80,8'he0,8'h3c);
      source_error=0;
      send_frame(8'h01,1,32'd7); expect_reply(8'h81,8'he0,8'h04);
      $display("PASS: m2 real-media uart bridge checks=%0d",checks); $finish;
    end
endmodule
