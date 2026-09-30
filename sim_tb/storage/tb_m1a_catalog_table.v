`timescale 1ns/1ps
`include "m1a_protocol.vh"

module tb_m1a_catalog_table;
    reg clk=0, rst_n=0;
    reg scan_start=0, scan_done=0, scan_ok=0, entry_valid=0;
    reg [4:0] entry_index=0;
    reg [1:0] entry_type=0;
    reg [31:0] entry_cluster=0, entry_size=0, fat_base=0, data_base=0;
    reg [7:0] sectors_per_cluster=0;
    reg query_valid=0;
    reg [7:0] query_image_id=0;
    wire query_ready, descriptor_valid, error_valid, catalog_valid;
    wire [7:0] descriptor_image_id, error_code, catalog_count;
    wire [1:0] descriptor_type;
    wire [31:0] descriptor_cluster, descriptor_size, descriptor_fat_base, descriptor_data_base;
    wire [7:0] descriptor_spc;
    wire [15:0] descriptor_epoch, catalog_epoch;
    integer errors=0, checks=0;

    always #5 clk=~clk;
    m1a_catalog_table #(.FILE_MAX(4)) dut(
        .clk(clk), .rst_n(rst_n), .scan_start(scan_start), .scan_done(scan_done), .scan_ok(scan_ok),
        .entry_valid(entry_valid), .entry_index(entry_index), .entry_type(entry_type),
        .entry_cluster(entry_cluster), .entry_size(entry_size), .scan_fat_lba_base(fat_base),
        .scan_data_lba_base(data_base), .scan_sectors_per_cluster(sectors_per_cluster),
        .query_valid(query_valid), .query_image_id(query_image_id), .query_ready(query_ready),
        .descriptor_valid(descriptor_valid), .descriptor_image_id(descriptor_image_id),
        .descriptor_type(descriptor_type), .descriptor_cluster(descriptor_cluster),
        .descriptor_size(descriptor_size), .descriptor_fat_lba_base(descriptor_fat_base),
        .descriptor_data_lba_base(descriptor_data_base), .descriptor_sectors_per_cluster(descriptor_spc),
        .descriptor_epoch(descriptor_epoch), .error_valid(error_valid), .error_code(error_code),
        .catalog_valid(catalog_valid), .catalog_count(catalog_count), .catalog_epoch(catalog_epoch));

    task add_entry;
        input [4:0] idx; input [1:0] typ; input [31:0] clu, size;
        begin
            @(negedge clk); entry_index=idx; entry_type=typ; entry_cluster=clu; entry_size=size; entry_valid=1;
            @(negedge clk); entry_valid=0;
        end
    endtask

    task query;
        input [7:0] id;
        begin
            @(negedge clk); query_image_id=id; query_valid=1;
            while (!query_ready) @(negedge clk);
            @(negedge clk); query_valid=0;
        end
    endtask

    initial begin
        #12; rst_n=1;
        // No catalog is exposed before a successful scan.
        checks=checks+1; if(query_ready || catalog_valid) begin $display("ERROR premature catalog"); errors=errors+1; end

        @(negedge clk); scan_start=1; fat_base=32'd100; data_base=32'd1000; sectors_per_cluster=8'd2;
        @(negedge clk); scan_start=0;
        add_entry(0, 2'd1, 32'd5, 32'd12345);
        add_entry(1, 2'd2, 32'd9, 32'd67890);
        @(negedge clk); scan_done=1; scan_ok=1;
        @(negedge clk); scan_done=0; scan_ok=0;
        checks=checks+1; if(!catalog_valid || catalog_count!=2) begin $display("ERROR catalog publish"); errors=errors+1; end

        query(1);
        @(posedge clk); #1;
        checks=checks+1;
        if(!descriptor_valid || descriptor_image_id!=1 || descriptor_type!=2 || descriptor_cluster!=9 ||
           descriptor_size!=67890 || descriptor_fat_base!=100 || descriptor_data_base!=1000 || descriptor_spc!=2 ||
           descriptor_epoch!=catalog_epoch || descriptor_epoch!=16'd1) begin
            $display("ERROR descriptor fields"); errors=errors+1;
        end

        query(3);
        @(posedge clk); #1;
        checks=checks+1; if(!error_valid || error_code!=`M1A_ERR_BAD_IMAGE) begin $display("ERROR bad image"); errors=errors+1; end

        // A failed rescan invalidates the previous table and cannot answer.
        @(negedge clk); scan_start=1;
        @(negedge clk); scan_start=0; scan_done=1; scan_ok=0;
        @(negedge clk); scan_done=0;
        checks=checks+1; if(catalog_valid || query_ready) begin $display("ERROR failed scan remained valid"); errors=errors+1; end

        if(errors==0) $display("PASS: m1a_catalog_table checks=%0d", checks);
        else $display("FAIL: m1a_catalog_table errors=%0d checks=%0d", errors, checks);
        $finish;
    end
endmodule
