`timescale 1ns/1ps
`include "m1a_protocol.vh"
module tb_m1a_service_shell;
    reg service_clk=0,provider_clk=0,spi_clk=0;
    reg service_rst_n=0,provider_rst_n=0,spi_cs_n=1,spi_mosi=0;
    reg provider_valid=0,media_byte_ready=1,packet_ready=0;
    reg [7:0] provider_data=0;
    wire spi_miso,spi_rx_overflow,provider_ready,provider_overflow,media_byte_valid;
    wire [7:0] media_byte_data;
    wire media_valid,media_line_start,media_line_end,media_frame_end,source_ready,source_busy,source_done,source_error;
    wire [31:0] packet_data,descriptor_duration;
    wire [15:0] media_frame_id,media_line_index,catalog_epoch,descriptor_width,descriptor_height,descriptor_frame_count,credit_level;
    wire [7:0] media_image_id,catalog_count,descriptor_image_id,status_code,status_error;
    wire [1:0] descriptor_type;
    wire catalog_valid,descriptor_valid,status_valid;
    integer errors=0,checks=0,i;
    reg [15:0] crc;
    always #5 service_clk=~service_clk;
    always #3 provider_clk=~provider_clk;

    m1a_service_shell #(.MOCK_LINES(2),.WORDS_PER_LINE(2)) dut(
        .service_clk(service_clk),.service_rst_n(service_rst_n),.spi_clk(spi_clk),.spi_cs_n(spi_cs_n),.spi_mosi(spi_mosi),.spi_miso(spi_miso),.spi_rx_overflow(spi_rx_overflow),
        .provider_clk(provider_clk),.provider_rst_n(provider_rst_n),.provider_valid(provider_valid),.provider_data(provider_data),.provider_ready(provider_ready),.provider_overflow(provider_overflow),
        .media_byte_valid(media_byte_valid),.media_byte_data(media_byte_data),.media_byte_ready(media_byte_ready),
        .media_ready(packet_ready),.media_valid(media_valid),.media_data(packet_data),.media_line_start(media_line_start),.media_line_end(media_line_end),.media_frame_end(media_frame_end),.media_frame_id(media_frame_id),.media_image_id(media_image_id),.media_line_index(media_line_index),
        .catalog_valid(catalog_valid),.catalog_count(catalog_count),.catalog_epoch(catalog_epoch),.descriptor_valid(descriptor_valid),.descriptor_image_id(descriptor_image_id),.descriptor_type(descriptor_type),.descriptor_width(descriptor_width),.descriptor_height(descriptor_height),.descriptor_frame_count(descriptor_frame_count),.descriptor_duration(descriptor_duration),
        .status_valid(status_valid),.status_code(status_code),.status_error(status_error),.source_ready(source_ready),.source_busy(source_busy),.source_done(source_done),.source_error(source_error),.credit_level(credit_level));

    function [15:0] crc_byte; input [15:0] ci; input [7:0] d; reg [15:0] c; integer j; begin c=ci^{d,8'h00}; for(j=0;j<8;j=j+1) if(c[15]) c={c[14:0],1'b0}^16'h1021; else c={c[14:0],1'b0}; crc_byte=c; end endfunction

    task spi_byte; input [7:0] d; integer b; begin
        spi_cs_n=0; #2;
        for(b=7;b>=0;b=b-1) begin spi_mosi=d[b]; #3; spi_clk=1; #3; spi_clk=0; #3; end
        spi_cs_n=1; #3;
    end endtask

    task send_cmd_open; input [7:0] image; begin
        crc=`M1A_CRC_INIT;
        spi_byte(`M1A_FRAME_SOF); spi_byte(`M1A_CMD_OPEN); crc=crc_byte(crc,`M1A_CMD_OPEN);
        spi_byte(8'd1); crc=crc_byte(crc,8'd1); spi_byte(image); crc=crc_byte(crc,image);
        spi_byte(crc[15:8]); spi_byte(crc[7:0]);
    end endtask

    initial begin
        #20; service_rst_n=1; provider_rst_n=1;
        repeat(4) @(posedge service_clk);
        checks=checks+1; if(!catalog_valid || catalog_count!=4) begin $display("ERROR shell catalog"); errors=errors+1; end
        send_cmd_open(8'd1);
        wait(descriptor_valid); checks=checks+1; if(descriptor_image_id!=1 || descriptor_width!=640) begin $display("ERROR shell descriptor"); errors=errors+1; end
        @(negedge provider_clk); provider_data=8'hD3; provider_valid=1;
        @(negedge provider_clk); provider_valid=0;
        wait(media_byte_valid); checks=checks+1; if(media_byte_data!=8'hD3) begin $display("ERROR provider CDC"); errors=errors+1; end
        @(posedge service_clk);
        // Current mock is protocol-only; SPI open must not start output without credit/play.
        repeat(5) @(posedge service_clk);
        checks=checks+1; if(media_valid) begin $display("ERROR unexpected media beat"); errors=errors+1; end
        // SPI cannot apply byte-level backpressure; verify its overflow monitor
        // records an attempted byte while the ingress FIFO is full.
        force dut.spi_rx_valid=1'b1;
        force dut.cmd_fifo_full=1'b1;
        #2 spi_clk=1; #1;
        release dut.spi_rx_valid;
        release dut.cmd_fifo_full;
        spi_clk=0;
        checks=checks+1; if(!spi_rx_overflow) begin $display("ERROR SPI RX overflow was not reported"); errors=errors+1; end
        if(errors==0) $display("PASS: m1a_service_shell checks=%0d",checks); else $display("FAIL: %0d errors",errors);
        $finish;
    end
endmodule
