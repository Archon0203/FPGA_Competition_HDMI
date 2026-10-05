// M2 bring-up transport: 7 bundled data bits + request/acknowledge toggles.
// Data settles BEFORE request changes and remains stable until acknowledged.
// Both sides synchronize only the toggles; this is NOT a high-speed video PHY.
// Reset both endpoints together to establish word alignment.
module m2_gpio_mailbox_tx(
    input wire clk, rst_n,
    input wire in_valid, input wire [31:0] in_data, output wire in_ready,
    output reg [6:0] data, output reg req, input wire ack);
    reg ack1, ack2;
    reg [31:0] word_q;
    reg [2:0] beat;
    reg [1:0] state;
    assign in_ready = state == 0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ack1<=0; ack2<=0; word_q<=0; beat<=0; state<=0; data<=0; req<=0;
        end else begin
            ack1<=ack; ack2<=ack1;
            case(state)
                0: if(in_valid) begin word_q<=in_data; data<=in_data[6:0]; beat<=0; state<=1; end
                1: begin req<=~req; state<=2; end
                2: if(ack2==req) begin
                    if(beat==4) state<=0;
                    else begin
                        word_q<={7'd0,word_q[31:7]};
                        data<=word_q[13:7]; beat<=beat+1'b1; state<=1;
                    end
                end
                default: state<=0;
            endcase
        end
    end
endmodule

module m2_gpio_mailbox_rx(
    input wire clk, rst_n,
    input wire [6:0] data, input wire req, output reg ack,
    output reg out_valid, output reg [31:0] out_data, input wire out_ready);
    reg req1, req2;
    reg [27:0] lower;
    reg [2:0] beat;
    reg settle;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            req1<=0; req2<=0; lower<=0; beat<=0; settle<=0;
            ack<=0; out_valid<=0; out_data<=0;
        end else begin
            req1<=req; req2<=req1;
            if(out_valid) begin
                if(out_ready) begin out_valid<=0; ack<=req2; beat<=0; end
            end else if(req2!=ack) begin
                // Additional destination cycle for bundled-data settling.
                if(!settle) settle<=1;
                else begin
                    settle<=0;
                    case(beat)
                        0: lower[6:0]<=data;
                        1: lower[13:7]<=data;
                        2: lower[20:14]<=data;
                        3: lower[27:21]<=data;
                        4: begin out_data<={data[3:0],lower}; out_valid<=1; end
                    endcase
                    if(beat!=4) begin beat<=beat+1'b1; ack<=req2; end
                end
            end
        end
    end
endmodule
