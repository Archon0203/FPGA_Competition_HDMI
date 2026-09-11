`timescale 1ns/1ps

// P1-03A sub-chain: real line_buffer_pingpong -> hdmi_video_adapter ->
// APUG092-like ready sink scoreboard. This does not model encrypted APUG092;
// it proves the project-owned continuity/packetization boundary.
module tb_hdmi_video_linebuffer_chain;
    localparam W = 8;
    localparam H = 2;

    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;

    reg fill_start = 0;
    reg [15:0] fill_line_index = 0;
    reg [15:0] fill_width = 0;
    wire fill_ready;
    wire fill_accept;
    reg fill_valid = 0;
    reg [23:0] fill_data = 0;
    reg fill_done = 0;
    reg fill_ok = 0;
    wire fill_commit_pulse, fill_fail_pulse;

    wire lb_read_start;
    wire [15:0] lb_read_line_index, lb_read_width;
    wire lb_pixel_valid;
    wire [23:0] lb_pixel_data;
    wire lb_line_done;
    wire underflow_pulse, underflow_sticky;
    wire lb_protocol_error;

    reg enable = 0;
    reg axis_ready = 0;
    wire axis_user, axis_valid, axis_last;
    wire [23:0] axis_data;
    wire frame_done_pulse, adapter_protocol_error;

    integer checks = 0;
    integer errors = 0;
    integer beats = 0;
    integer users = 0;
    integer lasts = 0;
    integer frames = 0;
    integer k;
    reg [23:0] expected;

    function [23:0] pattern;
        input integer line_no;
        input integer x;
        begin pattern = {line_no[7:0], x[7:0], 8'hA5}; end
    endfunction

    task check;
        input condition;
        input [8*100-1:0] what;
        begin
            checks = checks + 1;
            if (!condition) begin
                $display("ERROR: %0s @%0t", what, $time);
                errors = errors + 1;
            end
        end
    endtask

    task fill_one_line;
        input integer line_no;
        begin
            while (!fill_ready) @(negedge clk);
            fill_line_index = line_no;
            fill_width = W;
            fill_start = 1;
            @(negedge clk);
            fill_start = 0;
            for (k=0; k<W; k=k+1) begin
                fill_data = pattern(line_no,k);
                fill_valid = 1;
                @(negedge clk);
            end
            fill_valid = 0;
            fill_ok = 1;
            fill_done = 1;
            @(negedge clk);
            fill_done = 0;
            fill_ok = 0;
            @(negedge clk);
        end
    endtask

    line_buffer_pingpong #(.MAX_LINE_PIXELS(W)) u_lb (
        .clk(clk), .rst_n(rst_n),
        .fill_start(fill_start), .fill_line_index(fill_line_index),
        .fill_width(fill_width), .fill_ready(fill_ready), .fill_accept(fill_accept),
        .fill_valid(fill_valid), .fill_data(fill_data), .fill_done(fill_done),
        .fill_ok(fill_ok), .fill_commit_pulse(fill_commit_pulse),
        .fill_fail_pulse(fill_fail_pulse),
        .read_start(lb_read_start), .read_line_index(lb_read_line_index),
        .read_width(lb_read_width), .pixel_valid(lb_pixel_valid),
        .pixel_data(lb_pixel_data), .line_done(lb_line_done),
        .underflow_pulse(underflow_pulse), .underflow_sticky(underflow_sticky),
        .protocol_error(lb_protocol_error), .fill_active(), .read_active(),
        .bank0_ready(), .bank1_ready()
    );

    hdmi_video_adapter #(.ACTIVE_WIDTH(W), .ACTIVE_HEIGHT(H)) u_adapter (
        .clk_pix(clk), .rst_n(rst_n), .enable(enable),
        .lb_read_start(lb_read_start), .lb_read_line_index(lb_read_line_index),
        .lb_read_width(lb_read_width), .lb_pixel_valid(lb_pixel_valid),
        .lb_pixel_data(lb_pixel_data), .lb_line_done(lb_line_done),
        .axis_user(axis_user), .axis_valid(axis_valid), .axis_last(axis_last),
        .axis_data(axis_data), .axis_ready(axis_ready),
        .frame_done_pulse(frame_done_pulse), .protocol_error(adapter_protocol_error),
        .current_line(), .current_pixel()
    );

    // Scoreboard at the receiving clock edge, matching APUG092 pixel-domain sampling.
    always @(posedge clk) begin
        if (rst_n && axis_valid) begin
            expected = pattern(beats / W, beats % W);
            check(axis_data === expected, "RGB order/data preserved");
            check(axis_user == (beats == 0), "SOF user position");
            check(axis_last == ((beats % W) == W-1), "EOL last position");
            beats = beats + 1;
            if (axis_user) users = users + 1;
            if (axis_last) lasts = lasts + 1;
        end
        if (rst_n && frame_done_pulse) frames = frames + 1;
    end

    initial begin
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1;

        // Preload both ping-pong banks before enabling display.
        fill_one_line(0);
        fill_one_line(1);
        check(!lb_protocol_error, "line buffer preload clean");

        // APUG092 boundary ready may be low before the frame begins.
        axis_ready = 0;
        enable = 1;
        repeat (4) @(posedge clk);
        check(lb_read_start == 0, "adapter waits for APUG ready");

        axis_ready = 1;
        while (!frame_done_pulse && errors == 0) @(negedge clk);
        // Stop before the adapter can request frame 2; this sub-chain test only
        // preloads one two-line frame.
        enable = 0;
        repeat (2) @(posedge clk);

        check(beats == W*H, "exact active-frame beat count");
        check(users == 1, "one SOF per frame");
        check(lasts == H, "one EOL per line");
        check(frames == 1, "one frame_done pulse");
        check(!underflow_sticky, "preloaded frame has no underflow");
        check(!lb_protocol_error, "line buffer protocol clean");
        check(!adapter_protocol_error, "adapter protocol clean");

        if (errors == 0)
            $display("PASS: line_buffer -> hdmi_video_adapter sub-chain passed (checks=%0d)", checks);
        else
            $display("FAIL: line_buffer -> hdmi_video_adapter errors=%0d checks=%0d", errors, checks);
        $finish;
    end
endmodule
