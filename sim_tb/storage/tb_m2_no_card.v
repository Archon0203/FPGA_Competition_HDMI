`timescale 1ns/1ps
module tb_m2_no_card;
    reg clk=0, rst_n=0, scan_start=0;
    always #20 clk=~clk;
    wire sd_ncs, sd_sclk, sd_mosi;
    wire catalog_valid, source_done, source_error;
    wire [7:0] error_code;
    wire [7:0] sector_error_detail;
    integer errors_seen=0;

    m2_slave_tf_media_core #(.SPI_CLK_DIV(4), .SPI_INIT_CLK_DIV(32),
                             .SPI_MODE3(1)) dut (
        .clk(clk), .rst_n(rst_n), .scan_start(scan_start),
        .cmd_valid(1'b0), .cmd_ready(), .cmd_image_id(8'd0),
        .frame_base(21'd0),
        .sd_ncs(sd_ncs), .sd_sclk(sd_sclk), .sd_mosi(sd_mosi),
        .sd_miso(1'b1),
        .mem_wr_valid(), .mem_wr_addr(), .mem_wr_data(),
        .mem_wr_ready(1'b1),
        .catalog_valid(catalog_valid), .catalog_count(), .catalog_epoch(),
        .descriptor_valid(), .descriptor_image_id(),
        .descriptor_width(), .descriptor_height(),
        .source_ready(), .source_busy(), .source_done(source_done),
        .source_error(source_error), .error_code(error_code),
        .sector_error_detail(sector_error_detail));

    always @(posedge clk) begin
        if (rst_n && source_error) begin
            if (error_code !== 8'h11)
                $fatal(1, "unexpected no-card error code %h", error_code);
            if (sector_error_detail !== 8'h41)
                $fatal(1, "unexpected no-card physical detail %h", sector_error_detail);
            errors_seen = errors_seen + 1;
        end
        if (rst_n && (catalog_valid || source_done))
            $fatal(1, "no-card scan reported a frame");
    end

    initial begin
        #100 rst_n=1;
        wait (errors_seen == 1);
        repeat (4) @(negedge clk);
        scan_start=1;
        @(negedge clk) scan_start=0;
        wait (errors_seen == 2);
        $display("PASS: m2_no_card bounded failure and rescan errors=%0d", errors_seen);
        $finish;
    end
    initial begin
        #20000000;
        $fatal(1, "no-card failure did not terminate");
    end
endmodule
