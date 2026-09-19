`timescale 1ns/1ps

module tb_hdmi_test_pattern_line_provider;
    localparam W = 16;
    localparam H = 3;

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst_n = 0;
    reg read_start = 0;
    reg [15:0] read_line_index = 0;
    reg [15:0] read_width = 0;

    wire pixel_valid;
    wire [23:0] pixel_data;
    wire line_done;
    wire busy;
    wire protocol_error;

    integer checks = 0;
    integer errors = 0;
    integer beats = 0;
    integer done_count = 0;
    reg score_enable = 0;

    hdmi_test_pattern_line_provider #(
        .ACTIVE_WIDTH(W),
        .ACTIVE_HEIGHT(H)
    ) dut (
        .clk_pix(clk), .rst_n(rst_n),
        .read_start(read_start), .read_line_index(read_line_index),
        .read_width(read_width), .pixel_valid(pixel_valid),
        .pixel_data(pixel_data), .line_done(line_done),
        .busy(busy), .protocol_error(protocol_error)
    );

    function [23:0] expected_bar;
        input integer px;
        begin
            if      (px < 2)  expected_bar = 24'hFFFFFF;
            else if (px < 4)  expected_bar = 24'hFFFF00;
            else if (px < 6)  expected_bar = 24'h00FFFF;
            else if (px < 8)  expected_bar = 24'h00FF00;
            else if (px < 10) expected_bar = 24'hFF00FF;
            else if (px < 12) expected_bar = 24'hFF0000;
            else if (px < 14) expected_bar = 24'h0000FF;
            else              expected_bar = 24'h000000;
        end
    endfunction

    task check;
        input condition;
        input [8*100-1:0] what;
        begin
            checks = checks + 1;
            if (!condition) begin
                errors = errors + 1;
                $display("ERROR: %0s @ %0t", what, $time);
            end
        end
    endtask

    always @(posedge clk) begin
        if (rst_n && pixel_valid) begin
            if (score_enable) begin
                check(pixel_data === expected_bar(beats), "color bar pixel matches");
                check(line_done == (beats == W-1), "line_done only on final pixel");
                beats = beats + 1;
            end
            if (line_done) done_count = done_count + 1;
        end
    end

    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk); rst_n = 1;

        // Valid request.
        score_enable = 1;
        read_line_index = 1;
        read_width = W;
        read_start = 1;
        @(negedge clk); read_start = 0;

        while (done_count == 0) @(posedge clk);
        @(posedge clk);
        check(beats == W, "exact requested beat count");
        check(done_count == 1, "one line_done pulse");
        check(!busy, "provider returns idle after line");
        check(!protocol_error, "valid request has no protocol error");
        score_enable = 0;

        // Invalid width must set sticky diagnostic.
        @(negedge clk);
        read_line_index = 0;
        read_width = W-1;
        read_start = 1;
        @(negedge clk); read_start = 0;
        repeat (2) @(posedge clk);
        check(protocol_error, "wrong width detected");

        if (errors == 0)
            $display("PASS: hdmi_test_pattern_line_provider passed (checks=%0d)", checks);
        else
            $display("FAIL: hdmi_test_pattern_line_provider errors=%0d checks=%0d", errors, checks);
        $finish;
    end
endmodule
