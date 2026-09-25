`timescale 1ns/1ps

module tb_media_command_controller;
    // Keep manual-command scenarios below the automatic period so their
    // handshake checks are isolated from the separate rotation test.
    localparam integer PERIOD = 16;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [3:0] key_event = 4'b0000;
    reg [3:0] sw = 4'b0000;
    reg catalog_valid = 1'b0;
    reg [7:0] catalog_count = 8'd0;
    reg media_cmd_ready = 1'b0;

    wire media_cmd_valid;
    wire [7:0] media_cmd_image_id;
    wire [1:0] media_cmd_mode;
    wire [7:0] selected_image_id;
    wire play_en, emergency, slide_tick, osd_en, beep_alert;
    wire [1:0] transition_mode;
    wire [7:0] contrast;
    wire signed [7:0] brightness;

    media_command_controller #(.SLIDE_PERIOD_CLKS(PERIOD)) dut (
        .clk(clk), .rst_n(rst_n), .key_event(key_event), .sw(sw),
        .catalog_valid(catalog_valid), .catalog_count(catalog_count),
        .media_cmd_ready(media_cmd_ready), .media_cmd_valid(media_cmd_valid),
        .media_cmd_image_id(media_cmd_image_id), .media_cmd_mode(media_cmd_mode),
        .selected_image_id(selected_image_id), .play_en(play_en),
        .emergency(emergency), .slide_tick(slide_tick),
        .transition_mode(transition_mode), .contrast(contrast),
        .brightness(brightness), .osd_en(osd_en), .beep_alert(beep_alert)
    );

    always #5 clk = ~clk;

    integer errors = 0;
    integer checks = 0;
    integer i;

    task check;
        input [31:0] actual;
        input [31:0] expected;
        input [255:0] message;
        begin
            checks = checks + 1;
            if (actual !== expected) begin
                $display("ERROR: %s actual=%0d expected=%0d", message, actual, expected);
                errors = errors + 1;
            end
        end
    endtask

    task key_pulse;
        input [3:0] event_value;
        begin
            @(negedge clk);
            key_event = event_value;
            @(negedge clk);
            key_event = 4'b0000;
        end
    endtask

    task accept_command;
        input [7:0] expected_image;
        begin
            check(media_cmd_valid, 1, "command valid before acceptance");
            check(media_cmd_image_id, expected_image, "command image before acceptance");
            check(media_cmd_mode, 0, "command mode is OPEN");
            @(negedge clk);
            media_cmd_ready = 1'b1;
            @(negedge clk);
            media_cmd_ready = 1'b0;
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        check(media_cmd_valid, 0, "no catalog produces no command");
        check(play_en, 1, "reset play enabled");
        check(emergency, 0, "reset emergency off");
        check(osd_en, 1, "reset OSD enabled");

        // A catalog creates a single initial OPEN(0), held until accepted.
        @(negedge clk);
        catalog_count = 8'd4;
        catalog_valid = 1'b1;
        @(posedge clk);
        #1;
        check(media_cmd_valid, 1, "catalog issues initial command");
        check(media_cmd_image_id, 0, "initial image zero");

        // While ready is low, current payload remains stable and two manual
        // next events collapse into the newest requested image.
        key_pulse(4'b0010);
        key_pulse(4'b0010);
        #1;
        check(media_cmd_valid, 1, "blocked command stays valid");
        check(media_cmd_image_id, 0, "blocked payload remains stable");
        check(selected_image_id, 2, "latest desired image retained");

        accept_command(0);
        #1;
        check(media_cmd_valid, 1, "deferred command emitted");
        check(media_cmd_image_id, 2, "deferred command uses latest image");
        accept_command(2);
        #1;
        check(media_cmd_valid, 0, "queue drains after acceptance");

        // KEY0 pauses automatic rotation.  KEY1 still creates a manual open.
        key_pulse(4'b0001);
        check(play_en, 0, "play paused");
        for (i = 0; i < PERIOD + 2; i = i + 1) @(posedge clk);
        check(selected_image_id, 2, "pause blocks automatic rotation");
        key_pulse(4'b0010);
        #1;
        check(media_cmd_image_id, 3, "manual next works while paused");
        accept_command(3);

        // Previous selection is also a high-level OPEN command and wraps at
        // image zero.  Restore image three before the automatic-wrap test.
        key_pulse(4'b0100);
        #1;
        check(selected_image_id, 2, "manual previous decrements image");
        check(media_cmd_image_id, 2, "manual previous command");
        accept_command(2);
        key_pulse(4'b0010);
        #1;
        check(selected_image_id, 3, "manual next restores image three");
        accept_command(3);

        // Resume, then verify a fixed-period automatic command and tick.
        key_pulse(4'b0001);
        check(play_en, 1, "play resumed");
        repeat (PERIOD) @(posedge clk);
        #1;
        check(slide_tick, 1, "automatic rotation tick");
        check(media_cmd_valid, 1, "automatic command valid");
        check(media_cmd_image_id, 0, "automatic command wraps");
        accept_command(0);

        // Emergency is master-local: it mutes rotation and raises the alert,
        // without creating a media load command.
        key_pulse(4'b1000);
        check(emergency, 1, "emergency enabled");
        check(beep_alert, 1, "emergency alert enabled");
        repeat (PERIOD + 1) @(posedge clk);
        check(media_cmd_valid, 0, "emergency creates no media command");
        key_pulse(4'b1000);
        check(emergency, 0, "emergency disabled");

        // Switch values form a stable system-domain configuration snapshot.
        @(negedge clk);
        sw = 4'b1110;
        @(posedge clk);
        #1;
        check(transition_mode, 2, "transition switch map");
        check(contrast, 128, "contrast switch map");
        check(brightness, 32, "brightness switch map");

        // Catalog loss cancels an unaccepted command; a new catalog restarts
        // from image zero instead of retaining stale metadata.
        key_pulse(4'b0010);
        check(media_cmd_valid, 1, "manual command queued before catalog loss");
        @(negedge clk);
        catalog_valid = 1'b0;
        @(posedge clk);
        #1;
        check(media_cmd_valid, 0, "catalog loss cancels command");
        check(selected_image_id, 0, "catalog loss clears selected image");

        @(negedge clk);
        catalog_valid = 1'b1;
        @(posedge clk);
        #1;
        check(media_cmd_valid, 1, "new catalog restarts initial command");
        check(media_cmd_image_id, 0, "new catalog restarts at image zero");

        if (errors == 0)
            $display("PASS: media_command_controller (checks=%0d)", checks);
        else
            $display("FAIL: media_command_controller (%0d errors, checks=%0d)", errors, checks);
        $finish;
    end
endmodule
