`timescale 1ns/1ps
module tb_m2_card_error_status;
    reg clk_m = 1'b0;
    reg clk_s = 1'b0;
    reg rst_m_n = 1'b0;
    reg rst_s_n = 1'b0;
    reg key_next_n = 1'b1;
    reg key_prev_n = 1'b1;
    reg key_play_n = 1'b1;

    always #10 clk_m = ~clk_m; // 50 MHz
    always #20 clk_s = ~clk_s; // 25 MHz; 16@50 == 8@25 UART bit time

    wire m_tx, s_tx;
    wire missing;
    wire [3:0] m_led;

    m2_master_media_control #(
        .UART_CLKS_PER_BIT(16),
        .POR_CYCLES(8),
        .SLIDE_PERIOD_CLKS(3000),
        .DISCOVERY_INTERVAL_CYCLES(100),
        .ACK_TIMEOUT_CYCLES(5000),
        .STATUS_POLL_INTERVAL_CYCLES(100), .KEY_FILTER_CYCLES(4)
    ) u_master (
        .clk(clk_m), .rst_n(rst_m_n), .uart_rx(s_tx), .uart_tx(m_tx),
        .key_next_n(key_next_n), .key_prev_n(key_prev_n),
        .key_play_n(key_play_n), .led(m_led), .card_missing(missing)
    );

    wire s_rx_valid, s_rx_frame_err, s_rx_framing_err, s_rx_activity;
    wire [7:0] s_rx_data;
    wire s_frame_valid;
    wire [7:0] s_frame_opcode;
    wire [2:0] s_frame_length;
    wire [31:0] s_frame_payload;
    wire s_uart_ready, s_uart_start, s_tx_busy, s_tx_request;
    wire [7:0] s_uart_data, s_tx_opcode;
    wire [2:0] s_tx_length;
    wire [31:0] s_tx_payload;
    wire open_request;
    wire [7:0] open_image_id;
    wire link_seen, bridge_fault, command_toggle, reply_toggle;

    reg catalog_valid = 1'b0;
    reg [7:0] catalog_count = 8'd0;
    reg source_busy = 1'b0;
    reg source_done = 1'b0;
    reg source_valid = 1'b0;
    reg source_error = 1'b1;
    reg [7:0] source_error_code = 8'h41;
    reg [7:0] selected_image_id = 8'd0;

    db_uart_rx #(.CLKS_PER_BIT(8)) u_s_rx (
        .clk(clk_s), .rst_n(rst_s_n), .rx(m_tx),
        .valid(s_rx_valid), .data(s_rx_data),
        .framing_error(s_rx_framing_err), .rx_activity(s_rx_activity));
    db_ctrl_frame_parser u_s_parser (
        .clk(clk_s), .rst_n(rst_s_n), .byte_valid(s_rx_valid),
        .byte_data(s_rx_data), .frame_valid(s_frame_valid),
        .opcode(s_frame_opcode), .length(s_frame_length),
        .payload(s_frame_payload), .frame_error(s_rx_frame_err));
    db_uart_tx #(.CLKS_PER_BIT(8)) u_s_tx (
        .clk(clk_s), .rst_n(rst_s_n), .start(s_uart_start),
        .data(s_uart_data), .ready(s_uart_ready), .tx(s_tx));
    db_ctrl_frame_tx u_s_frame_tx (
        .clk(clk_s), .rst_n(rst_s_n), .request(s_tx_request),
        .opcode(s_tx_opcode), .length(s_tx_length), .payload(s_tx_payload),
        .uart_ready(s_uart_ready), .uart_start(s_uart_start),
        .uart_data(s_uart_data), .busy(s_tx_busy));
    m2_real_media_uart_bridge u_bridge (
        .clk(clk_s), .rst_n(rst_s_n),
        .rx_frame_valid(s_frame_valid), .rx_frame_opcode(s_frame_opcode),
        .rx_frame_length(s_frame_length), .rx_frame_payload(s_frame_payload),
        .rx_frame_error(s_rx_frame_err), .rx_framing_error(s_rx_framing_err),
        .frame_tx_busy(s_tx_busy), .frame_tx_request(s_tx_request),
        .frame_tx_opcode(s_tx_opcode), .frame_tx_length(s_tx_length),
        .frame_tx_payload(s_tx_payload), .catalog_valid(catalog_valid),
        .catalog_count(catalog_count), .source_busy(source_busy),
        .source_done(source_done), .source_valid(source_valid), .source_error(source_error),
        .source_error_code(source_error_code), .selected_image_id(selected_image_id),
        .open_request(open_request), .open_image_id(open_image_id),
        .link_seen(link_seen), .fault(bridge_fault),
        .command_toggle(command_toggle), .reply_toggle(reply_toggle));

    initial begin
        repeat(5) @(negedge clk_m);rst_m_n=1;rst_s_n=1;
        wait(missing);repeat(10) @(negedge clk_m);
        if(u_master.u_coordinator.remote_error!=8'h41) $fatal(1,"SD detail lost in UART");
        source_error_code=8'h21;
        wait(!missing);
        if(u_master.u_coordinator.remote_error!=8'h21) $fatal(1,"bad file mistaken for missing TF");
        source_error=0;source_valid=1;catalog_valid=1;catalog_count=4;
        wait(u_master.catalog_valid);
        if(missing) $fatal(1,"missing card page persists after recovery");
        $display("PASS: UART Slave SD init error -> Master card UI flag, bad-file discrimination, recovery");$finish;
    end
    initial begin #5000000;$fatal(1,"card error status watchdog");end
endmodule
