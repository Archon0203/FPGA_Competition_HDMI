`timescale 1ns/1ps
module tb_m1abc_control_link;
    reg clk_m = 1'b0;
    reg clk_s = 1'b0;
    reg rst_m_n = 1'b0;
    reg rst_s_n = 1'b0;
    reg key_next_n = 1'b1;
    reg key_prev_n = 1'b1;
    reg key_play_n = 1'b1;

    wire m_tx, s_tx;
    wire [3:0] m_led;
    wire [7:0] s_image;
    wire s_update_toggle, s_link, s_fault, s_cmd_toggle;
    wire s_packet_done, s_packet_pass;

    always #10.000 clk_m = ~clk_m;   // 50.000 MHz
    always #10.013 clk_s = ~clk_s;   // independent board oscillator model

    m1abc_master_control_top #(
        .UART_CLKS_PER_BIT(16),
        .POR_CYCLES(8),
        .SLIDE_PERIOD_CLKS(10000),
        .DISCOVERY_INTERVAL_CYCLES(200),
        .ACK_TIMEOUT_CYCLES(5000)
    ) u_master (
        .clk(clk_m), .rst_n(rst_m_n), .uart_rx(s_tx), .uart_tx(m_tx),
        .key_next_n(key_next_n), .key_prev_n(key_prev_n),
        .key_play_n(key_play_n), .led(m_led));

    m1abc_slave_control_core #(
        .UART_CLKS_PER_BIT(16), .POR_CYCLES(8)
    ) u_slave (
        .clk(clk_s), .rst_n(rst_s_n), .uart_rx(m_tx), .uart_tx(s_tx),
        .display_image_id(s_image), .display_update_toggle(s_update_toggle),
        .link_seen(s_link), .fault(s_fault), .command_toggle(s_cmd_toggle),
        .packet_test_done(s_packet_done), .packet_test_pass(s_packet_pass));

    integer errors = 0;
    integer checks = 0;
    integer guard;
    reg [7:0] expected;

    task check;
        input condition;
        input [255:0] message;
        begin
            checks = checks + 1;
            if (!condition) begin
                $display("ERROR: %s", message);
                errors = errors + 1;
            end
        end
    endtask

    task wait_image;
        input [7:0] image_id;
        begin
            guard = 0;
            while (s_image !== image_id && guard < 60000) begin
                @(posedge clk_s);
                guard = guard + 1;
            end
            check(s_image === image_id, "slave reached expected display image");
        end
    endtask

    initial begin
        repeat (10) @(posedge clk_m);
        rst_m_n = 1'b1;
        rst_s_n = 1'b1;

        guard = 0;
        while ((!m_led[1] || !s_link) && guard < 50000) begin
            @(posedge clk_m);
            guard = guard + 1;
        end
        check(m_led[1] === 1'b1, "master link_ok after discovery/open");
        check(s_link === 1'b1, "slave link_seen");

        guard = 0;
        while (!s_packet_done && guard < 50000) begin
            @(posedge clk_s);
            guard = guard + 1;
        end
        check(s_packet_done === 1'b1, "packet contract selftest completed");
        check(s_packet_pass === 1'b1, "packet contract sequence/CRC selftest passed");
        check(s_fault === 1'b0, "slave has no fault");

        // Initial catalog activation requests OPEN(0), then automatic rotation
        // must reach all remaining catalog entries through real UART frames.
        wait_image(8'd0);
        wait_image(8'd1);
        wait_image(8'd2);
        wait_image(8'd3);

        check(u_master.u_coordinator.catalog_count == 8'd4, "catalog count returned to master");
        check(u_master.u_coordinator.remote_error == 8'd0, "remote error zero");
        check(m_led[3] === 1'b0, "master fault LED low");

        if (errors == 0)
            $display("PASS: M1 ABC dual-board control link + A service + C auto selection (checks=%0d, image=%0d)", checks, s_image);
        else
            $fatal(1, "FAIL: M1 ABC control link errors=%0d checks=%0d", errors, checks);
        $finish;
    end
endmodule
