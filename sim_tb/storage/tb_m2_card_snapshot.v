`timescale 1ns/1ps
module tb_m2_card_snapshot;
    reg clk = 0, rst_n = 0, cmd_valid = 0;
    wire cmd_ready, sector_req, sector_consume_ready;
    wire [31:0] sector_lba;
    reg streaming = 0;
    reg [8:0] byte_index = 0;
    reg [7:0] sector_data [0:511];
    reg [7:0] bmp_bytes [0:921653];
    reg [1023:0] card_path;
    integer card_fd, seek_result, read_count;
    integer cycles = 0, writes = 0, pauses = 0, requests = 0;
    integer first_protocol_cycle = -1;
    reg [31:0] first_protocol_lba = 0;
    reg [31:0] first_protocol_remaining = 0;
    reg [5:0] first_protocol_fifo = 0;
    reg [11:0] stall_phase = 0;
    reg stall_writes = 0;
    reg corrupt_header = 0;
    reg drop_flow_control = 0;
    wire byte_enable = drop_flow_control || sector_consume_ready;
    reg [31:0] expected_rgb;
    reg [20:0] expected_addr;
    wire mem_wr_ready = !stall_writes || stall_phase >= 12'd1600;
    wire mem_wr_valid, source_done, source_error, catalog_valid;
    wire [20:0] mem_wr_addr;
    wire [31:0] mem_wr_data;
    wire [7:0] catalog_count, error_code;

    always #5 clk = ~clk;

    m2_real_media_service dut (
        .clk(clk), .rst_n(rst_n), .scan_start(1'b0),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready), .cmd_image_id(8'd0),
        .frame_base(21'd0), .sector_req(sector_req), .sector_lba(sector_lba),
        .sector_consume_ready(sector_consume_ready),
        .sector_ready(streaming), .sector_idle(!streaming),
        .sector_din_valid(streaming && byte_enable),
        .sector_din(sector_data[byte_index]), .sector_error(1'b0),
        .mem_wr_valid(mem_wr_valid), .mem_wr_addr(mem_wr_addr),
        .mem_wr_data(mem_wr_data), .mem_wr_ready(mem_wr_ready),
        .catalog_valid(catalog_valid), .catalog_count(catalog_count),
        .catalog_epoch(), .descriptor_valid(), .descriptor_image_id(),
        .descriptor_width(), .descriptor_height(), .source_ready(),
        .source_busy(), .source_done(source_done),
        .source_error(source_error), .error_code(error_code)
    );

    always @(posedge clk) begin
        if (rst_n) begin
            cycles <= cycles + 1;
            stall_phase <= stall_phase + 1'b1;
            if (streaming && !sector_consume_ready) pauses <= pauses + 1;
            if (mem_wr_valid && mem_wr_ready) begin
                if (writes >= 307200)
                    $fatal(1, "extra framebuffer pixel");
                expected_rgb = {8'h00, bmp_bytes[54+writes*3+2],
                                bmp_bytes[54+writes*3+1], bmp_bytes[54+writes*3]};
                expected_addr = (479 - writes/640)*640 + writes%640;
                if (!drop_flow_control &&
                    (mem_wr_addr !== expected_addr || mem_wr_data !== expected_rgb))
                    $fatal(1, "real BMP pixel mismatch n=%0d addr=%0d expected=%0d data=%h expected=%h",
                           writes, mem_wr_addr, expected_addr, mem_wr_data, expected_rgb);
                writes <= writes + 1;
            end
            if (dut.u_loader.protocol_error && first_protocol_cycle < 0) begin
                first_protocol_cycle <= cycles;
                first_protocol_lba <= sector_lba;
                first_protocol_remaining <= dut.u_loader.u_file_reader.remaining;
                first_protocol_fifo <= dut.u_loader.u_framebuffer_writer.fifo_count;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            streaming <= 0;
            byte_index <= 0;
        end else if (!sector_req) begin
            streaming <= 0;
            byte_index <= 0;
        end else if (!streaming) begin
            seek_result = $fseek(card_fd, sector_lba * 512, 0);
            if (seek_result != 0)
                $fatal(1, "card snapshot seek failed LBA=%0d", sector_lba);
            read_count = $fread(sector_data, card_fd, 0, 512);
            if (read_count != 512)
                $fatal(1, "card snapshot short read LBA=%0d n=%0d", sector_lba, read_count);
            if (corrupt_header && sector_lba == 32'd22336)
                sector_data[18] = 8'h81;
            requests <= requests + 1;
            streaming <= 1;
            byte_index <= 0;
        end else if (byte_enable) begin
            if (byte_index == 9'd511) streaming <= 0;
            else byte_index <= byte_index + 1'b1;
        end
    end

    initial begin
        if (!$value$plusargs("CARD_IMAGE=%s", card_path))
            $fatal(1, "pass +CARD_IMAGE=<raw card snapshot>");
        stall_writes = $test$plusargs("STALL_WRITES");
        corrupt_header = $test$plusargs("CORRUPT_HEADER");
        drop_flow_control = $test$plusargs("DROP_FLOW_CONTROL");
        card_fd = $fopen(card_path, "rb");
        if (!card_fd) $fatal(1, "cannot open card snapshot");
        seek_result = $fseek(card_fd, 22336 * 512, 0);
        if (seek_result != 0) $fatal(1, "cannot seek to first BMP cluster");
        read_count = $fread(bmp_bytes, card_fd, 0, 921654);
        if (read_count != 921654) $fatal(1, "cannot load BMP golden pixels");
        repeat (4) @(negedge clk);
        rst_n = 1;
        while (!cmd_ready && !source_error && cycles < 200000) @(negedge clk);
        if (!cmd_ready || catalog_count != 5)
            $fatal(1, "real card catalog failed ready=%b count=%0d code=%h requests=%0d",
                   cmd_ready, catalog_count, error_code, requests);
        @(negedge clk); cmd_valid = 1;
        @(negedge clk); cmd_valid = 0;
        while (!source_done && !source_error && cycles < 5000000) @(negedge clk);
        if (corrupt_header) begin
            if (!source_error || error_code != 8'h3B || writes != 0)
                $fatal(1, "corrupt BMP header classification failed code=%h writes=%0d",
                       error_code, writes);
            $display("PASS: corrupt real-card BMP header classified 0x3B");
            $fclose(card_fd);
            $finish;
        end
        if (drop_flow_control) begin
            if (!source_error || error_code != 8'h3D)
                $fatal(1, "writer overflow classification failed code=%h writes=%0d",
                       error_code, writes);
            $display("PASS: unthrottled real-card stream classified overflow 0x3D");
            $fclose(card_fd);
            $finish;
        end
        if (!source_done || source_error || writes != 307200)
            $fatal(1, "real card BMP failed done=%b err=%b code=%h writes=%0d requests=%0d first_protocol_cycle=%0d lba=%0d remaining=%0d fifo=%0d",
                   source_done, source_error, error_code, writes, requests,
                   first_protocol_cycle, first_protocol_lba,
                   first_protocol_remaining, first_protocol_fifo);
        $display("PASS: real card FAT32/BMP writes=%0d requests=%0d pauses=%0d stalls=%b",
                 writes, requests, pauses, stall_writes);
        $fclose(card_fd);
        $finish;
    end
endmodule
