// M1 master role: sends a small control frame every 125 ms and displays the
// most recent reply opcode plus transmitted-frame count.
module dual_board_master_top #(
    parameter integer UART_CLKS_PER_BIT = 434,
    parameter integer COMMAND_INTERVAL_CYCLES = 6250000,
    parameter integer POR_CYCLES = 1000000
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       uart_rx,
    output wire       uart_tx,
    output wire [7:0] seg_data,
    output wire [7:0] seg_sel
);
    localparam [7:0] OP_PING = 8'h01;
    localparam [7:0] OP_OPEN = 8'h02;
    localparam [7:0] OP_STATUS = 8'h03;
    localparam [7:0] OP_ABORT = 8'h04;
    wire rx_valid, rx_framing_error, rx_activity;
    wire [7:0] rx_data;
    wire frame_valid, frame_error;
    wire [7:0] rx_opcode;
    wire tx_ready, tx_start, tx_busy;
    wire [7:0] tx_data;
    wire core_rst_n;
    reg [22:0] tick;
    reg [1:0] command_index;
    reg request;
    reg [7:0] command;
    reg [7:0] last_reply;
    reg [7:0] reply_count;
    reg [7:0] tx_count;
    reg [7:0] error_count;
    reg [7:0] rx_activity_count;
    // E0: idle/no RX start detected, E2: RX activity but no valid reply yet,
    // E1: UART or protocol error, otherwise the last valid reply.
    wire [7:0] display_status = (error_count != 0) ? 8'he1 :
                                ((reply_count == 0 && rx_activity_count != 0) ? 8'he2 : last_reply);

    db_startup_reset #(.POR_CYCLES(POR_CYCLES)) u_por (
        .clk(clk), .ext_rst_n(rst_n), .rst_n(core_rst_n));

    db_uart_rx #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) u_rx (.clk(clk), .rst_n(core_rst_n), .rx(uart_rx), .valid(rx_valid),
        .data(rx_data), .framing_error(rx_framing_error), .rx_activity(rx_activity));
    db_frame_parser u_parser (.clk(clk), .rst_n(core_rst_n), .byte_valid(rx_valid),
        .byte_data(rx_data), .frame_valid(frame_valid), .opcode(rx_opcode),
        .frame_error(frame_error));
    db_frame_tx u_frame_tx (.clk(clk), .rst_n(core_rst_n), .request(request),
        .opcode(command), .uart_ready(tx_ready), .uart_start(tx_start),
        .uart_data(tx_data), .busy(tx_busy));
    db_uart_tx #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) u_tx (.clk(clk), .rst_n(core_rst_n), .start(tx_start), .data(tx_data),
        .ready(tx_ready), .tx(uart_tx));
    db_hex_display u_display (.clk(clk), .rst_n(core_rst_n), .status(display_status),
        .count(tx_count), .seg_data(seg_data), .seg_sel(seg_sel));

    always @(posedge clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            tick <= 23'd0;
            command_index <= 2'd0;
            request <= 1'b0;
            command <= OP_PING;
            last_reply <= 8'he0;
            reply_count <= 8'h00;
            tx_count <= 8'h00;
            error_count <= 8'h00;
            rx_activity_count <= 8'h00;
        end else begin
            request <= 1'b0;
            if (rx_activity)
                rx_activity_count <= rx_activity_count + 1'b1;
            if (frame_valid) begin
                last_reply <= rx_opcode;
                reply_count <= reply_count + 1'b1;
            end
            if (frame_error || rx_framing_error)
                error_count <= error_count + 1'b1;
            if (tick == COMMAND_INTERVAL_CYCLES-1) begin
                tick <= 23'd0;
                if (!tx_busy) begin
                    request <= 1'b1;
                    tx_count <= tx_count + 1'b1;
                    case (command_index)
                        2'd0: command <= OP_PING;
                        2'd1: command <= OP_OPEN;
                        2'd2: command <= OP_STATUS;
                        default: command <= OP_ABORT;
                    endcase
                    command_index <= command_index + 1'b1;
                end
            end else begin
                tick <= tick + 1'b1;
            end
        end
    end
endmodule
