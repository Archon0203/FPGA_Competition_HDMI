`timescale 1ns/1ps

module tb_sdram_adapter;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_n = 1'b0;
    wire rst = !rst_n;

    reg mem_wr_valid = 1'b0;
    reg [20:0] mem_wr_addr = 21'd0;
    reg [31:0] mem_wr_data = 32'd0;
    wire mem_wr_ready;

    reg mem_rd_valid = 1'b0;
    reg [20:0] mem_rd_addr = 21'd0;
    wire mem_rd_ready;
    wire mem_rvalid;
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

    wire ready_for_traffic;
    wire protocol_error;
    wire provider_fault;
    wire contention_seen;
    wire [15:0] read_outstanding_debug;
    wire [31:0] read_accept_count_debug;
    wire [31:0] write_accept_count_debug;
    wire [31:0] app_read_word_count_debug;
    wire [31:0] app_write_word_count_debug;

    wire model_protocol_error;
    wire [31:0] model_app_read_count;
    wire [31:0] model_app_write_count;
    wire [31:0] model_masked_word_count;

    integer checks = 0;
    integer errors = 0;
    integer guard;
    integer base_reads;
    integer base_writes;
    integer base_masked;
    reg read_dm_violation_seen = 1'b0;

    sdram_adapter #(.RESP_TAG_FIFO_DEPTH(32)) dut (
        .clk(clk), .rst_n(rst_n),
        .mem_wr_valid(mem_wr_valid), .mem_wr_addr(mem_wr_addr),
        .mem_wr_data(mem_wr_data), .mem_wr_ready(mem_wr_ready),
        .mem_rd_valid(mem_rd_valid), .mem_rd_addr(mem_rd_addr),
        .mem_rd_ready(mem_rd_ready), .mem_rvalid(mem_rvalid), .mem_rdata(mem_rdata),
        .App_wr_en(App_wr_en), .App_wr_addr(App_wr_addr),
        .App_wr_din(App_wr_din), .App_wr_dm(App_wr_dm),
        .App_rd_en(App_rd_en), .App_rd_addr(App_rd_addr),
        .Sdr_rd_en(Sdr_rd_en), .Sdr_rd_dout(Sdr_rd_dout),
        .Sdr_init_done(Sdr_init_done), .Sdr_init_ref_vld(Sdr_init_ref_vld),
        .Sdr_busy(Sdr_busy), .App_ref_req(App_ref_req),
        .ready_for_traffic(ready_for_traffic), .protocol_error(protocol_error),
        .provider_fault(provider_fault), .contention_seen(contention_seen),
        .read_outstanding_debug(read_outstanding_debug),
        .read_accept_count_debug(read_accept_count_debug),
        .write_accept_count_debug(write_accept_count_debug),
        .app_read_word_count_debug(app_read_word_count_debug),
        .app_write_word_count_debug(app_write_word_count_debug)
    );

    mock_apug011_app_port #(.MEM_WORDS(4096), .INIT_CYCLES(8), .READ_LATENCY(10)) mem (
        .clk(clk), .rst(rst),
        .App_wr_en(App_wr_en), .App_wr_addr(App_wr_addr),
        .App_wr_din(App_wr_din), .App_wr_dm(App_wr_dm),
        .App_rd_en(App_rd_en), .App_rd_addr(App_rd_addr),
        .Sdr_rd_en(Sdr_rd_en), .Sdr_rd_dout(Sdr_rd_dout),
        .Sdr_init_done(Sdr_init_done), .Sdr_init_ref_vld(Sdr_init_ref_vld),
        .Sdr_busy(Sdr_busy), .force_refresh(force_refresh), .force_busy(force_busy),
        .inject_unsolicited_response(inject_unsolicited_response),
        .protocol_error(model_protocol_error),
        .app_read_count(model_app_read_count), .app_write_count(model_app_write_count),
        .masked_word_count(model_masked_word_count)
    );


    // A read must never be presented with a non-zero byte mask.  This was not
    // modeled by the original strict mock, but the official IS42 model applies
    // DQM to read output and will tri-state DQ when all bytes are masked.
    always @(posedge clk) begin
        if (!rst_n)
            read_dm_violation_seen <= 1'b0;
        else if (App_rd_en && (App_wr_dm !== 4'b0000))
            read_dm_violation_seen <= 1'b1;
    end

    task check;
        input condition;
        input [8*120-1:0] msg;
        begin
            checks = checks + 1;
            if (!condition) begin
                errors = errors + 1;
                $display("FAIL: %0s @%0t", msg, $time);
            end
        end
    endtask

    task reset_dut;
        begin
            mem_wr_valid = 1'b0;
            mem_rd_valid = 1'b0;
            force_refresh = 1'b0;
            force_busy = 1'b0;
            inject_unsolicited_response = 1'b0;
            rst_n = 1'b0;
            repeat (4) @(posedge clk);
            rst_n = 1'b1;
            @(posedge clk);
        end
    endtask

    task wait_init;
        begin
            guard = 0;
            while (!ready_for_traffic && guard < 100) begin
                @(posedge clk);
                guard = guard + 1;
            end
            check(ready_for_traffic, "adapter becomes ready after APUG011 init");
        end
    endtask

    task do_write;
        input [20:0] addr;
        input [31:0] data;
        begin
            @(negedge clk);
            mem_wr_addr  = addr;
            mem_wr_data  = data;
            mem_wr_valid = 1'b1;
            guard = 0;
            while (!mem_wr_ready && guard < 200) begin
                @(posedge clk);
                guard = guard + 1;
            end
            check(mem_wr_ready, "write request accepted");
            @(negedge clk);
            mem_wr_valid = 1'b0;
        end
    endtask

    task do_read;
        input [20:0] addr;
        input [31:0] expected;
        begin
            @(negedge clk);
            mem_rd_addr  = addr;
            mem_rd_valid = 1'b1;
            guard = 0;
            while (!mem_rd_ready && guard < 200) begin
                @(posedge clk);
                guard = guard + 1;
            end
            check(mem_rd_ready, "read request accepted");
            @(negedge clk);
            mem_rd_valid = 1'b0;
            guard = 0;
            while (!mem_rvalid && guard < 300) begin
                @(posedge clk);
                guard = guard + 1;
            end
            check(mem_rvalid, "read response returned");
            if (mem_rvalid)
                check(mem_rdata === expected, "read response data matches");

            // mem_rvalid can be observed in the same posedge active region in
            // which sdram_adapter retires read_outstanding_debug via NBA.
            // Return on the following negedge so callers sample post-NBA state
            // rather than the previous-cycle outstanding count.
            @(negedge clk);
        end
    endtask

    initial begin
        $display("P1-01 sdram_adapter unit test start");

        // CASE0: no upstream command may be accepted before initialization.
        $display("CASE0 init gating");
        reset_dut();
        @(negedge clk);
        mem_rd_addr = 21'd4;
        mem_rd_valid = 1'b1;
        repeat (3) begin
            @(posedge clk);
            check(!mem_rd_ready, "read blocked before init");
            check(!App_rd_en && !App_wr_en, "APUG command blocked before init");
        end
        @(negedge clk);
        mem_rd_valid = 1'b0;
        wait_init();
        check(App_ref_req == 1'b0, "adapter uses APUG011 self-refresh mode");

        // CASE1: arbitrary-word writes become aligned 4-word masked groups.
        $display("CASE1 arbitrary write + mask padding");
        base_writes = model_app_write_count;
        base_masked = model_masked_word_count;
        do_write(21'd5, 32'h1122_3344);
        do_write(21'd8, 32'hA5A5_5A5A);
        repeat (12) @(posedge clk);
        check(mem.mem[5] === 32'h1122_3344, "unaligned word write stored at exact address");
        check(mem.mem[8] === 32'hA5A5_5A5A, "aligned word write stored at exact address");
        check(model_app_write_count - base_writes == 8, "two abstract writes issue eight APUG words");
        check(model_masked_word_count - base_masked == 6, "three padding words per abstract write are masked");

        // CASE2: arbitrary reads return only target lane and preserve data.
        $display("CASE2 arbitrary read + response filtering");
        base_reads = model_app_read_count;
        do_read(21'd5, 32'h1122_3344);
        do_read(21'd8, 32'hA5A5_5A5A);
        check(model_app_read_count - base_reads == 8, "two abstract reads issue eight APUG words");
        check(read_outstanding_debug == 16'd0, "all accepted reads retired");

        // CASE3: busy stalls APUG commands and target ready without losing request.
        $display("CASE3 busy stall");
        force_busy = 1'b1;
        @(negedge clk);
        mem_wr_addr = 21'd13;
        mem_wr_data = 32'hCAFE_1300;
        mem_wr_valid = 1'b1;
        repeat (6) begin
            @(posedge clk);
            check(!mem_wr_ready, "write target not accepted while busy");
            check(!App_wr_en && !App_rd_en, "no APUG command while busy");
        end
        force_busy = 1'b0;
        guard = 0;
        while (!mem_wr_ready && guard < 100) begin
            @(posedge clk);
            guard = guard + 1;
        end
        check(mem_wr_ready, "stalled write resumes after busy");
        @(negedge clk);
        mem_wr_valid = 1'b0;
        repeat (8) @(posedge clk);
        check(mem.mem[13] === 32'hCAFE_1300, "busy-stalled write eventually commits");

        // CASE4: refresh similarly pauses an in-flight micro-group.
        $display("CASE4 refresh stall");
        force_refresh = 1'b1;
        @(negedge clk);
        mem_rd_addr = 21'd13;
        mem_rd_valid = 1'b1;
        repeat (5) begin
            @(posedge clk);
            check(!mem_rd_ready, "read target not accepted during refresh");
            check(!App_wr_en && !App_rd_en, "no APUG command during refresh");
        end
        force_refresh = 1'b0;
        guard = 0;
        while (!mem_rd_ready && guard < 100) begin
            @(posedge clk);
            guard = guard + 1;
        end
        check(mem_rd_ready, "refresh-stalled read resumes");
        @(negedge clk);
        mem_rd_valid = 1'b0;
        guard = 0;
        while (!mem_rvalid && guard < 300) begin
            @(posedge clk);
            guard = guard + 1;
        end
        check(mem_rvalid && mem_rdata === 32'hCAFE_1300, "refresh-stalled read returns correct data");

        // CASE5: direct upstream contention is observed; read starts first.
        $display("CASE5 read priority on direct contention");
        @(negedge clk);
        mem_rd_addr = 21'd5;
        mem_wr_addr = 21'd20;
        mem_wr_data = 32'h2020_2020;
        mem_rd_valid = 1'b1;
        mem_wr_valid = 1'b1;
        guard = 0;
        while (!mem_rd_ready && guard < 100) begin
            @(posedge clk);
            check(!mem_wr_ready, "write cannot overtake contending read");
            guard = guard + 1;
        end
        check(mem_rd_ready, "read wins contention");
        @(negedge clk);
        mem_rd_valid = 1'b0;
        // Keep writer valid; it must be accepted after read group completes.
        guard = 0;
        while (!mem_wr_ready && guard < 200) begin
            @(posedge clk);
            guard = guard + 1;
        end
        check(mem_wr_ready, "writer accepted after read group");
        @(negedge clk);
        mem_wr_valid = 1'b0;
        repeat (20) @(posedge clk);
        check(contention_seen, "contention_seen sticky flag set");
        check(mem.mem[20] === 32'h2020_2020, "post-contention write committed");

        // CASE6: verify exact APUG grouping is accepted by strict model.
        $display("CASE6 APUG group legality");
        check(!model_protocol_error, "all generated APUG commands obey grouping/stall/read-DQM rules");
        check(!read_dm_violation_seen, "App_wr_dm stays 0000 throughout APUG011 reads");
        check(!provider_fault, "provider_fault remains clear");
        check(!protocol_error, "adapter protocol_error remains clear before negative test");

        // CASE7: an unsolicited provider response is detected and quarantined.
        $display("CASE7 unsolicited response negative test");
        while (read_outstanding_debug != 0) @(posedge clk);
        repeat (20) @(posedge clk);
        @(negedge clk);
        inject_unsolicited_response = 1'b1;
        @(posedge clk);
        @(negedge clk);
        inject_unsolicited_response = 1'b0;
        @(posedge clk);
        #1;
        check(protocol_error, "unsolicited Sdr_rd_en sets sticky protocol_error");
        check(!mem_rvalid, "unsolicited provider word is not forwarded to P0");

        if (errors == 0)
            $display("PASS: sdram_adapter APUG011 application-side unit cases passed (checks=%0d)", checks);
        else
            $display("FAIL: sdram_adapter errors=%0d checks=%0d", errors, checks);

        #50;
        $finish;
    end

endmodule
