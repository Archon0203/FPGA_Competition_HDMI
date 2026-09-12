`timescale 1ns/1ps

module tb_p1_sdram_cached_adapter;
    reg clk = 1'b0;
    reg rst_n = 1'b0;

    reg         mem_wr_valid = 1'b0;
    reg [20:0]  mem_wr_addr = 21'd0;
    reg [31:0]  mem_wr_data = 32'd0;
    wire        mem_wr_ready;

    reg         mem_rd_valid = 1'b0;
    reg [20:0]  mem_rd_addr = 21'd0;
    wire        mem_rd_ready;
    wire        mem_rvalid;
    wire [31:0] mem_rdata;

    wire App_wr_en;
    wire [20:0] App_wr_addr;
    wire [31:0] App_wr_din;
    wire [3:0] App_wr_dm;
    wire App_rd_en;
    wire [20:0] App_rd_addr;
    wire Sdr_rd_en;
    wire [31:0] Sdr_rd_dout;
    wire Sdr_init_done;
    wire Sdr_init_ref_vld;
    wire Sdr_busy;
    wire App_ref_req;

    reg force_refresh = 1'b0;
    reg force_busy = 1'b0;
    reg inject_unsolicited_response = 1'b0;

    wire provider_protocol_error;
    wire [31:0] provider_app_read_count;
    wire [31:0] provider_app_write_count;
    wire [31:0] provider_masked_word_count;

    wire ready_for_traffic;
    wire protocol_error;
    wire provider_fault;
    wire contention_seen;
    wire [15:0] read_outstanding_debug;
    wire [31:0] read_accept_count_debug;
    wire [31:0] write_accept_count_debug;
    wire [31:0] app_read_word_count_debug;
    wire [31:0] app_write_word_count_debug;
    wire [31:0] read_cache_hit_count_debug;
    wire [31:0] read_cache_miss_count_debug;

    integer checks = 0;
    integer cycles;
    reg [31:0] rd_data;

    always #3.333 clk = ~clk; // ~150 MHz

    p1_sdram_cached_adapter dut (
        .clk                        (clk),
        .rst_n                      (rst_n),
        .mem_wr_valid               (mem_wr_valid),
        .mem_wr_addr                (mem_wr_addr),
        .mem_wr_data                (mem_wr_data),
        .mem_wr_ready               (mem_wr_ready),
        .mem_rd_valid               (mem_rd_valid),
        .mem_rd_addr                (mem_rd_addr),
        .mem_rd_ready               (mem_rd_ready),
        .mem_rvalid                 (mem_rvalid),
        .mem_rdata                  (mem_rdata),
        .App_wr_en                  (App_wr_en),
        .App_wr_addr                (App_wr_addr),
        .App_wr_din                 (App_wr_din),
        .App_wr_dm                  (App_wr_dm),
        .App_rd_en                  (App_rd_en),
        .App_rd_addr                (App_rd_addr),
        .Sdr_rd_en                  (Sdr_rd_en),
        .Sdr_rd_dout                (Sdr_rd_dout),
        .Sdr_init_done              (Sdr_init_done),
        .Sdr_init_ref_vld           (Sdr_init_ref_vld),
        .Sdr_busy                   (Sdr_busy),
        .App_ref_req                (App_ref_req),
        .ready_for_traffic          (ready_for_traffic),
        .protocol_error             (protocol_error),
        .provider_fault             (provider_fault),
        .contention_seen            (contention_seen),
        .read_outstanding_debug     (read_outstanding_debug),
        .read_accept_count_debug    (read_accept_count_debug),
        .write_accept_count_debug   (write_accept_count_debug),
        .app_read_word_count_debug  (app_read_word_count_debug),
        .app_write_word_count_debug (app_write_word_count_debug),
        .read_cache_hit_count_debug (read_cache_hit_count_debug),
        .read_cache_miss_count_debug(read_cache_miss_count_debug)
    );

    mock_apug011_app_port #(
        .MEM_WORDS(4096),
        .INIT_CYCLES(8),
        .READ_LATENCY(10)
    ) provider (
        .clk                        (clk),
        .rst                        (!rst_n),
        .App_wr_en                  (App_wr_en),
        .App_wr_addr                (App_wr_addr),
        .App_wr_din                 (App_wr_din),
        .App_wr_dm                  (App_wr_dm),
        .App_rd_en                  (App_rd_en),
        .App_rd_addr                (App_rd_addr),
        .Sdr_rd_en                  (Sdr_rd_en),
        .Sdr_rd_dout                (Sdr_rd_dout),
        .Sdr_init_done              (Sdr_init_done),
        .Sdr_init_ref_vld           (Sdr_init_ref_vld),
        .Sdr_busy                   (Sdr_busy),
        .force_refresh              (force_refresh),
        .force_busy                 (force_busy),
        .inject_unsolicited_response(inject_unsolicited_response),
        .protocol_error             (provider_protocol_error),
        .app_read_count             (provider_app_read_count),
        .app_write_count            (provider_app_write_count),
        .masked_word_count          (provider_masked_word_count)
    );

    task check_true;
        input condition;
        input [8*100-1:0] message;
        begin
            checks = checks + 1;
            if (!condition) begin
                $display("FAIL: %0s", message);
                $finish;
            end
        end
    endtask

    task do_write;
        input [20:0] addr;
        input [31:0] data;
        begin
            // Drive on negedge, but recognize the valid/ready transfer only
            // on a posedge.  This models a synchronous master and prevents a
            // cache/adapter request from being counted twice because READY
            // changes in a delta-cycle after VALID is asserted.
            @(negedge clk);
            mem_wr_addr  = addr;
            mem_wr_data  = data;
            mem_wr_valid = 1'b1;

            cycles = 0;
            @(posedge clk);
            while (!mem_wr_ready && cycles < 200) begin
                cycles = cycles + 1;
                @(posedge clk);
            end
            check_true(mem_wr_ready, "write accepted");

            @(negedge clk);
            mem_wr_valid = 1'b0;

            cycles = 0;
            while ((dut.state != 2'd0) && cycles < 200) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            check_true(cycles < 200, "write group retired");
        end
    endtask

    task do_read;
        input [20:0] addr;
        output [31:0] data;
        begin
            data = 32'hxxxxxxxx;
            @(negedge clk);
            mem_rd_addr  = addr;
            mem_rd_valid = 1'b1;

            // Handshake is a rising-edge event.  Sampling READY only at
            // negedges can leave VALID asserted across two rising edges on a
            // cache hit and artificially increment the adapter's accept/hit
            // counters twice.
            cycles = 0;
            @(posedge clk);
            while (!mem_rd_ready && cycles < 300) begin
                cycles = cycles + 1;
                @(posedge clk);
            end
            check_true(mem_rd_ready, "read accepted");

            @(negedge clk);
            mem_rd_valid = 1'b0;

            cycles = 0;
            while (!mem_rvalid && cycles < 300) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            check_true(mem_rvalid, "read response returned");
            data = mem_rdata;
            @(negedge clk);
        end
    endtask

    initial begin
        repeat (6) @(negedge clk);
        rst_n = 1'b1;

        cycles = 0;
        while (!ready_for_traffic && cycles < 100) begin
            @(negedge clk);
            cycles = cycles + 1;
        end
        check_true(ready_for_traffic, "provider initialized");
        check_true(App_ref_req == 1'b0, "self-refresh request remains low");

        // Populate two aligned 4-word groups through the real masked-write path.
        do_write(21'd0, 32'h00112233);
        do_write(21'd1, 32'h00445566);
        do_write(21'd2, 32'h00778899);
        do_write(21'd3, 32'h00AABBCC);
        do_write(21'd4, 32'h00010203);
        do_write(21'd5, 32'h00102030);
        do_write(21'd6, 32'h00405060);
        do_write(21'd7, 32'h00708090);

        // First group: one physical 4-word fill followed by three cache hits.
        do_read(21'd0, rd_data);
        check_true(rd_data == 32'h00112233, "group0 lane0 data");
        do_read(21'd1, rd_data);
        check_true(rd_data == 32'h00445566, "group0 lane1 data");
        do_read(21'd2, rd_data);
        check_true(rd_data == 32'h00778899, "group0 lane2 data");
        do_read(21'd3, rd_data);
        check_true(rd_data == 32'h00AABBCC, "group0 lane3 data");

        check_true(app_read_word_count_debug == 32'd4,
                   "four sequential abstract reads use one APUG 4-word group");
        check_true(read_cache_miss_count_debug == 32'd1, "one group0 cache miss");
        $display("CACHE_COUNT_GROUP0: hits=%0d misses=%0d accepted=%0d app_reads=%0d",
                 read_cache_hit_count_debug, read_cache_miss_count_debug,
                 read_accept_count_debug, app_read_word_count_debug);
        check_true(read_cache_hit_count_debug == 32'd3, "three group0 cache hits");

        // Second group causes exactly one more physical group fill.
        do_read(21'd4, rd_data);
        check_true(rd_data == 32'h00010203, "group1 lane0 data");
        do_read(21'd5, rd_data);
        check_true(rd_data == 32'h00102030, "group1 lane1 data");
        do_read(21'd6, rd_data);
        check_true(rd_data == 32'h00405060, "group1 lane2 data");
        do_read(21'd7, rd_data);
        check_true(rd_data == 32'h00708090, "group1 lane3 data");

        check_true(app_read_word_count_debug == 32'd8,
                   "eight sequential abstract reads use two APUG groups");
        check_true(provider_app_read_count == 32'd8,
                   "provider observed eight physical read words");
        check_true(read_cache_miss_count_debug == 32'd2, "two total cache misses");
        check_true(read_cache_hit_count_debug == 32'd6, "six total cache hits");

        check_true(read_accept_count_debug == 32'd8, "eight abstract reads accepted");
        check_true(write_accept_count_debug == 32'd8, "eight abstract writes accepted");
        check_true(app_write_word_count_debug == 32'd32,
                   "eight abstract writes retire as eight APUG 4-word groups");
        check_true(provider_app_write_count == 32'd32,
                   "provider observed all 32 physical write words");
        check_true(provider_masked_word_count == 32'd24,
                   "three padding lanes masked for every abstract write");
        check_true(read_outstanding_debug == 16'd0, "all abstract reads retired");
        check_true(!protocol_error, "adapter protocol_error clear");
        check_true(!provider_fault, "provider_fault clear");
        check_true(!provider_protocol_error, "mock APUG protocol_error clear");

        $display("PASS: p1_sdram_cached_adapter passed (checks=%0d, abstract_reads=%0d, app_reads=%0d, hits=%0d, misses=%0d)",
                 checks, read_accept_count_debug, app_read_word_count_debug,
                 read_cache_hit_count_debug, read_cache_miss_count_debug);
        $finish;
    end

    initial begin
        #200000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
