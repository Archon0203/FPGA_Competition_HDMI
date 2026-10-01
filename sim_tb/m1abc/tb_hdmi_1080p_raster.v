`timescale 1ns/1ps
module tb_hdmi_1080p_raster;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    wire active, frame_start, line_start, line_last, frame_boundary, hsync, vsync;
    wire [11:0] x, y;
    always #3.367 clk = ~clk; // ~148.5 MHz; frequency itself is not proven by this TB.

    hdmi_1080p_raster dut (
        .pix_clk(clk), .rst_n(rst_n), .active(active), .x(x), .y(y),
        .frame_start(frame_start), .line_start(line_start), .line_last(line_last),
        .frame_boundary(frame_boundary), .hsync(hsync), .vsync(vsync));

    integer active_pixels = 0;
    integer line_starts = 0;
    integer frame_seen = 0;
    integer guard = 0;

    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        while (frame_seen < 2 && guard < 6000000) begin
            @(posedge clk);
            guard = guard + 1;
            if (frame_start) begin
                if (frame_seen == 0) begin
                    active_pixels = 0;
                    line_starts = 0;
                    frame_seen = 1;
                end else begin
                    frame_seen = 2;
                end
            end
            if (frame_seen == 1) begin
                if (active) active_pixels = active_pixels + 1;
                if (line_start) line_starts = line_starts + 1;
            end
        end
        if (frame_seen != 2 || active_pixels != 1920*1080 || line_starts != 1080)
            $fatal(1, "FAIL: 1080p raster frames=%0d active=%0d lines=%0d guard=%0d", frame_seen, active_pixels, line_starts, guard);
        $display("PASS: 1080p canonical raster 2200x1125, active_pixels=%0d lines=%0d", active_pixels, line_starts);
        $finish;
    end
endmodule
