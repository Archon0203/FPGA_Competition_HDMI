`timescale 1ns/1ps

module tb_sdram_arbiter_adapter_chain;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    wire rst = !rst_n;

    reg wr_valid = 1'b0;
    reg [20:0] wr_addr = 21'd0;
    reg [31:0] wr_data = 32'd0;
    wire wr_ready;

    reg rd_valid = 1'b0;
    reg [20:0] rd_addr = 21'd0;
    wire rd_ready;
    wire rd_rvalid;
    wire [31:0] rd_rdata;

    wire mem_wr_valid;
    wire [20:0] mem_wr_addr;
    wire [31:0] mem_wr_data;
    wire mem_wr_ready;
    wire mem_rd_valid;
    wire [20:0] mem_rd_addr;
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

    reg force_refresh = 1'b0;
    reg force_busy = 1'b0;

    wire arb_protocol_error;
    wire arb_contention_seen;
    wire [15:0] arb_outstanding;
    wire [31:0] arb_read_accepts;
    wire [31:0] arb_write_accepts;

    wire adapter_protocol_error;
    wire adapter_provider_fault;
    wire adapter_contention_seen;
    wire [15:0] adapter_outstanding;
    wire model_protocol_error;

    integer checks = 0;
    integer errors = 0;
    integer guard;

    sdram_arbiter #(.MAX_READ_OUTSTANDING(8)) arb (
        .clk(clk), .rst_n(rst_n),
        .wr_valid(wr_valid), .wr_addr(wr_addr), .wr_data(wr_data), .wr_ready(wr_ready),
        .rd_valid(rd_valid), .rd_addr(rd_addr), .rd_ready(rd_ready),
        .rd_rvalid(rd_rvalid), .rd_rdata(rd_rdata),
        .mem_wr_valid(mem_wr_valid), .mem_wr_addr(mem_wr_addr),
        .mem_wr_data(mem_wr_data), .mem_wr_ready(mem_wr_ready),
        .mem_rd_valid(mem_rd_valid), .mem_rd_addr(mem_rd_addr),
        .mem_rd_ready(mem_rd_ready), .mem_rvalid(mem_rvalid), .mem_rdata(mem_rdata),
        .protocol_error(arb_protocol_error), .contention_seen(arb_contention_seen),
        .rd_outstanding_debug(arb_outstanding),
        .read_accept_count_debug(arb_read_accepts), .write_accept_count_debug(arb_write_accepts)
    );

    sdram_adapter #(.RESP_TAG_FIFO_DEPTH(32)) adapter (
        .clk(clk), .rst_n(rst_n),
        .mem_wr_valid(mem_wr_valid), .mem_wr_addr(mem_wr_addr),
        .mem_wr_data(mem_wr_data), .mem_wr_ready(mem_wr_ready),
        .mem_rd_valid(mem_rd_valid), .mem_rd_addr(mem_rd_addr),
        .mem_rd_ready(mem_rd_ready), .mem_rvalid(mem_rvalid), .mem_rdata(mem_rdata),
        .App_wr_en(App_wr_en), .App_wr_addr(App_wr_addr), .App_wr_din(App_wr_din), .App_wr_dm(App_wr_dm),
        .App_rd_en(App_rd_en), .App_rd_addr(App_rd_addr),
        .Sdr_rd_en(Sdr_rd_en), .Sdr_rd_dout(Sdr_rd_dout),
        .Sdr_init_done(Sdr_init_done), .Sdr_init_ref_vld(Sdr_init_ref_vld), .Sdr_busy(Sdr_busy),
        .App_ref_req(), .ready_for_traffic(),
        .protocol_error(adapter_protocol_error), .provider_fault(adapter_provider_fault),
        .contention_seen(adapter_contention_seen), .read_outstanding_debug(adapter_outstanding),
        .read_accept_count_debug(), .write_accept_count_debug(),
        .app_read_word_count_debug(), .app_write_word_count_debug()
    );

    mock_apug011_app_port #(.MEM_WORDS(4096), .INIT_CYCLES(8), .READ_LATENCY(10)) mem (
        .clk(clk), .rst(rst),
        .App_wr_en(App_wr_en), .App_wr_addr(App_wr_addr), .App_wr_din(App_wr_din), .App_wr_dm(App_wr_dm),
        .App_rd_en(App_rd_en), .App_rd_addr(App_rd_addr),
        .Sdr_rd_en(Sdr_rd_en), .Sdr_rd_dout(Sdr_rd_dout),
        .Sdr_init_done(Sdr_init_done), .Sdr_init_ref_vld(Sdr_init_ref_vld), .Sdr_busy(Sdr_busy),
        .force_refresh(force_refresh), .force_busy(force_busy), .inject_unsolicited_response(1'b0),
        .protocol_error(model_protocol_error), .app_read_count(), .app_write_count(), .masked_word_count()
    );

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

    task source_write;
        input [20:0] a;
        input [31:0] d;
        begin
            @(negedge clk);
            wr_addr = a; wr_data = d; wr_valid = 1'b1;
            guard = 0;
            while (!wr_ready && guard < 300) begin
                @(posedge clk); guard = guard + 1;
            end
            check(wr_ready, "arbiter write accepted through adapter");
            @(negedge clk); wr_valid = 1'b0;
        end
    endtask

    task source_read;
        input [20:0] a;
        input [31:0] exp;
        begin
            @(negedge clk);
            rd_addr = a; rd_valid = 1'b1;
            guard = 0;
            while (!rd_ready && guard < 300) begin
                @(posedge clk); guard = guard + 1;
            end
            check(rd_ready, "arbiter read accepted through adapter");
            @(negedge clk); rd_valid = 1'b0;
            guard = 0;
            while (!rd_rvalid && guard < 400) begin
                @(posedge clk); guard = guard + 1;
            end
            check(rd_rvalid, "arbiter returned adapter response");
            if (rd_rvalid) check(rd_rdata === exp, "chain read data matches");
        end
    endtask

    initial begin
        $display("P1-01 arbiter -> adapter -> APUG011-like model chain test start");
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        while (!Sdr_init_done) @(posedge clk);
        repeat (2) @(posedge clk);

        $display("CASE0 write/read arbitrary word addresses");
        source_write(21'd101, 32'h0101_AA55);
        source_write(21'd104, 32'h0104_55AA);
        source_write(21'd107, 32'h0107_1234);
        repeat (12) @(posedge clk);
        source_read(21'd101, 32'h0101_AA55);
        source_read(21'd104, 32'h0104_55AA);
        source_read(21'd107, 32'h0107_1234);

        $display("CASE1 arbiter strict read priority under contention");
        @(negedge clk);
        rd_addr = 21'd101; rd_valid = 1'b1;
        wr_addr = 21'd108; wr_data = 32'h0108_BEEF; wr_valid = 1'b1;
        guard = 0;
        while (!rd_ready && guard < 300) begin
            @(posedge clk);
            check(!wr_ready, "writer blocked while read request contends");
            guard = guard + 1;
        end
        check(rd_ready, "contending read accepted first");
        @(negedge clk); rd_valid = 1'b0;
        guard = 0;
        while (!wr_ready && guard < 400) begin
            @(posedge clk); guard = guard + 1;
        end
        check(wr_ready, "contending writer eventually accepted");
        @(negedge clk); wr_valid = 1'b0;
        guard = 0;
        while (!rd_rvalid && guard < 400) begin
            @(posedge clk); guard = guard + 1;
        end
        check(rd_rvalid && rd_rdata === 32'h0101_AA55, "contending read response correct");
        repeat (12) @(posedge clk);
        check(mem.mem[108] === 32'h0108_BEEF, "contending write committed");

        $display("CASE2 refresh and busy backpressure propagate safely");
        force_refresh = 1'b1;
        @(negedge clk); rd_addr = 21'd104; rd_valid = 1'b1;
        repeat (5) begin
            @(posedge clk);
            check(!rd_ready, "arbiter read stalls during APUG refresh");
        end
        force_refresh = 1'b0;
        guard = 0;
        while (!rd_ready && guard < 300) begin @(posedge clk); guard = guard + 1; end
        check(rd_ready, "read resumes after refresh");
        @(negedge clk); rd_valid = 1'b0;
        guard = 0;
        while (!rd_rvalid && guard < 400) begin @(posedge clk); guard = guard + 1; end
        check(rd_rvalid && rd_rdata === 32'h0104_55AA, "post-refresh response correct");

        force_busy = 1'b1;
        @(negedge clk); wr_addr = 21'd109; wr_data = 32'h0109_CAFE; wr_valid = 1'b1;
        repeat (5) begin
            @(posedge clk);
            check(!wr_ready, "arbiter write stalls during APUG busy");
        end
        force_busy = 1'b0;
        guard = 0;
        while (!wr_ready && guard < 300) begin @(posedge clk); guard = guard + 1; end
        check(wr_ready, "write resumes after busy");
        @(negedge clk); wr_valid = 1'b0;
        repeat (12) @(posedge clk);
        check(mem.mem[109] === 32'h0109_CAFE, "post-busy write committed");

        $display("CASE3 clean drain/status");
        repeat (30) @(posedge clk);
        check(arb_outstanding == 16'd0, "arbiter outstanding drained");
        check(adapter_outstanding == 16'd0, "adapter outstanding drained");
        check(!arb_protocol_error, "arbiter protocol_error clear");
        check(!adapter_protocol_error, "adapter protocol_error clear");
        check(!adapter_provider_fault, "adapter provider_fault clear");
        check(!model_protocol_error, "APUG strict model protocol_error clear");
        check(arb_contention_seen, "arbiter observed intended contention");
        check(arb_read_accepts >= 32'd5, "read acceptance count advanced");
        check(arb_write_accepts >= 32'd5, "write acceptance count advanced");

        if (errors == 0)
            $display("PASS: sdram_arbiter -> sdram_adapter -> APUG011-like model chain passed (checks=%0d)", checks);
        else
            $display("FAIL: chain errors=%0d checks=%0d", errors, checks);

        #50;
        $finish;
    end
endmodule
