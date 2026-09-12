`timescale 1ns/1ps

module tb_p1_framebuffer_pattern_writer;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg start = 1'b0;
    reg mem_wr_ready = 1'b0;

    wire mem_wr_valid;
    wire [20:0] mem_wr_addr;
    wire [31:0] mem_wr_data;
    wire busy, done, ok, protocol_error;
    wire [15:0] x_debug, y_debug;

    integer checks = 0;
    integer writes = 0;
    integer ready_cycle = 0;
    integer timeout_cycles = 0;

    always #5 clk = ~clk;

    p1_framebuffer_pattern_writer #(
        .FRAME_WIDTH(16),
        .FRAME_HEIGHT(8),
        .FRAME_STRIDE_WORDS(16),
        .FRAME_BASE(21'd32),
        .BORDER_PIXELS(1),
        .CENTER_BAR_PIXELS(2)
    ) dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .mem_wr_valid(mem_wr_valid), .mem_wr_addr(mem_wr_addr),
        .mem_wr_data(mem_wr_data), .mem_wr_ready(mem_wr_ready),
        .busy(busy), .done(done), .ok(ok), .protocol_error(protocol_error),
        .x_debug(x_debug), .y_debug(y_debug)
    );

    function [23:0] expected_rgb;
        input integer x;
        input integer y;
        begin
            if ((x < 1) || (x >= 15) || (y < 1) || (y >= 7))
                expected_rgb = 24'hFFFFFF;
            else if ((x >= 7) && (x < 9))
                expected_rgb = 24'hFF00FF;
            else if ((y >= 3) && (y < 5))
                expected_rgb = 24'h00FFFF;
            else if ((x < 8) && (y < 4))
                expected_rgb = 24'hFF0000;
            else if ((x >= 8) && (y < 4))
                expected_rgb = 24'h00FF00;
            else if ((x < 8) && (y >= 4))
                expected_rgb = 24'h0000FF;
            else
                expected_rgb = 24'hFFFF00;
        end
    endfunction

    always @(posedge clk) begin
        if (rst_n && mem_wr_valid && mem_wr_ready) begin
            if (mem_wr_addr !== (21'd32 + writes)) begin
                $display("FAIL: addr write=%0d got=%0d", writes, mem_wr_addr);
                $finish;
            end
            checks = checks + 1;

            if (mem_wr_data !== {8'h00, expected_rgb(writes % 16, writes / 16)}) begin
                $display("FAIL: data write=%0d got=%h exp=%h", writes, mem_wr_data,
                         {8'h00, expected_rgb(writes % 16, writes / 16)});
                $finish;
            end
            checks = checks + 1;
            writes = writes + 1;
        end
    end

    // Drive ready from an independent cycle counter.  Do not derive
    // backpressure from the accepted-write count: if ready is deasserted
    // while that count is used as the selector, the count cannot advance and
    // the testbench can deadlock permanently.  Driving on negedge also keeps
    // ready stable around the DUT sampling edge.
    always @(negedge clk) begin
        if (!rst_n) begin
            ready_cycle  = 0;
            mem_wr_ready = 1'b0;
        end else begin
            ready_cycle  = ready_cycle + 1;
            mem_wr_ready = ((ready_cycle % 5) != 3);
        end
    end

    initial begin
        repeat (4) @(posedge clk);
        rst_n <= 1'b1;
        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        // A 128-write transfer should finish in far fewer than 2000 cycles,
        // even with the deterministic 1-in-5 backpressure pattern above.
        // This watchdog is intentionally written in Verilog-2001 syntax: the
        // project compiles .v testbenches with plain `vlog`, so SystemVerilog
        // fork/join_any constructs must not be used here.
        timeout_cycles = 0;
        while (!done && (timeout_cycles < 2000)) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
        end

        if (!done) begin
            $display("FAIL: timeout waiting for done writes=%0d x=%0d y=%0d valid=%b ready=%b",
                     writes, x_debug, y_debug, mem_wr_valid, mem_wr_ready);
            $finish;
        end

        if (!ok || protocol_error) begin
            $display("FAIL: done ok=%b protocol_error=%b", ok, protocol_error);
            $finish;
        end
        checks = checks + 2;

        if (writes != 128) begin
            $display("FAIL: write count got=%0d exp=128", writes);
            $finish;
        end
        checks = checks + 1;

        $display("PASS: p1_framebuffer_pattern_writer passed (checks=%0d)", checks);
        $finish;
    end
endmodule
