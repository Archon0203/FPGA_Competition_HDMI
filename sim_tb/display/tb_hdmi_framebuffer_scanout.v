`timescale 1ns/1ps

module tb_hdmi_framebuffer_scanout;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg enable = 1'b1;

    wire read_start;
    wire [15:0] read_line;
    wire [15:0] read_width;
    wire pixel_valid;
    wire [23:0] pixel_data;
    wire line_done;
    wire frame_boundary;
    wire active_expected;
    wire timing_error;

    reg fill_start = 1'b0;
    reg [15:0] fill_line = 0;
    reg [15:0] fill_width = 8;
    wire fill_ready;
    reg fill_valid = 1'b0;
    reg [23:0] fill_data = 0;
    reg fill_done = 1'b0;
    reg fill_ok = 1'b0;

    wire underflow_sticky;
    wire lb_protocol_error;

    integer checks = 0;
    integer active_pixels = 0;
    integer expected_line;
    integer expected_x;

    always #20 clk = ~clk;

    line_buffer_pingpong #(.MAX_LINE_PIXELS(8)) u_lb (
        .clk(clk), .rst_n(rst_n),
        .fill_start(fill_start), .fill_line_index(fill_line), .fill_width(fill_width),
        .fill_ready(fill_ready), .fill_accept(), .fill_valid(fill_valid),
        .fill_data(fill_data), .fill_done(fill_done), .fill_ok(fill_ok),
        .fill_commit_pulse(), .fill_fail_pulse(),
        .read_start(read_start), .read_line_index(read_line), .read_width(read_width),
        .pixel_valid(pixel_valid), .pixel_data(pixel_data), .line_done(line_done),
        .underflow_pulse(), .underflow_sticky(underflow_sticky),
        .protocol_error(lb_protocol_error), .fill_active(), .read_active(),
        .bank0_ready(), .bank1_ready()
    );

    hdmi_framebuffer_scanout #(
        .HACTIVE(8), .HFP(1), .HSA(1), .HBP(2),
        .VACTIVE(2), .VFP(1), .VSA(1), .VBP(1)
    ) dut (
        .clk_pix(clk), .rst_n(rst_n), .enable(enable),
        .lb_read_start(read_start), .lb_read_line_index(read_line),
        .lb_read_width(read_width), .lb_pixel_valid(pixel_valid),
        .lb_pixel_data(pixel_data), .lb_line_done(line_done),
        .pixel_valid(), .pixel_data(), .frame_boundary(frame_boundary),
        .active_expected(active_expected), .timing_error(timing_error),
        .h_count_debug(), .v_count_debug()
    );

    task fill_one_line;
        input integer line;
        integer i;
        begin
            wait (fill_ready);
            @(posedge clk);
            fill_line  <= line;
            fill_start <= 1'b1;
            @(posedge clk);
            fill_start <= 1'b0;
            for (i = 0; i < 8; i = i + 1) begin
                fill_valid <= 1'b1;
                fill_data  <= {8'h10 + line[7:0], 8'h20, i[7:0]};
                fill_done  <= (i == 7);
                fill_ok    <= (i == 7);
                @(posedge clk);
            end
            fill_valid <= 1'b0;
            fill_done  <= 1'b0;
            fill_ok    <= 1'b0;
        end
    endtask

    always @(posedge clk) begin
        if (rst_n && active_expected) begin
            if (!pixel_valid) begin
                $display("FAIL: expected active without pixel_valid");
                $finish;
            end
            expected_line = active_pixels / 8;
            expected_x    = active_pixels % 8;
            if (pixel_data !== {8'h10 + expected_line[7:0], 8'h20, expected_x[7:0]}) begin
                $display("FAIL: pixel line=%0d x=%0d got=%h", expected_line, expected_x, pixel_data);
                $finish;
            end
            active_pixels = active_pixels + 1;
            checks = checks + 2;
        end
    end

    initial begin
        repeat (3) @(posedge clk);
        rst_n <= 1'b1;
        // Three blank lines provide enough time to fill both banks.
        fill_one_line(0);
        fill_one_line(1);

        wait (active_pixels == 16);
        repeat (3) @(posedge clk);

        if (timing_error || lb_protocol_error || underflow_sticky) begin
            $display("FAIL: timing=%b lb_protocol=%b underflow=%b",
                     timing_error, lb_protocol_error, underflow_sticky);
            $finish;
        end
        checks = checks + 3;
        $display("PASS: hdmi_framebuffer_scanout passed (checks=%0d)", checks);
        $finish;
    end

    initial begin
        #100000;
        $display("FAIL: timeout active_pixels=%0d", active_pixels);
        $finish;
    end
endmodule
