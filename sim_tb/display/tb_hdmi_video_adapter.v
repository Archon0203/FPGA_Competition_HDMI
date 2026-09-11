`timescale 1ns/1ps

module tb_hdmi_video_adapter;
    localparam W = 8;
    localparam H = 3;

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst_n = 0;
    reg enable = 0;

    wire lb_read_start;
    wire [15:0] lb_read_line_index;
    wire [15:0] lb_read_width;
    reg lb_pixel_valid = 0;
    reg [23:0] lb_pixel_data = 0;
    reg lb_line_done = 0;

    wire axis_user, axis_valid, axis_last;
    wire [23:0] axis_data;
    reg axis_ready = 0;

    wire frame_done_pulse;
    wire protocol_error;
    wire [15:0] current_line, current_pixel;

    integer checks = 0;
    integer req_count = 0;
    integer beat_count = 0;
    integer user_count = 0;
    integer last_count = 0;
    integer frame_count = 0;
    integer i;

    hdmi_video_adapter #(.ACTIVE_WIDTH(W), .ACTIVE_HEIGHT(H)) dut (
        .clk_pix(clk), .rst_n(rst_n), .enable(enable),
        .lb_read_start(lb_read_start), .lb_read_line_index(lb_read_line_index),
        .lb_read_width(lb_read_width), .lb_pixel_valid(lb_pixel_valid),
        .lb_pixel_data(lb_pixel_data), .lb_line_done(lb_line_done),
        .axis_user(axis_user), .axis_valid(axis_valid), .axis_last(axis_last),
        .axis_data(axis_data), .axis_ready(axis_ready),
        .frame_done_pulse(frame_done_pulse), .protocol_error(protocol_error),
        .current_line(current_line), .current_pixel(current_pixel)
    );

    task check;
        input condition;
        input [8*100-1:0] what;
        begin
            checks = checks + 1;
            if (!condition) begin
                $display("ERROR: %0s @ %0t", what, $time);
                $fatal(1);
            end
        end
    endtask

    task send_line;
        input integer line_no;
        input integer break_valid_at;
        input integer drop_ready_at;
        begin
            // Wait for the adapter request. The mock APUG side may keep ready
            // low for arbitrary whole-line boundary stalls.
            while (!lb_read_start) @(posedge clk);
            check(lb_read_line_index == line_no, "requested expected line index");
            check(lb_read_width == W, "requested configured width");
            req_count = req_count + 1;

            // line_buffer contract: first pixel starts after read_start.
            @(negedge clk);
            for (i = 0; i < W; i = i + 1) begin
                lb_pixel_valid = (i != break_valid_at);
                lb_pixel_data  = {line_no[7:0], i[7:0], 8'h5a};
                lb_line_done   = (i == W-1);
                if (i == drop_ready_at) axis_ready = 1'b0;
                else if (drop_ready_at >= 0) axis_ready = 1'b1;
                @(posedge clk);
                @(negedge clk);
            end
            lb_pixel_valid = 0;
            lb_line_done   = 0;
            axis_ready     = 1'b1;
        end
    endtask

    always @(posedge clk) begin
        if (axis_valid) begin
            beat_count = beat_count + 1;
            if (axis_user) user_count = user_count + 1;
            if (axis_last) last_count = last_count + 1;
        end
        if (frame_done_pulse) frame_count = frame_count + 1;
    end

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1;
        enable = 1;

        // CASE0: no line request until APUG092 ready.
        axis_ready = 0;
        repeat (5) @(posedge clk);
        check(req_count == 0, "no request while APUG ready is low");
        check(lb_read_start == 0, "read_start remains low while not ready");

        // CASE1: complete frame, with legal ready stalls between lines.
        axis_ready = 1;
        send_line(0, -1, -1);
        // emulate documented boundary backpressure after EOL
        axis_ready = 0;
        repeat (3) @(posedge clk);
        check(lb_read_start == 0, "no next line request during boundary backpressure");
        axis_ready = 1;
        send_line(1, -1, -1);
        axis_ready = 0;
        repeat (2) @(posedge clk);
        axis_ready = 1;
        send_line(2, -1, -1);
        repeat (2) @(posedge clk);

        check(req_count == 3, "one request per active line");
        check(beat_count == W*H, "all frame pixels emitted");
        check(user_count == 1, "SOF user exactly once per frame");
        check(last_count == H, "EOL last exactly once per line");
        check(frame_count == 1, "frame_done exactly once");
        check(protocol_error == 0, "clean frame has no protocol error");

        // CASE2: verify frame wraps and SOF appears again.
        send_line(0, -1, -1);
        check(user_count == 2, "SOF asserted on next frame first line");

        // CASE3: mid-line ready drop is illegal and sticky-detected. Reset first.
        enable = 0;
        rst_n = 0;
        repeat (2) @(posedge clk);
        rst_n = 1;
        enable = 1;
        axis_ready = 1;
        send_line(0, -1, 3);
        repeat (2) @(posedge clk);
        check(protocol_error == 1, "mid-line ready drop detected");

        // CASE4: line-buffer active-line gap is illegal and sticky-detected.
        enable = 0;
        rst_n = 0;
        repeat (2) @(posedge clk);
        rst_n = 1;
        enable = 1;
        axis_ready = 1;
        send_line(0, 4, -1);
        repeat (2) @(posedge clk);
        check(protocol_error == 1, "pixel-valid gap detected");

        $display("PASS: hdmi_video_adapter APUG092 contract passed (checks=%0d)", checks);
        $finish;
    end
endmodule
