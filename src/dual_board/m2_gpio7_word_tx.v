// Eleven-wire M2 profile: seven data pins, one forwarded clock, two UART
// control pins and common ground. Each word uses a marker and five data beats.
// A packet credit must bound the receiver's storage; this PHY has no retry.
module m2_gpio7_word_tx (
    input wire clk,
    input wire rst_n,
    input wire in_valid,
    input wire [31:0] in_data,
    input wire in_last,
    output wire in_ready,
    output reg [6:0] link_data,
    output reg link_clk
);
    reg [31:0] word_q;
    reg last_q;
    reg [2:0] beat;
    reg [1:0] phase;
    assign in_ready = (phase == 0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            word_q <= 0;
            last_q <= 0;
            beat <= 0;
            phase <= 0;
            link_data <= 0;
            link_clk <= 0;
        end else case (phase)
            0: if (in_valid) begin
                word_q <= in_data;
                last_q <= in_last;
                beat <= 0;
                link_data <= 7'h7e;
                phase <= 1;
            end
            1: begin
                link_clk <= 1;
                phase <= 2;
            end
            2: begin
                link_clk <= 0;
                if (beat == 5) phase <= 0;
                else begin
                    beat <= beat + 1'b1;
                    case (beat)
                        0: link_data <= word_q[6:0];
                        1: link_data <= word_q[13:7];
                        2: link_data <= word_q[20:14];
                        3: link_data <= word_q[27:21];
                        4: link_data <= {2'b00,last_q,word_q[31:28]};
                        default: link_data <= 0;
                    endcase
                    phase <= 1;
                end
            end
            default: phase <= 0;
        endcase
    end
endmodule
