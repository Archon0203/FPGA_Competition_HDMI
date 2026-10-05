`timescale 1ns/1ps
module tb_m2_open_dispatcher;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #10 clk = ~clk;

    reg catalog_valid = 1'b0;
    reg [7:0] catalog_count = 8'd0;
    reg cmd_ready = 1'b0;
    reg remote_open_request = 1'b0;
    reg [7:0] remote_open_image_id = 8'd0;
    reg catalog_restart = 1'b0;

    wire cmd_valid;
    wire [7:0] cmd_image_id;
    wire cmd_is_remote;
    wire bootstrap_issued;
    wire remote_queued;

    integer checks = 0;

    m2_open_dispatcher dut (
        .clk(clk), .rst_n(rst_n),
        .catalog_valid(catalog_valid), .catalog_count(catalog_count),
        .cmd_ready(cmd_ready),
        .remote_open_request(remote_open_request),
        .remote_open_image_id(remote_open_image_id),
        .catalog_restart(catalog_restart),
        .cmd_valid(cmd_valid), .cmd_image_id(cmd_image_id),
        .cmd_is_remote(cmd_is_remote),
        .bootstrap_issued(bootstrap_issued), .remote_queued(remote_queued)
    );

    task expect_pulse;
        input [7:0] image_id;
        input is_remote;
        begin
            while (!cmd_valid) @(posedge clk);
            if (cmd_image_id !== image_id || cmd_is_remote !== is_remote) begin
                $display("FAIL: pulse id=%0d remote=%0d expected id=%0d remote=%0d",
                         cmd_image_id, cmd_is_remote, image_id, is_remote);
                $fatal;
            end
            checks = checks + 1;
            @(posedge clk);
        end
    endtask

    task send_remote;
        input [7:0] image_id;
        begin
            @(negedge clk);
            remote_open_image_id = image_id;
            remote_open_request = 1'b1;
            @(negedge clk);
            remote_open_request = 1'b0;
        end
    endtask

    initial begin #20000; $fatal(1,"watchdog"); end
    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        // A usable catalog must emit one and only one standalone OPEN(0).
        @(negedge clk);
        catalog_valid = 1'b1;
        catalog_count = 8'd4;
        cmd_ready = 1'b1;
        expect_pulse(8'd0, 1'b0);
        while (cmd_valid) @(posedge clk);
        repeat (8) begin
            @(posedge clk);
            if (cmd_valid) begin
                $display("FAIL: bootstrap repeated without restart");
                $fatal;
            end
        end
        checks = checks + 1;

        // Remote NEXT/PREV style OPENs work after the bootstrap.
        send_remote(8'd1);
        expect_pulse(8'd1, 1'b1);

        // While busy, keep one latest request; newest user intent wins.
        cmd_ready = 1'b0;
        send_remote(8'd2);
        send_remote(8'd3);
        repeat (3) @(posedge clk);
        if (!remote_queued) $fatal;
        cmd_ready = 1'b1;
        // ID 2 was already presented while ready was low: it must remain
        // stable until accepted, followed by the coalesced queued ID 3.
        expect_pulse(8'd2, 1'b1);
        @(negedge clk);
        expect_pulse(8'd3, 1'b1);

        // Explicit catalog restart re-arms exactly one standalone bootstrap.
        @(negedge clk); catalog_restart = 1'b1;
        @(negedge clk); catalog_restart = 1'b0;
        expect_pulse(8'd0, 1'b0);
        while (cmd_valid) @(posedge clk);
        repeat (6) begin
            @(posedge clk);
            if (cmd_valid) $fatal;
        end
        checks = checks + 1;

        $display("PASS: m2 open dispatcher checks=%0d", checks);
        $finish;
    end
endmodule
