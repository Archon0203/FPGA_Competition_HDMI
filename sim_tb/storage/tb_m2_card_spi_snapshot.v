`timescale 1ns/1ps
module tb_m2_card_spi_snapshot;
    reg clk = 0, rst_n = 0, cmd_valid = 0, sd_miso = 1;
    wire cmd_ready, sd_ncs, sd_sclk, sd_mosi;
    wire mem_wr_valid, source_done, source_error;
    wire [20:0] mem_wr_addr;
    wire [31:0] mem_wr_data;
    wire [7:0] catalog_count, error_code;
    reg [1023:0] card_path;
    reg [7:0] response [0:530];
    reg [7:0] command [0:5];
    reg [7:0] sector_data [0:511];
    reg [7:0] bmp_bytes [0:921653];
    reg [7:0] mosi_shift = 0, received_byte;
    reg [2:0] bit_count = 0;
    integer card_fd, seek_result, read_count;
    integer head = 0, tail = 0, command_count = 0;
    integer cmd17_count = 0, writes = 0, j;
    reg [31:0] expected_rgb;
    reg [20:0] expected_addr;
    reg [31:0] command_lba;

    always #5 clk = ~clk;

    m2_slave_tf_media_core #(
        .SPI_CLK_DIV(4), .SPI_INIT_CLK_DIV(32), .SPI_MODE3(1),
        .WIDTH(640), .HEIGHT(480)
    ) dut (
        .clk(clk), .rst_n(rst_n), .scan_start(1'b0),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready), .cmd_image_id(8'd0),
        .frame_base(21'd0), .sd_ncs(sd_ncs), .sd_sclk(sd_sclk),
        .sd_mosi(sd_mosi), .sd_miso(sd_miso),
        .mem_wr_valid(mem_wr_valid), .mem_wr_addr(mem_wr_addr),
        .mem_wr_data(mem_wr_data), .mem_wr_ready(1'b1),
        .catalog_valid(), .catalog_count(catalog_count), .catalog_epoch(),
        .descriptor_valid(), .descriptor_image_id(),
        .descriptor_width(), .descriptor_height(),
        .source_ready(), .source_busy(), .source_done(source_done),
        .source_error(source_error), .error_code(error_code)
    );

    always @(negedge sd_sclk or posedge sd_ncs) begin
        if (sd_ncs) sd_miso <= 1;
        else sd_miso <= head < tail ? response[head][7-bit_count] : 1'b1;
    end

    always @(posedge sd_sclk or posedge sd_ncs) begin
        if (sd_ncs) begin
            bit_count = 0;
            mosi_shift = 0;
            command_count = 0;
            head = 0;
            tail = 0;
        end else begin
            mosi_shift = {mosi_shift[6:0], sd_mosi};
            if (bit_count == 7) begin
                received_byte = mosi_shift;
                bit_count = 0;
                if (head < tail) head = head + 1;
                if (command_count == 0) begin
                    if (received_byte[7:6] == 2'b01) begin
                        command[0] = received_byte;
                        command_count = 1;
                    end
                end else begin
                    command[command_count] = received_byte;
                    if (command_count == 5) begin
                        if (command[5][0] !== 1'b1)
                            $fatal(1, "SD command end bit must be 1, final byte=%02x", command[5]);
                        command_count = 0;
                        case (command[0][5:0])
                            0: begin response[tail] = 8'h01; tail = tail + 1; end
                            8: begin
                                response[tail] = 8'h01;
                                response[tail+1] = 0;
                                response[tail+2] = 0;
                                response[tail+3] = 1;
                                response[tail+4] = 8'haa;
                                tail = tail + 5;
                            end
                            55: begin response[tail] = 8'h01; tail = tail + 1; end
                            41: begin response[tail] = 0; tail = tail + 1; end
                            17: begin
                                command_lba = {command[1],command[2],command[3],command[4]};
                                seek_result = $fseek(card_fd, command_lba * 512, 0);
                                if (seek_result != 0)
                                    $fatal(1, "SPI model seek failed LBA=%0d", command_lba);
                                read_count = $fread(sector_data, card_fd, 0, 512);
                                if (read_count != 512)
                                    $fatal(1, "SPI model short read LBA=%0d", command_lba);
                                response[tail] = 8'hff;
                                response[tail+1] = 0;
                                response[tail+2] = 8'hff;
                                response[tail+3] = 8'hfe;
                                for (j=0; j<512; j=j+1)
                                    response[tail+4+j] = sector_data[j];
                                response[tail+516] = 8'h12;
                                response[tail+517] = 8'h34;
                                tail = tail + 518;
                                cmd17_count = cmd17_count + 1;
                            end
                            default: $fatal(1, "unexpected SD command %0d", command[0][5:0]);
                        endcase
                    end else command_count = command_count + 1;
                end
            end else bit_count = bit_count + 1'b1;
        end
    end

    always @(posedge clk) if (rst_n && mem_wr_valid) begin
        if (writes >= 307200) $fatal(1, "extra SPI framebuffer pixel");
        expected_rgb = {8'h00, bmp_bytes[54+writes*3+2],
                        bmp_bytes[54+writes*3+1], bmp_bytes[54+writes*3]};
        expected_addr = (479 - writes/640)*640 + writes%640;
        if (mem_wr_addr !== expected_addr || mem_wr_data !== expected_rgb)
            $fatal(1, "SPI real BMP pixel mismatch n=%0d addr=%0d expected=%0d data=%h expected=%h",
                   writes, mem_wr_addr, expected_addr, mem_wr_data, expected_rgb);
        writes <= writes + 1;
    end

    initial begin
        if (!$value$plusargs("CARD_IMAGE=%s", card_path))
            $fatal(1, "pass +CARD_IMAGE=<raw card snapshot>");
        card_fd = $fopen(card_path, "rb");
        if (!card_fd) $fatal(1, "cannot open card snapshot");
        seek_result = $fseek(card_fd, 22336 * 512, 0);
        if (seek_result != 0) $fatal(1, "cannot seek to first BMP cluster");
        read_count = $fread(bmp_bytes, card_fd, 0, 921654);
        if (read_count != 921654) $fatal(1, "cannot load BMP golden pixels");
        repeat (4) @(negedge clk);
        rst_n = 1;
        wait(cmd_ready || source_error);
        if (!cmd_ready || catalog_count != 5)
            $fatal(1, "SPI catalog failed count=%0d code=%h reads=%0d",
                   catalog_count, error_code, cmd17_count);
        @(negedge clk); cmd_valid = 1;
        @(negedge clk); cmd_valid = 0;
        wait(source_done || source_error);
        if (!source_done || source_error || writes != 307200)
            $fatal(1, "SPI BMP failed code=%h writes=%0d reads=%0d",
                   error_code, writes, cmd17_count);
        $display("PASS: real card bit-level SPI BMP writes=%0d reads=%0d",
                 writes, cmd17_count);
        $fclose(card_fd);
        $finish;
    end

    initial begin
        #1500000000;
        $fatal(1, "real card bit-level SPI timeout reads=%0d writes=%0d code=%h",
               cmd17_count, writes, error_code);
    end
endmodule
