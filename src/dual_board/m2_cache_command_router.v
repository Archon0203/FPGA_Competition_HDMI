// Serialize both manual and carousel commands through a display-cache query.
// A hit replies only after pixels AND metadata commit. A miss is forwarded to
// the unchanged UART OPEN/DONE transaction. No stale Slave DONE can complete a
// local operation or skip a subsequent cache miss.
module m2_cache_command_router(
    input wire clk, rst_n,
    input wire cmd_valid, input wire [7:0] cmd_id, input wire [1:0] cmd_mode,
    output wire cmd_ready,
    output wire query_valid, output wire [7:0] query_id, input wire query_ready,
    input wire reply_valid, reply_hit, output wire reply_ready,
    output wire remote_valid, output wire [7:0] remote_id,
    output wire [1:0] remote_mode, input wire remote_ready,
    output reg local_commit
);
    localparam IDLE=0, QUERY=1, REPLY=2, OPEN=3, DONE=4;
    reg [2:0] state;
    reg [7:0] image;
    reg [1:0] mode;
    assign cmd_ready=(state==IDLE) && remote_ready;
    assign query_valid=(state==QUERY);
    assign query_id=image;
    assign reply_ready=(state==REPLY);
    assign remote_valid=(state==OPEN);
    assign remote_id=image;
    assign remote_mode=mode;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin state<=IDLE; image<=0; mode<=0; local_commit<=0; end
        else begin
            local_commit<=0;
            case(state)
                IDLE: if(cmd_valid && cmd_ready) begin
                    image<=cmd_id; mode<=cmd_mode;
                    // Query even speculative fills: if the image already has
                    // a valid bank, no second SD read or remote transfer is
                    // needed. A prefetch hit must not alter displayed state.
                    state <= QUERY;
                end
                QUERY: if(query_ready) state<=REPLY;
                REPLY: if(reply_valid) begin
                    if(reply_hit) begin
                        state<=IDLE;
                        local_commit<=(mode==2'd1) ? 1'b0 : 1'b1;
                    end
                    else state<=OPEN;
                end
                OPEN: if(remote_ready) state<=DONE;
                DONE: if(remote_ready) state<=IDLE;
                default: state<=IDLE;
            endcase
        end
    end
endmodule
