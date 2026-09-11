`timescale 1ns/1ps

// P1-03B protected-core simulation candidate.
// This intentionally stops at APUG092's 10-bit TMDS parallel outputs so that
// Questa does not need an EG_LOGIC_ODDR primitive model.  The official EG PHY
// is covered later by TD elaboration/P&R in FPGA_Competition_HDMI_P1-03B.al.
module tb_apug092_external_video_core;
    localparam W = 1280;
    localparam H = 720;

    reg clk = 0;
    // 74.25 MHz 720p transport baseline pixel clock.
    always #6.734007 clk = ~clk;

    reg rst_n = 0;

    wire lb_read_start;
    wire [15:0] lb_read_line_index;
    wire [15:0] lb_read_width;
    wire lb_pixel_valid;
    wire [23:0] lb_pixel_data;
    wire lb_line_done;
    wire provider_busy;
    wire provider_error;

    wire axis_user, axis_valid, axis_last, axis_ready;
    wire [23:0] axis_data;
    wire frame_done;
    wire adapter_error;
    wire [15:0] current_line, current_pixel;

    wire video_locked;
    wire ddc_scl;
    tri1 ddc_sda;
    wire [9:0] ch0, ch1, ch2, clk_ch;

    integer checks = 0;
    integer errors = 0;
    integer frames = 0;
    integer cycles = 0;
    integer tmds_changes = 0;
    reg [39:0] prev_tmds = 40'd0;

    task check;
        input condition;
        input [8*120-1:0] what;
        begin
            checks = checks + 1;
            if (!condition) begin
                errors = errors + 1;
                $display("ERROR: %0s @ %0t", what, $time);
            end
        end
    endtask

    hdmi_test_pattern_line_provider #(.ACTIVE_WIDTH(W), .ACTIVE_HEIGHT(H)) u_provider (
        .clk_pix(clk), .rst_n(rst_n),
        .read_start(lb_read_start), .read_line_index(lb_read_line_index),
        .read_width(lb_read_width), .pixel_valid(lb_pixel_valid),
        .pixel_data(lb_pixel_data), .line_done(lb_line_done),
        .busy(provider_busy), .protocol_error(provider_error)
    );

    hdmi_video_adapter #(.ACTIVE_WIDTH(W), .ACTIVE_HEIGHT(H)) u_adapter (
        .clk_pix(clk), .rst_n(rst_n), .enable(1'b1),
        .lb_read_start(lb_read_start), .lb_read_line_index(lb_read_line_index),
        .lb_read_width(lb_read_width), .lb_pixel_valid(lb_pixel_valid),
        .lb_pixel_data(lb_pixel_data), .lb_line_done(lb_line_done),
        .axis_user(axis_user), .axis_valid(axis_valid), .axis_last(axis_last),
        .axis_data(axis_data), .axis_ready(axis_ready),
        .frame_done_pulse(frame_done), .protocol_error(adapter_error),
        .current_line(current_line), .current_pixel(current_pixel)
    );

    apug092_core_wrapper #(
        .HACTIVE(1280), .HFP(110), .HSA(40), .HBP(220),
        .VACTIVE(720), .VFP(5), .VSA(5), .VBP(20),
        .VIDEO_VIC(69), .IIC_SCL_DIV(125)
    ) u_core (
        .pixel_clk(clk), .rst(~rst_n),
        .edid_read_trig(1'b0), .edid_read_valid(), .edid_read_data(),
        .axis_user(axis_user), .axis_valid(axis_valid),
        .axis_last(axis_last), .axis_data(axis_data), .axis_ready(axis_ready),
        .audio_valid(1'b0), .audio_left_data(24'd0), .audio_right_data(24'd0),
        .acr_valid(1'b0), .acr_cts(20'd0), .acr_n(20'd0),
        .video_locked(video_locked), .ddc_scl(ddc_scl), .ddc_sda(ddc_sda),
        .ch0_tmds_data(ch0), .ch1_tmds_data(ch1),
        .ch2_tmds_data(ch2), .clk_tmds_data(clk_ch)
    );

    always @(posedge clk) begin
        if (rst_n) begin
            cycles = cycles + 1;
            if (frame_done) frames = frames + 1;
            if ({clk_ch,ch2,ch1,ch0} !== prev_tmds)
                tmds_changes = tmds_changes + 1;
            prev_tmds <= {clk_ch,ch2,ch1,ch0};
        end
    end

    initial begin : run_test
        repeat (10) @(posedge clk);
        @(negedge clk); rst_n = 1;

        // Allow several real 1280x720 frames for APUG092 phase matching.
        while ((cycles < 5000000) && !((frames >= 2) && video_locked))
            @(posedge clk);

        check(frames >= 1, "external source completed at least one active frame");
        check(provider_error == 0, "test line provider protocol clean");
        check(adapter_error == 0, "APUG092 line-continuity contract clean");
        check(video_locked == 1, "APUG092 O_video_locked asserted");
        check(tmds_changes > 100, "protected APUG092 TMDS words are active");

        if (errors == 0)
            $display("PASS: APUG092 external-video protected-core chain passed (checks=%0d frames=%0d)", checks, frames);
        else
            $display("FAIL: APUG092 external-video core errors=%0d checks=%0d frames=%0d locked=%0b", errors, checks, frames, video_locked);
        $finish;
    end
endmodule
