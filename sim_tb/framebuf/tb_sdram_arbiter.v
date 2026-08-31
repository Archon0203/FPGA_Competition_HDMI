`timescale 1ns/1ps

// ================================================================
// Testbench : tb_sdram_arbiter
// P0-07 adversarial unit verification.
// ================================================================
module tb_sdram_arbiter;
    reg clk = 1'b0;
    reg rst_n = 1'b0;

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
    reg mem_wr_ready = 1'b0;

    wire mem_rd_valid;
    wire [20:0] mem_rd_addr;
    reg mem_rd_ready = 1'b0;
    reg mem_rvalid = 1'b0;
    reg [31:0] mem_rdata = 32'd0;

    wire protocol_error;
    wire contention_seen;
    wire [15:0] rd_outstanding_debug;
    wire [31:0] read_accept_count_debug;
    wire [31:0] write_accept_count_debug;

    integer errors = 0;
    integer checks = 0;

    sdram_arbiter #(.MAX_READ_OUTSTANDING(4)) u_dut (
        .clk(clk), .rst_n(rst_n),
        .wr_valid(wr_valid), .wr_addr(wr_addr), .wr_data(wr_data), .wr_ready(wr_ready),
        .rd_valid(rd_valid), .rd_addr(rd_addr), .rd_ready(rd_ready),
        .rd_rvalid(rd_rvalid), .rd_rdata(rd_rdata),
        .mem_wr_valid(mem_wr_valid), .mem_wr_addr(mem_wr_addr),
        .mem_wr_data(mem_wr_data), .mem_wr_ready(mem_wr_ready),
        .mem_rd_valid(mem_rd_valid), .mem_rd_addr(mem_rd_addr),
        .mem_rd_ready(mem_rd_ready), .mem_rvalid(mem_rvalid), .mem_rdata(mem_rdata),
        .protocol_error(protocol_error), .contention_seen(contention_seen),
        .rd_outstanding_debug(rd_outstanding_debug),
        .read_accept_count_debug(read_accept_count_debug),
        .write_accept_count_debug(write_accept_count_debug)
    );

    always #5 clk = ~clk;

    task check_int;
        input integer got;
        input integer exp;
        input [8*100-1:0] msg;
        begin
            checks = checks + 1;
            if (got !== exp) begin
                $display("ERROR: %s got=%0d exp=%0d", msg, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    task check_addr;
        input [20:0] got;
        input [20:0] exp;
        input [8*100-1:0] msg;
        begin
            checks = checks + 1;
            if (got !== exp) begin
                $display("ERROR: %s got=%0d exp=%0d", msg, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    task check_word;
        input [31:0] got;
        input [31:0] exp;
        input [8*100-1:0] msg;
        begin
            checks = checks + 1;
            if (got !== exp) begin
                $display("ERROR: %s got=%08x exp=%08x", msg, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    task clear_inputs;
        begin
            wr_valid = 1'b0;
            rd_valid = 1'b0;
            mem_wr_ready = 1'b0;
            mem_rd_ready = 1'b0;
            mem_rvalid = 1'b0;
            mem_rdata = 32'd0;
        end
    endtask

    task reset_dut;
        begin
            clear_inputs;
            @(negedge clk); rst_n = 1'b0;
            repeat (3) @(posedge clk);
            @(negedge clk); rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    initial begin
        reset_dut;

        $display("CASE0 idle");
        check_int(mem_rd_valid, 0, "idle no read");
        check_int(mem_wr_valid, 0, "idle no write");
        check_int(rd_outstanding_debug, 0, "idle outstanding=0");

        $display("CASE1 write pass-through");
        @(negedge clk);
        wr_valid = 1'b1; wr_addr = 21'd123; wr_data = 32'h00A1B2C3;
        mem_wr_ready = 1'b1;
        #1;
        check_int(mem_wr_valid, 1, "write valid");
        check_int(wr_ready, 1, "write ready");
        check_addr(mem_wr_addr, 21'd123, "write addr");
        check_word(mem_wr_data, 32'h00A1B2C3, "write data");
        @(posedge clk); @(negedge clk); wr_valid = 1'b0; mem_wr_ready = 1'b0;
        check_int(write_accept_count_debug, 1, "write accepted once");

        $display("CASE2 read request + delayed response");
        @(negedge clk);
        rd_valid = 1'b1; rd_addr = 21'd456; mem_rd_ready = 1'b1;
        #1;
        check_int(mem_rd_valid, 1, "read valid");
        check_int(rd_ready, 1, "read ready");
        check_addr(mem_rd_addr, 21'd456, "read addr");
        @(posedge clk); @(negedge clk);
        rd_valid = 1'b0; mem_rd_ready = 1'b0;
        check_int(rd_outstanding_debug, 1, "one read outstanding");
        mem_rdata = 32'h00112233; mem_rvalid = 1'b1; #1;
        check_int(rd_rvalid, 1, "response forwarded");
        check_word(rd_rdata, 32'h00112233, "response data");
        @(posedge clk); @(negedge clk); mem_rvalid = 1'b0;
        check_int(rd_outstanding_debug, 0, "response drained outstanding");

        $display("CASE3 simultaneous read/write -> read wins");
        @(negedge clk);
        wr_valid = 1'b1; wr_addr = 21'd900; wr_data = 32'h00DEAD55;
        rd_valid = 1'b1; rd_addr = 21'd901;
        mem_wr_ready = 1'b1; mem_rd_ready = 1'b1;
        #1;
        check_int(mem_rd_valid, 1, "contention read selected");
        check_int(rd_ready, 1, "contention read accepted");
        check_int(mem_wr_valid, 0, "contention write suppressed");
        check_int(wr_ready, 0, "contention writer backpressured");
        @(posedge clk); @(negedge clk);
        rd_valid = 1'b0; mem_rd_ready = 1'b0;
        #1;
        check_int(contention_seen, 1, "contention sticky set");
        check_int(mem_wr_valid, 1, "write resumes after read request clears");
        check_int(wr_ready, 1, "writer accepted after read");
        @(posedge clk); @(negedge clk);
        wr_valid = 1'b0; mem_wr_ready = 1'b0;
        mem_rvalid = 1'b1; mem_rdata = 32'h00ABCDEF;
        @(posedge clk); @(negedge clk); mem_rvalid = 1'b0;
        check_int(rd_outstanding_debug, 0, "contention read response drained");

        $display("CASE4 read downstream stall blocks writer");
        @(negedge clk);
        wr_valid = 1'b1; rd_valid = 1'b1; rd_addr = 21'd1000;
        mem_wr_ready = 1'b1; mem_rd_ready = 1'b0;
        #1;
        check_int(mem_rd_valid, 1, "stalled read remains selected");
        check_int(rd_ready, 0, "read not accepted");
        check_int(mem_wr_valid, 0, "writer blocked while read waits");
        check_int(wr_ready, 0, "writer ready low while read waits");
        @(negedge clk); clear_inputs;

        $display("CASE5 zero-latency response legal");
        @(negedge clk);
        rd_valid = 1'b1; rd_addr = 21'd77; mem_rd_ready = 1'b1;
        mem_rvalid = 1'b1; mem_rdata = 32'h0055AA11;
        #1;
        check_int(rd_rvalid, 1, "same-cycle response forwarded");
        check_word(rd_rdata, 32'h0055AA11, "same-cycle response data");
        @(posedge clk); @(negedge clk); clear_inputs;
        check_int(rd_outstanding_debug, 0, "same-cycle accept/response leaves zero");

        $display("CASE6 multiple outstanding responses");
        // Accept three reads.
        repeat (3) begin
            @(negedge clk);
            rd_valid = 1'b1; mem_rd_ready = 1'b1;
            rd_addr = 21'd2000 + read_accept_count_debug[2:0];
            @(posedge clk);
        end
        @(negedge clk); rd_valid = 1'b0; mem_rd_ready = 1'b0;
        check_int(rd_outstanding_debug, 3, "three outstanding");
        repeat (3) begin
            @(negedge clk); mem_rvalid = 1'b1; mem_rdata = 32'h00100000 + rd_outstanding_debug;
            @(posedge clk);
        end
        @(negedge clk); mem_rvalid = 1'b0;
        check_int(rd_outstanding_debug, 0, "multiple responses drained");

        $display("CASE7 unexpected response dropped and flagged");
        reset_dut;
        @(negedge clk); mem_rvalid = 1'b1; mem_rdata = 32'h00BADBAD; #1;
        check_int(rd_rvalid, 0, "unsolicited response not forwarded");
        @(posedge clk); @(negedge clk); mem_rvalid = 1'b0;
        check_int(protocol_error, 1, "unsolicited response flagged");

        $display("CASE8 reset clears sticky state");
        reset_dut;
        check_int(protocol_error, 0, "protocol error cleared");
        check_int(contention_seen, 0, "contention cleared");
        check_int(rd_outstanding_debug, 0, "outstanding cleared");
        check_int(read_accept_count_debug, 0, "read count cleared");
        check_int(write_accept_count_debug, 0, "write count cleared");

        if (errors == 0)
            $display("PASS: sdram_arbiter all adversarial cases passed (checks=%0d)", checks);
        else
            $display("FAIL: sdram_arbiter errors=%0d checks=%0d", errors, checks);
        $finish;
    end
endmodule
