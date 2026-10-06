`timescale 1ns/1ps
module tb_m2_master_cached_control;
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
    wire qv, qr, reply_ready;
    wire [7:0] query;
    reg rv=0,rh=0;
    reg [3:0] cached=4'b0001;
    integer queries=0,opens=0,locals=0,query_delay=0,load_delay=0;
    reg [7:0] load_id=0;
    wire [3:0] m_led;
    wire master_catalog_valid, master_card_missing, master_link_ok, master_fault;
    wire [7:0] master_catalog_count, master_selected_image;

    m2_master_media_control #(
        .ENABLE_LOCAL_CACHE(1), .UART_CLKS_PER_BIT(16),
        .POR_CYCLES(8),
        .SLIDE_PERIOD_CLKS(3000),
        .DISCOVERY_INTERVAL_CYCLES(100),
        .ACK_TIMEOUT_CYCLES(5000),
        .STATUS_POLL_INTERVAL_CYCLES(100), .KEY_FILTER_CYCLES(4)
    ) u_master (
        .clk(clk_m), .rst_n(rst_m_n), .uart_rx(s_tx), .uart_tx(m_tx),
        .key_next_n(key_next_n), .key_prev_n(key_prev_n),
        .key_play_n(key_play_n), .led(m_led),
        .cache_query_valid(qv), .cache_query_id(query), .cache_query_ready(1'b1),
        .cache_reply_valid(rv), .cache_reply_hit(rh), .cache_reply_ready(reply_ready),
        .catalog_valid(master_catalog_valid), .catalog_count(master_catalog_count),
        .selected_image_id(master_selected_image), .link_ok(master_link_ok),
        .fault(master_fault), .card_missing(master_card_missing)
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
    wire open_prefetch;
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
        .open_prefetch(open_prefetch),
        .link_seen(link_seen), .fault(bridge_fault),
        .command_toggle(command_toggle), .reply_toggle(reply_toggle));

    always @(posedge clk_m) if(rst_m_n) begin
        if(u_master.local_commit) locals=locals+1;
        if(rv && reply_ready)rv<=0;
        if(qv) begin
            if(query_delay || rv)$fatal(1,"overlapping cache queries");
            queries=queries+1;query_delay=40;rh<=cached[query];
        end else if(query_delay) begin
            query_delay=query_delay-1;
            if(query_delay==0)rv<=1;
        end
    end
    always @(posedge clk_s) if(rst_s_n) begin
        source_done<=0;
        if(open_request) begin
            if(source_busy)$fatal(1,"OPEN before previous media done");
            opens=opens+1;load_id<=open_image_id;
            source_busy<=1;source_valid<=0;load_delay=12000;
        end else if(load_delay) begin
            load_delay=load_delay-1;
            if(load_delay==0) begin
                selected_image_id<=load_id;source_busy<=0;source_valid<=1;source_done<=1;
                cached[load_id]<=1;
            end
        end
    end
    task press;
        input integer key;
        begin
            @(negedge clk_m);
            case(key)0:key_play_n=0;1:key_next_n=0;2:key_prev_n=0;endcase
            repeat(32)@(negedge clk_m);
            key_play_n=1;key_next_n=1;key_prev_n=1;
            repeat(32)@(negedge clk_m);
        end
    endtask
    initial begin
        repeat(5)@(negedge clk_m);rst_m_n=1;rst_s_n=1;
        wait(locals==1);press(0); // pause auto after cached bootstrap
        if(opens!=0)$fatal(1,"cached bootstrap sent OPEN");
        press(1);wait(opens==1);wait(u_master.media_cmd_ready && !source_busy);
        if(selected_image_id!=1)$fatal(1,"first miss not displayed");
        press(2);wait(locals==2); // local image 0, Slave still owns image 1
        @(negedge clk_m);cached[1]=0; // eviction; following miss must force OPEN 1
        press(1);wait(opens==2);wait(u_master.media_cmd_ready && !source_busy);
        if(selected_image_id!=1)$fatal(1,"same-Slave-id miss was skipped after local switch");
        press(0);wait(opens==4);wait(u_master.media_cmd_ready && !source_busy);
        wait(queries>=12);
        repeat(4000)@(negedge clk_m);
        // Background prefetches are real OPEN transactions, so the OPEN count
        // is no longer fixed at the pre-prefetch value.  The carousel must,
        // however, accumulate local cache commits and remain bounded instead
        // of issuing one remote OPEN for every timer tick.
        if(locals<6 || opens>12) begin
            $display("DEBUG opens=%0d locals=%0d queries=%0d selected=%0d cached=%b ready=%b", opens, locals, queries, selected_image_id, cached, u_master.media_cmd_ready);
            $fatal(1,"automatic carousel did not use cache/prefetch correctly");
        end
        $display("PASS: Master cached manual/automatic carousel with background prefetch, metadata-query gate, stale Slave DONE avoided opens=%0d hits=%0d queries=%0d",opens,locals,queries);$finish;
    end
    initial begin #20000000;$fatal(1,"cached Master watchdog opens=%0d hits=%0d queries=%0d",opens,locals,queries);end
endmodule
