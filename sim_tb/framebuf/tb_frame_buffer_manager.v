`timescale 1ns/1ps

// ================================================================
// Testbench : tb_frame_buffer_manager
// P0-04 adversarial unit verification.
//
// Verifies:
//   - reset front=A / back=B
//   - accepted load launches writer exactly once
//   - successful write only becomes visible at display frame boundary
//   - frame boundary during active write never swaps
//   - writer_done and boundary on same edge defer swap to next boundary
//   - failed write preserves displayed frame and leaves back buffer reusable
//   - load requests while busy/pending are rejected
//   - repeated A/B swaps never make read_base == write_base
// ================================================================

module tb_frame_buffer_manager;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg load_start = 1'b0;
    reg [15:0] load_width = 16'd0;
    reg [15:0] load_height = 16'd0;
    reg [15:0] load_stride_words = 16'd0;
    wire load_ready;
    wire load_accept;
    wire writer_start;
    wire [20:0] write_base;
    wire [15:0] write_width;
    wire [15:0] write_height;
    wire [15:0] write_stride_words;
    reg writer_done = 1'b0;
    reg writer_ok = 1'b0;
    reg display_frame_boundary = 1'b0;
    wire [20:0] read_base;
    wire [15:0] read_width;
    wire [15:0] read_height;
    wire [15:0] read_stride_words;
    wire read_frame_valid;
    wire write_in_progress;
    wire pending_swap;
    wire swap_pulse;
    wire load_fail_pulse;
    wire read_buffer_sel;
    wire write_buffer_sel;
    wire config_error;

    localparam [20:0] A_BASE = 21'd0;
    localparam [20:0] B_BASE = 21'd307200;

    frame_buffer_manager #(
        .IMAGE_A_BASE(A_BASE),
        .IMAGE_B_BASE(B_BASE)
    ) u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .load_start(load_start),
        .load_width(load_width),
        .load_height(load_height),
        .load_stride_words(load_stride_words),
        .load_ready(load_ready),
        .load_accept(load_accept),
        .writer_start(writer_start),
        .write_base(write_base),
        .write_width(write_width),
        .write_height(write_height),
        .write_stride_words(write_stride_words),
        .writer_done(writer_done),
        .writer_ok(writer_ok),
        .display_frame_boundary(display_frame_boundary),
        .read_base(read_base),
        .read_width(read_width),
        .read_height(read_height),
        .read_stride_words(read_stride_words),
        .read_frame_valid(read_frame_valid),
        .write_in_progress(write_in_progress),
        .pending_swap(pending_swap),
        .swap_pulse(swap_pulse),
        .load_fail_pulse(load_fail_pulse),
        .read_buffer_sel(read_buffer_sel),
        .write_buffer_sel(write_buffer_sel),
        .config_error(config_error)
    );

    always #5 clk = ~clk;

    integer errors = 0;
    integer checks = 0;
    integer writer_start_count = 0;
    integer swap_count = 0;
    integer fail_count = 0;
    integer i;

    task check_int;
        input integer got;
        input integer exp;
        input [8*96-1:0] msg;
        begin
            checks = checks + 1;
            if (got !== exp) begin
                $display("ERROR: %s got=%0d exp=%0d", msg, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    task check_base;
        input [20:0] got;
        input [20:0] exp;
        input [8*96-1:0] msg;
        begin
            checks = checks + 1;
            if (got !== exp) begin
                $display("ERROR: %s got=%0d exp=%0d", msg, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    task pulse_load_start;
        input [15:0] w;
        input [15:0] h;
        input [15:0] stride;
        begin
            @(negedge clk);
            load_width = w;
            load_height = h;
            load_stride_words = stride;
            load_start = 1'b1;
            @(negedge clk);
            load_start = 1'b0;
        end
    endtask

    task pulse_writer_done;
        input integer success;
        begin
            @(negedge clk);
            writer_ok = success ? 1'b1 : 1'b0;
            writer_done = 1'b1;
            @(negedge clk);
            writer_done = 1'b0;
            writer_ok = 1'b0;
        end
    endtask

    task pulse_boundary;
        begin
            @(negedge clk);
            display_frame_boundary = 1'b1;
            @(negedge clk);
            display_frame_boundary = 1'b0;
        end
    endtask

    task pulse_done_and_boundary_same_edge;
        input integer success;
        begin
            @(negedge clk);
            writer_ok = success ? 1'b1 : 1'b0;
            writer_done = 1'b1;
            display_frame_boundary = 1'b1;
            @(negedge clk);
            writer_done = 1'b0;
            writer_ok = 1'b0;
            display_frame_boundary = 1'b0;
        end
    endtask

    task invariant_distinct_buffers;
        begin
            checks = checks + 1;
            if (read_base === write_base) begin
                $display("ERROR: read_base and write_base became identical (%0d)", read_base);
                errors = errors + 1;
            end
        end
    endtask

    always @(posedge clk) begin
        if (rst_n) begin
            if (writer_start)
                writer_start_count = writer_start_count + 1;
            if (swap_pulse)
                swap_count = swap_count + 1;
            if (load_fail_pulse)
                fail_count = fail_count + 1;

            if (!config_error)
                invariant_distinct_buffers;
        end
    end

    initial begin
        $display("tb_frame_buffer_manager start");
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
        @(negedge clk);

        // ------------------------------------------------------------
        // CASE0: reset map.
        // ------------------------------------------------------------
        $display("CASE0 reset front=A back=B");
        check_int(config_error, 0, "valid frozen buffer map");
        check_base(read_base, A_BASE, "reset read base A");
        check_base(write_base, B_BASE, "reset write base B");
        check_int(load_ready, 1, "reset load ready");
        check_int(write_in_progress, 0, "reset not writing");
        check_int(pending_swap, 0, "reset no pending swap");
        check_int(read_frame_valid, 0, "reset front metadata invalid until first complete frame");

        // ------------------------------------------------------------
        // CASE1: successful load is pending until boundary.
        // ------------------------------------------------------------
        $display("CASE1 successful load -> pending -> boundary swap");
        pulse_load_start(16'd640, 16'd480, 16'd640);
        @(posedge clk); @(negedge clk);
        check_int(writer_start_count, 1, "case1 one writer_start");
        check_int(write_in_progress, 1, "case1 writing");
        check_int(load_ready, 0, "case1 load blocked while writing");
        check_base(read_base, A_BASE, "case1 display remains A while writing");
        check_base(write_base, B_BASE, "case1 writing B");
        check_int(write_width, 640, "case1 write width metadata");
        check_int(write_height, 480, "case1 write height metadata");
        check_int(write_stride_words, 640, "case1 write stride metadata");

        pulse_writer_done(1);
        @(posedge clk); @(negedge clk);
        check_int(write_in_progress, 0, "case1 writer complete");
        check_int(pending_swap, 1, "case1 pending swap");
        check_int(load_ready, 0, "case1 pending frame cannot be overwritten");
        check_base(read_base, A_BASE, "case1 still A before boundary");
        check_int(read_frame_valid, 0, "case1 old front still invalid before first swap");

        pulse_boundary;
        @(posedge clk); @(negedge clk);
        check_int(swap_count, 1, "case1 one swap");
        check_int(pending_swap, 0, "case1 pending cleared");
        check_base(read_base, B_BASE, "case1 B now front");
        check_base(write_base, A_BASE, "case1 A now back");
        check_int(read_frame_valid, 1, "case1 completed B is valid front");
        check_int(read_width, 640, "case1 read width follows swapped B metadata");
        check_int(read_height, 480, "case1 read height follows swapped B metadata");
        check_int(read_stride_words, 640, "case1 read stride follows swapped B metadata");
        check_int(load_ready, 1, "case1 next load ready");

        // ------------------------------------------------------------
        // CASE2: frame boundary during active write must do nothing.
        // Also verify load_start while busy is rejected.
        // ------------------------------------------------------------
        $display("CASE2 boundary/load request during active write are ignored");
        pulse_load_start(16'd320, 16'd240, 16'd640);
        @(posedge clk); @(negedge clk);
        check_int(writer_start_count, 2, "case2 second writer_start");
        pulse_boundary;
        @(posedge clk); @(negedge clk);
        check_int(swap_count, 1, "case2 no swap while write active");
        check_base(read_base, B_BASE, "case2 front remains B");

        pulse_load_start(16'd17, 16'd9, 16'd640); // illegal while busy, must be rejected
        @(posedge clk); @(negedge clk);
        check_int(writer_start_count, 2, "case2 busy load rejected");
        check_int(write_in_progress, 1, "case2 original load still active");

        pulse_writer_done(1);
        @(posedge clk); @(negedge clk);
        check_int(pending_swap, 1, "case2 completed frame pending");
        pulse_boundary;
        @(posedge clk); @(negedge clk);
        check_int(swap_count, 2, "case2 swap after completion");
        check_base(read_base, A_BASE, "case2 A restored front");
        check_base(write_base, B_BASE, "case2 B restored back");
        check_int(read_frame_valid, 1, "case2 A is valid after successful swap");
        check_int(read_width, 320, "case2 read width metadata=320");
        check_int(read_height, 240, "case2 read height metadata=240");

        // ------------------------------------------------------------
        // CASE3: writer_done and boundary same edge do NOT swap immediately.
        // This makes completed-frame visibility unambiguous and tear-free.
        // ------------------------------------------------------------
        $display("CASE3 writer_done + boundary same edge defers swap");
        pulse_load_start(16'd641, 16'd2, 16'd644);
        @(posedge clk); @(negedge clk);
        pulse_done_and_boundary_same_edge(1);
        @(posedge clk); @(negedge clk);
        check_int(pending_swap, 1, "case3 pending retained after coincident boundary");
        check_int(swap_count, 2, "case3 no immediate swap");
        check_base(read_base, A_BASE, "case3 current frame unchanged");

        // A new load while pending must be rejected to protect completed back buffer.
        pulse_load_start(16'd99, 16'd9, 16'd100);
        @(posedge clk); @(negedge clk);
        check_int(writer_start_count, 3, "case3 pending load rejected");

        pulse_boundary;
        @(posedge clk); @(negedge clk);
        check_int(swap_count, 3, "case3 swaps on next boundary");
        check_base(read_base, B_BASE, "case3 B front after deferred swap");
        check_base(write_base, A_BASE, "case3 A back after deferred swap");
        check_int(read_width, 641, "case3 deferred B width metadata");
        check_int(read_height, 2, "case3 deferred B height metadata");
        check_int(read_stride_words, 644, "case3 deferred B stride metadata");

        // ------------------------------------------------------------
        // CASE4: failed writer never changes current displayed frame.
        // Back buffer becomes reusable immediately after failure.
        // ------------------------------------------------------------
        $display("CASE4 writer failure preserves front frame");
        pulse_load_start(16'd100, 16'd10, 16'd640);
        @(posedge clk); @(negedge clk);
        pulse_writer_done(0);
        @(posedge clk); @(negedge clk);
        check_int(fail_count, 1, "case4 fail pulse");
        check_int(pending_swap, 0, "case4 no pending swap");
        check_base(read_base, B_BASE, "case4 front preserved");
        check_base(write_base, A_BASE, "case4 same back buffer reusable");
        check_int(read_frame_valid, 1, "case4 front remains valid");
        check_int(read_width, 641, "case4 front metadata preserved");
        check_int(load_ready, 1, "case4 load ready after failure");
        pulse_boundary;
        @(posedge clk); @(negedge clk);
        check_int(swap_count, 3, "case4 boundary cannot swap failed frame");

        // ------------------------------------------------------------
        // CASE5: retry after failure succeeds, proving no reset is required.
        // ------------------------------------------------------------
        $display("CASE5 retry after failure then swap");
        pulse_load_start(16'd17, 16'd9, 16'd640);
        @(posedge clk); @(negedge clk);
        check_int(writer_start_count, 5, "case5 writer_start count");
        pulse_writer_done(1);
        @(posedge clk); @(negedge clk);
        check_int(pending_swap, 1, "case5 retry pending");
        pulse_boundary;
        @(posedge clk); @(negedge clk);
        check_int(swap_count, 4, "case5 retry swap");
        check_base(read_base, A_BASE, "case5 A front");
        check_base(write_base, B_BASE, "case5 B back");
        check_int(read_width, 17, "case5 retry metadata visible");
        check_int(read_height, 9, "case5 retry height visible");

        // ------------------------------------------------------------
        // CASE6: several additional cycles to stress alternating ownership.
        // ------------------------------------------------------------
        $display("CASE6 repeated A/B ownership alternation");
        for (i = 0; i < 4; i = i + 1) begin
            pulse_load_start(16'd64 + i, 16'd32 + i, 16'd640);
            @(posedge clk); @(negedge clk);
            pulse_writer_done(1);
            @(posedge clk); @(negedge clk);
            pulse_boundary;
            @(posedge clk); @(negedge clk);
            invariant_distinct_buffers;
        end
        check_int(swap_count, 8, "case6 total swap count");
        check_int(pending_swap, 0, "case6 no pending at end");
        check_int(write_in_progress, 0, "case6 idle at end");
        check_int(load_ready, 1, "case6 ready at end");

        if (errors == 0)
            $display("PASS: frame_buffer_manager all adversarial cases passed (checks=%0d)", checks);
        else
            $display("FAIL: frame_buffer_manager errors=%0d checks=%0d", errors, checks);

        $finish;
    end

endmodule
