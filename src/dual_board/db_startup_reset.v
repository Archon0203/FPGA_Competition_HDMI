// Small power-on reset generator for the M1 validation design.
// The board KEY_1 input remains an active-low manual reset; this generator
// also holds the datapath in reset briefly after configuration so the display
// scanner and UART state are deterministic even when KEY_1 is not pressed.
module db_startup_reset #(
    parameter integer POR_CYCLES = 1000000
)(
    input  wire clk,
    input  wire ext_rst_n,
    output wire rst_n
);
    reg [20:0] count;
    reg        por_done;

    initial begin
        count   = 21'd0;
        por_done = (POR_CYCLES <= 1);
    end

    always @(posedge clk or negedge ext_rst_n) begin
        if (!ext_rst_n) begin
            count    <= 21'd0;
            por_done <= (POR_CYCLES <= 1);
        end else if (!por_done) begin
            if (count >= POR_CYCLES - 1) begin
                count    <= count;
                por_done <= 1'b1;
            end else begin
                count <= count + 1'b1;
            end
        end
    end

    assign rst_n = ext_rst_n & por_done;
endmodule
