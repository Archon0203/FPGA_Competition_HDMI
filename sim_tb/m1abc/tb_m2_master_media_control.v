`timescale 1ns/1ps
module tb_m2_master_media_control;
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
        .key_play_n(key_play_n), .led(m_led)
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

    reg catalog_valid = 1'b1;
    reg [7:0] catalog_count = 8'd4;
    reg source_busy = 1'b0;
    reg source_done = 1'b0;
    reg source_valid = 1'b1;
    reg source_error = 1'b0;
    reg [7:0] source_error_code = 8'h00;
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

    integer errors = 0;
    integer checks = 0;
    integer open_count = 0;
    integer load_countdown = 0;
    integer guard;
    reg [7:0] load_target = 0;
    reg [7:0] expected_id;

    task check;
        input condition;
        input [255:0] message;
        begin
            checks = checks + 1;
            if (!condition) begin
                errors = errors + 1;
                $display("ERROR: %0s", message);
            end
        end
    endtask

    always @(posedge clk_s or negedge rst_s_n) begin
        if (!rst_s_n) begin
            source_busy <= 1'b0;
            source_done <= 1'b0;
            source_valid <= 1'b1; // model Slave standalone image 0 already displayed
            selected_image_id <= 8'd0;
            load_countdown <= 0;
            load_target <= 0;
            open_count <= 0;
        end else begin
            source_done <= 1'b0;
            if (open_request) begin
                case (open_count[1:0])
                    2'd0: expected_id = 8'd1;
                    2'd1: expected_id = 8'd2;
                    2'd2: expected_id = 8'd3;
                    default: expected_id = 8'd0;
                endcase
                if (open_count < 3 && open_image_id !== expected_id) begin
                    errors = errors + 1;
                    $display("ERROR: OPEN sequence count=%0d got=%0d expected=%0d",
                             open_count, open_image_id, expected_id);
                end
                open_count <= open_count + 1;
                load_target <= open_image_id;
                if (source_busy) $fatal(1,"OPEN overlaps outstanding media load");
                load_countdown <= 12000; // far longer than slide period and ACK timeout
                source_busy <= 1'b1;
                source_valid <= 1'b0;
            end else if (load_countdown != 0) begin
                load_countdown <= load_countdown - 1;
                if (load_countdown == 1) begin
                    selected_image_id <= load_target;
                    source_busy <= 1'b0;
                    source_valid <= 1'b1;
                    source_done <= 1'b1;
                end
            end
        end
    end

    task press;
        input integer key;
        begin
            @(negedge clk_m);
            case(key) 0: key_play_n=0; 1: key_next_n=0; 2: key_prev_n=0; endcase
            repeat(12) @(negedge clk_m);
            key_play_n=1; key_next_n=1; key_prev_n=1;
            repeat(12) @(negedge clk_m);
        end
    endtask
    task wait_visible;
        input [7:0] id;
        begin
            guard=0;
            while ((selected_image_id!=id || !u_master.media_cmd_ready) && guard<60000) begin
                @(negedge clk_m); guard=guard+1;
            end
            check(guard<60000,"requested image reaches visible DONE");
        end
    endtask
    initial begin #20000000; $fatal(1,"watchdog"); end

    initial begin
        repeat (8) @(posedge clk_m);
        rst_m_n = 1'b1;
        rst_s_n = 1'b1;

        guard = 0;
        while ((!m_led[1] || !link_seen) && guard < 50000) begin
            @(posedge clk_m); guard = guard + 1;
        end
        check(m_led[1] === 1'b1, "Master discovery link_ok");
        check(link_seen === 1'b1, "real-media bridge saw Master");

        guard = 0;
        while (open_count < 3 && guard < 200000) begin
            @(posedge clk_m); guard = guard + 1;
        end
        press(0); // pause while the third image is still loading
        check(!u_master.play_en,"physical pause key disables carousel");
        check(open_count >= 3, "preloaded image 0 deduped; slideshow emitted OPEN 1,2,3");

        guard = 0;
        while (selected_image_id != 8'd3 && guard < 16000) begin
            @(posedge clk_s); guard = guard + 1;
        end
        check(selected_image_id == 8'd3, "mock real-media load reached image 3");
        check(!bridge_fault, "Slave bridge fault remains clear");
        check(!m_led[3], "Master fault LED remains clear");

        wait_visible(3);
        repeat(10000) @(negedge clk_m);
        check(open_count==3,"paused carousel sends no extra OPEN");
        press(2);
        wait_visible(2);
        check(open_count==4,"PREV performs exactly one real load");
        press(1);
        wait_visible(3);
        check(open_count==5,"NEXT performs exactly one real load");
        if (errors == 0)
            $display("PASS: M2 integrated media control checks=%0d opens=%0d selected=%0d",
                     checks, open_count, selected_image_id);
        else
            $fatal(1, "FAIL: M2 Master real-control link errors=%0d checks=%0d", errors, checks);
        $finish;
    end
endmodule
