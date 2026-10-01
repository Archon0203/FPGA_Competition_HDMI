// PRBS31 source used by the M1 data-contract self-test.
module m1b_prbs31 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    output wire [31:0] data
);
    reg [30:0] state;
    wire feedback = state[30] ^ state[27];
    assign data = {state, state[0]};
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= 31'h7fffffff;
        else if (enable)
            state <= {state[29:0], feedback};
    end
endmodule
