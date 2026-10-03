// Slave frame readback and line packet source. The caller must assert start
// only after the media writer and SDRAM backend have completed their write
// fence. One read is outstanding; rd_rvalid follows a previously accepted
// request and returns ordered 0x00RRGGBB words.
module m2_frame_packet_source #(
    parameter integer WIDTH = 640,
    parameter integer HEIGHT = 480,
    parameter integer CREDIT_TIMEOUT_CYCLES = 5_000_000,
    parameter integer READ_TIMEOUT_CYCLES = 5_000_000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire        frame_ready,
    input  wire [20:0] frame_base,
    input  wire [15:0] frame_id,
    input  wire [7:0]  image_id,
    input  wire [15:0] credit_add,
    output wire        source_ready,
    output wire        source_busy,
    output reg         source_done,
    output reg         source_error,
    output reg  [15:0] credit_level,
    output wire        mem_rd_valid,
    output wire [20:0] mem_rd_addr,
    input  wire        mem_rd_ready,
    input  wire        mem_rvalid,
    input  wire [31:0] mem_rdata,
    output wire        packet_valid,
    output wire [31:0] packet_data,
    output wire        packet_last,
    input  wire        packet_ready
);
    localparam [2:0] IDLE=0, WAIT_CREDIT=1, ISSUE=2, WAIT_DATA=3,
                     TX_START=4, TX_PAY=5, TX_DONE=6;
    reg [2:0] state;
    reg [20:0] base_q;
    reg [15:0] frame_q, line_q, fetch_q, transmit_q;
    reg [7:0] image_q;
    reg [31:0] line_ram [0:WIDTH-1];
    reg [31:0] timeout_q;
    wire payload_ready, tx_busy, tx_done;
    wire [7:0] sequence_unused;
    wire [16:0] credit_total = {1'b0, credit_level} + {1'b0, credit_add};
    wire [15:0] credit_sum = credit_total[16] ? 16'hffff : credit_total[15:0];
    wire spend_credit = (state == WAIT_CREDIT) && credit_sum != 0;

    assign source_ready = (state == IDLE);
    assign source_busy = (state != IDLE);
    assign mem_rd_valid = (state == ISSUE);
    assign mem_rd_addr = base_q + (line_q * WIDTH) + fetch_q;

    m2_line_packet_tx #(.PAYLOAD_WORDS(WIDTH)) u_packet (
        .clk(clk), .rst_n(rst_n), .line_start(state == TX_START),
        .frame_id(frame_q), .image_id(image_q), .line_index(line_q),
        .payload_valid(state == TX_PAY && transmit_q < WIDTH),
        .payload_data((transmit_q < WIDTH) ? line_ram[transmit_q] : 32'd0),
        .payload_ready(payload_ready), .out_valid(packet_valid),
        .out_data(packet_data), .out_last(packet_last),
        .out_ready(packet_ready), .busy(tx_busy),
        .packet_done(tx_done), .sequence(sequence_unused));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            base_q <= 0; frame_q <= 0; image_q <= 0;
            line_q <= 0; fetch_q <= 0; transmit_q <= 0;
            timeout_q <= 0; credit_level <= 0;
            source_done <= 0; source_error <= 0;
        end else begin
            source_done <= 0;
            credit_level <= spend_credit ? credit_sum - 1'b1 : credit_sum;
            case (state)
                IDLE: if (start) begin
                    source_error <= 0;
                    if (frame_ready && frame_base[1:0] == 0) begin
                        base_q <= frame_base;
                        frame_q <= frame_id;
                        image_q <= image_id;
                        line_q <= 0;
                        timeout_q <= 0;
                        state <= WAIT_CREDIT;
                    end else source_error <= 1;
                end
                WAIT_CREDIT: if (spend_credit) begin
                    fetch_q <= 0;
                    timeout_q <= 0;
                    state <= ISSUE;
                end else if (timeout_q == CREDIT_TIMEOUT_CYCLES-1) begin
                    source_error <= 1;
                    state <= IDLE;
                end else timeout_q <= timeout_q + 1'b1;
                ISSUE: if (mem_rd_ready) begin
                    timeout_q <= 0;
                    state <= WAIT_DATA;
                end else if (timeout_q == READ_TIMEOUT_CYCLES-1) begin
                    source_error <= 1;
                    state <= IDLE;
                end else timeout_q <= timeout_q + 1'b1;
                WAIT_DATA: if (mem_rvalid) begin
                    line_ram[fetch_q] <= mem_rdata;
                    timeout_q <= 0;
                    if (fetch_q == WIDTH-1) begin
                        transmit_q <= 0;
                        state <= TX_START;
                    end else begin
                        fetch_q <= fetch_q + 1'b1;
                        state <= ISSUE;
                    end
                end else if (timeout_q == READ_TIMEOUT_CYCLES-1) begin
                    source_error <= 1;
                    state <= IDLE;
                end else timeout_q <= timeout_q + 1'b1;
                TX_START: state <= TX_PAY;
                TX_PAY: if (payload_ready && transmit_q < WIDTH) begin
                    if (transmit_q == WIDTH-1) state <= TX_DONE;
                    transmit_q <= transmit_q + 1'b1;
                end
                TX_DONE: if (tx_done) begin
                    if (line_q == HEIGHT-1) begin
                        source_done <= 1;
                        state <= IDLE;
                    end else begin
                        line_q <= line_q + 1'b1;
                        timeout_q <= 0;
                        state <= WAIT_CREDIT;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
