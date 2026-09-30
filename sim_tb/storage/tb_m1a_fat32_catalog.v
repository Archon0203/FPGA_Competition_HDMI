`timescale 1ns/1ps
`include "m1a_protocol.vh"

module tb_m1a_fat32_catalog;
    localparam integer SECT=512;
    localparam [31:0] BOOT_LBA=2048, ROOT_LBA=2280;
    reg clk=0, rst_n=0, scan_start=0;
    wire sector_req, scan_done, scan_ok;
    wire [31:0] sector_lba;
    reg sector_ready=0, din_valid=0;
    reg [7:0] din=0;
    wire [4:0] scan_file_count;
    reg query_valid=0;
    reg [7:0] query_image_id=0;
    wire query_ready, descriptor_valid, error_valid, catalog_valid;
    wire [7:0] descriptor_image_id, error_code, catalog_count;
    wire [1:0] descriptor_type;
    wire [31:0] descriptor_cluster, descriptor_size, descriptor_fat, descriptor_data;
    wire [7:0] descriptor_spc;
    wire [15:0] descriptor_epoch, catalog_epoch;
    reg [7:0] disk [0:3][0:SECT-1];
    reg [8:0] stream_index=0;
    reg [1:0] selected=0;
    reg request_d=0;
    reg [31:0] previous_lba=32'hFFFFFFFF;
    integer errors=0, checks=0, i, j;

    always #5 clk=~clk;
    m1a_fat32_catalog #(.FILE_MAX(8)) dut (
        .clk(clk), .rst_n(rst_n), .scan_start(scan_start),
        .sector_req(sector_req), .sector_lba(sector_lba),
        .sector_ready(sector_ready), .din_valid(din_valid), .din(din),
        .scan_done(scan_done), .scan_ok(scan_ok), .scan_file_count(scan_file_count),
        .query_valid(query_valid), .query_image_id(query_image_id), .query_ready(query_ready),
        .descriptor_valid(descriptor_valid), .descriptor_image_id(descriptor_image_id),
        .descriptor_type(descriptor_type), .descriptor_cluster(descriptor_cluster),
        .descriptor_size(descriptor_size), .descriptor_fat_lba_base(descriptor_fat),
        .descriptor_data_lba_base(descriptor_data),
        .descriptor_sectors_per_cluster(descriptor_spc), .descriptor_epoch(descriptor_epoch),
        .error_valid(error_valid), .error_code(error_code), .catalog_valid(catalog_valid),
        .catalog_count(catalog_count), .catalog_epoch(catalog_epoch)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stream_index<=0; selected<=0; request_d<=0; previous_lba<=32'hFFFFFFFF;
            sector_ready<=0; din_valid<=0; din<=0;
        end else begin
            request_d<=sector_req;
            if (sector_req && (!request_d || sector_lba!=previous_lba)) begin
                previous_lba<=sector_lba;
                stream_index<=0;
                selected <= (sector_lba==0) ? 0 :
                            ((sector_lba==BOOT_LBA) ? 1 :
                            ((sector_lba==ROOT_LBA) ? 2 : 3));
                sector_ready<=1;
                din_valid<=1;
            end else if (sector_req && sector_ready && stream_index<SECT-1) begin
                stream_index<=stream_index+1'b1;
                din<=disk[selected][stream_index+1'b1];
                din_valid<=1;
            end else begin
                sector_ready<=0;
                din_valid<=0;
            end
            if (sector_req && (!request_d || sector_lba!=previous_lba))
                din<=disk[(sector_lba==0)?0:
                          ((sector_lba==BOOT_LBA)?1:
                          ((sector_lba==ROOT_LBA)?2:3))][0];
        end
    end

    task expect;
        input condition; input [255:0] label;
        begin checks=checks+1; if(!condition) begin $display("ERROR: %0s",label); errors=errors+1; end end
    endtask

    initial begin
        for(i=0;i<4;i=i+1) for(j=0;j<SECT;j=j+1) disk[i][j]=0;
        // MBR: FAT32 LBA partition begins at 2048.
        disk[0][450]=8'h0C; disk[0][454]=8'h00; disk[0][455]=8'h08;
        // BPB: bps=512, spc=2, reserved=32, two FATs of 100 sectors, root cluster=2.
        disk[1][11]=0; disk[1][12]=2; disk[1][13]=2;
        disk[1][14]=32; disk[1][15]=0; disk[1][16]=2;
        disk[1][36]=100; disk[1][37]=0; disk[1][38]=0; disk[1][39]=0;
        disk[1][44]=2; disk[1][45]=0; disk[1][46]=0; disk[1][47]=0;
        // First root-cluster sector has no end marker; scanner must continue.
        for(i=0;i<SECT;i=i+32) disk[2][i]=8'hE5;
        // One BMP entry in the second sector: cluster 7, size 0x1234.
        disk[3][0]=8'h54; disk[3][1]=8'h45; disk[3][2]=8'h53; disk[3][3]=8'h54;
        disk[3][8]=8'h42; disk[3][9]=8'h4D; disk[3][10]=8'h50;
        disk[3][11]=8'h20; disk[3][26]=7; disk[3][28]=8'h34; disk[3][29]=8'h12;
        disk[3][32]=0;

        #12; rst_n=1;
        @(negedge clk); scan_start=1;
        @(negedge clk); scan_start=0;
        i=0; while(!catalog_valid && i<5000) begin @(negedge clk); i=i+1; end
        expect(catalog_valid && scan_done && scan_ok,"FAT32 scan publishes catalog");
        expect(scan_file_count==1 && catalog_count==1,"one file indexed");
        expect(sector_lba==ROOT_LBA+1,"scan continues to second root-cluster sector");
        @(negedge clk); query_image_id=0; query_valid=1;
        while(!query_ready) @(negedge clk);
        @(negedge clk); query_valid=0;
        @(posedge clk); #1;
        expect(descriptor_valid && descriptor_image_id==0,"descriptor returned");
        expect(descriptor_type==1 && descriptor_cluster==7 && descriptor_size==32'h1234,"file metadata");
        expect(descriptor_fat==2080 && descriptor_data==2280 && descriptor_spc==2,"BPB geometry");
        expect(descriptor_epoch==catalog_epoch,"catalog epoch carried with descriptor");
        if(errors==0) $display("PASS: m1a_fat32_catalog checks=%0d",checks);
        else $display("FAIL: m1a_fat32_catalog errors=%0d checks=%0d",errors,checks);
        $finish;
    end
endmodule
