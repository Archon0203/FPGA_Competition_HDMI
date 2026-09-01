`timescale 1ns/1ps

module tb_p1_apug011_bist;
    reg clk;
    reg rst_n;
    reg backend_ready;

    wire        wr_valid;
    wire [20:0] wr_addr;
    wire [31:0] wr_data;
    reg         wr_ready;
    wire        rd_valid;
    wire [20:0] rd_addr;
    reg         rd_ready;
    reg         rd_rvalid;
    reg  [31:0] rd_rdata;

    reg arb_protocol_error;
    reg adapter_protocol_error;
    reg provider_fault;

    wire done;
    wire pass;
    wire fail;
    wire [3:0] state_debug;

    integer errors;
    integer checks;
    integer write_seen;
    integer read_seen;
    reg [1:0] response_delay;
    reg [20:0] pending_addr;
    reg response_pending;

    p1_apug011_bist dut (
        .clk(clk),
        .rst_n(rst_n),
        .backend_ready(backend_ready),
        .wr_valid(wr_valid),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .wr_ready(wr_ready),
        .rd_valid(rd_valid),
        .rd_addr(rd_addr),
        .rd_ready(rd_ready),
        .rd_rvalid(rd_rvalid),
        .rd_rdata(rd_rdata),
        .arb_protocol_error(arb_protocol_error),
        .adapter_protocol_error(adapter_protocol_error),
        .provider_fault(provider_fault),
        .done(done),
        .pass(pass),
        .fail(fail),
        .state_debug(state_debug)
    );

    always #5 clk = ~clk;

    task check;
        input condition;
        input [8*96-1:0] message;
        begin
            checks = checks + 1;
            if (!condition) begin
                errors = errors + 1;
                $display("FAIL: %0s", message);
            end else begin
                $display("PASS: %0s", message);
            end
        end
    endtask

    always @(posedge clk) begin
        rd_rvalid <= 1'b0;

        if (wr_valid && wr_ready) begin
            write_seen <= write_seen + 1;
            if (write_seen == 0) begin
                check(wr_addr == 21'd5, "first write address is 5");
                check(wr_data == 32'h11223344, "first write data matches");
            end else if (write_seen == 1) begin
                check(wr_addr == 21'd8, "second write address is 8");
                check(wr_data == 32'hA5A55A5A, "second write data matches");
            end
        end

        if (rd_valid && rd_ready && !response_pending) begin
            read_seen <= read_seen + 1;
            pending_addr <= rd_addr;
            response_pending <= 1'b1;
            response_delay <= 2'd2;
        end

        if (response_pending) begin
            if (response_delay != 0) begin
                response_delay <= response_delay - 1'b1;
            end else begin
                response_pending <= 1'b0;
                rd_rvalid <= 1'b1;
                if (pending_addr == 21'd5)
                    rd_rdata <= 32'h11223344;
                else if (pending_addr == 21'd8)
                    rd_rdata <= 32'hA5A55A5A;
                else
                    rd_rdata <= 32'hDEADBEEF;
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        backend_ready = 1'b0;
        wr_ready = 1'b1;
        rd_ready = 1'b1;
        rd_rvalid = 1'b0;
        rd_rdata = 32'd0;
        arb_protocol_error = 1'b0;
        adapter_protocol_error = 1'b0;
        provider_fault = 1'b0;
        errors = 0;
        checks = 0;
        write_seen = 0;
        read_seen = 0;
        response_delay = 0;
        pending_addr = 0;
        response_pending = 1'b0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);
        check(!wr_valid && !rd_valid, "BIST waits until backend_ready");

        backend_ready = 1'b1;
        wait(done);
        @(negedge clk);
        check(pass && !fail, "nominal BIST reaches PASS");
        check(write_seen == 2, "exactly two writes accepted");
        check(read_seen == 2, "exactly two reads accepted");

        // Health error must dominate and terminate in FAIL after reset.
        rst_n = 1'b0;
        backend_ready = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
        provider_fault = 1'b1;
        repeat (2) @(posedge clk);
        provider_fault = 1'b0;
        wait(done);
        @(negedge clk);
        check(fail && !pass, "provider fault drives sticky FAIL terminal state");

        if (errors == 0)
            $display("PASS: p1_apug011_bist unit cases passed (checks=%0d)", checks);
        else
            $display("FAIL: p1_apug011_bist errors=%0d checks=%0d", errors, checks);
        $finish;
    end
endmodule
