`timescale 1ns/1ps

module tb_m1c_coordinator_realmedia;
    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    reg media_cmd_valid = 0;
    reg [7:0] media_cmd_image_id = 0;
    reg [1:0] media_cmd_mode = 0;
    wire media_cmd_ready;

    reg frame_tx_busy = 0;
    wire frame_tx_request;
    wire [7:0] frame_tx_opcode;
    wire [2:0] frame_tx_length;
    wire [31:0] frame_tx_payload;

    reg rx_frame_valid = 0;
    reg [7:0] rx_frame_opcode = 0;
    reg [2:0] rx_frame_length = 0;
    reg [31:0] rx_frame_payload = 0;
    reg rx_frame_error = 0;
    reg rx_framing_error = 0;

    wire catalog_valid;
    wire [7:0] catalog_count;
    wire [7:0] remote_selected_image;
    wire [7:0] remote_status;
    wire [7:0] remote_error;
    wire link_ok, fault, ack_toggle, image_change_toggle;

    m1c_coordinator_uart #(
        .DISCOVERY_INTERVAL_CYCLES(4),
        .ACK_TIMEOUT_CYCLES(20),
        .STATUS_POLL_INTERVAL_CYCLES(4)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .media_cmd_valid(media_cmd_valid), .media_cmd_image_id(media_cmd_image_id),
        .media_cmd_mode(media_cmd_mode), .media_cmd_ready(media_cmd_ready),
        .frame_tx_busy(frame_tx_busy), .frame_tx_request(frame_tx_request),
        .frame_tx_opcode(frame_tx_opcode), .frame_tx_length(frame_tx_length),
        .frame_tx_payload(frame_tx_payload), .rx_frame_valid(rx_frame_valid),
        .rx_frame_opcode(rx_frame_opcode), .rx_frame_length(rx_frame_length),
        .rx_frame_payload(rx_frame_payload), .rx_frame_error(rx_frame_error),
        .rx_framing_error(rx_framing_error), .catalog_valid(catalog_valid),
        .catalog_count(catalog_count), .remote_selected_image(remote_selected_image),
        .remote_status(remote_status), .remote_error(remote_error), .link_ok(link_ok),
        .fault(fault), .ack_toggle(ack_toggle), .image_change_toggle(image_change_toggle)
    );

    integer errors = 0;
    integer checks = 0;

    task check;
        input condition;
        input [255:0] msg;
        begin
            checks = checks + 1;
            if (!condition) begin
                $display("ERROR: %s", msg);
                errors = errors + 1;
            end
        end
    endtask

    task reply;
        input [7:0] opcode;
        input [7:0] status;
        input [7:0] image_id;
        input [7:0] count;
        input [7:0] err;
        begin
            @(negedge clk);
            rx_frame_opcode = opcode;
            rx_frame_length = 4;
            rx_frame_payload = {err, count, image_id, status};
            rx_frame_valid = 1;
            @(negedge clk);
            rx_frame_valid = 0;
        end
    endtask

    initial begin #100000; $fatal(1,"watchdog"); end
    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1;

        // Discover a 3-image catalog.
        wait(frame_tx_request && frame_tx_opcode == 8'h00);
        reply(8'h80, 8'h04, 8'd0, 8'd3, 8'd0);
        repeat (2) @(posedge clk);
        check(catalog_valid && catalog_count == 3, "catalog discovered");
        check(media_cmd_ready, "coordinator idle after discovery");

        // Issue OPEN(1). Slave immediately ACKs ACCEPTED.
        @(negedge clk);
        media_cmd_image_id = 8'd1;
        media_cmd_valid = 1;
        @(negedge clk);
        media_cmd_valid = 0;
        wait(frame_tx_request && frame_tx_opcode == 8'h01);
        reply(8'h81, 8'h02, 8'd0, 8'd3, 8'd0);
        repeat (2) @(posedge clk);
        check(!media_cmd_ready, "ACCEPTED does not complete real-media OPEN");

        // First STATUS says still busy/accepted.
        wait(frame_tx_request && frame_tx_opcode == 8'h09);
        reply(8'h89, 8'h02, 8'd0, 8'd3, 8'd0);
        repeat (2) @(posedge clk);
        check(!media_cmd_ready, "busy STATUS keeps command blocked");

        // Drop one STATUS response: timeout must not release the next OPEN.
        wait(frame_tx_request && frame_tx_opcode == 8'h09);
        repeat(22) @(negedge clk);
        check(!media_cmd_ready, "missing reply retains media transaction");
        // Next STATUS reports requested image DONE.
        wait(frame_tx_request && frame_tx_opcode == 8'h09);
        reply(8'h89, 8'h04, 8'd1, 8'd3, 8'd0);
        repeat (2) @(posedge clk);
        check(media_cmd_ready, "DONE STATUS releases next command");
        check(remote_selected_image == 1, "remote selected image updated");
        check(link_ok && !fault, "link remains healthy");

        if (errors == 0)
            $display("PASS: m1c coordinator real-media completion gate checks=%0d", checks);
        else
            $fatal(1,"FAIL: m1c coordinator real-media completion gate errors=%0d checks=%0d", errors, checks);
        $finish;
    end
endmodule
