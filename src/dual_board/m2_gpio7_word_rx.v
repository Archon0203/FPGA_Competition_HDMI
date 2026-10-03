// Source-clocked capture. The complete word crosses into sys_clk through the
// existing Gray-pointer FIFO. The upstream credit protocol prevents overflow.
module m2_gpio7_word_rx #(
    parameter integer FIFO_ADDR_WIDTH = 4
)(
    input wire link_clk,
    input wire [6:0] link_data,
    input wire link_rst_n,
    input wire sys_clk,
    input wire sys_rst_n,
    output wire out_valid,
    output wire [31:0] out_data,
    output wire out_last,
    input wire out_ready,
    output reg overflow_sticky
);
    reg [2:0] beat;
    reg [27:0] lower;
    wire [32:0] fifo_din = {link_data[4],link_data[3:0],lower};
    wire fifo_wr = (beat == 5);
    wire [32:0] fifo_dout;
    wire full, empty;

    async_fifo #(.DATA_WIDTH(33), .ADDR_WIDTH(FIFO_ADDR_WIDTH)) u_fifo (
        .wr_clk(link_clk), .wr_rst_n(link_rst_n),
        .wr_en(fifo_wr), .din(fifo_din), .full(full),
        .rd_clk(sys_clk), .rd_rst_n(sys_rst_n),
        .rd_en(out_valid && out_ready), .dout(fifo_dout), .empty(empty));
    assign out_valid = !empty;
    assign {out_last,out_data} = fifo_dout;

    always @(posedge link_clk or negedge link_rst_n) begin
        if (!link_rst_n) begin
            beat <= 0;
            lower <= 0;
            overflow_sticky <= 0;
        end else begin
            if (fifo_wr && full) overflow_sticky <= 1;
            case (beat)
                0: if (link_data == 7'h7e) beat <= 1;
                1: begin lower[6:0] <= link_data; beat <= 2; end
                2: begin lower[13:7] <= link_data; beat <= 3; end
                3: begin lower[20:14] <= link_data; beat <= 4; end
                4: begin lower[27:21] <= link_data; beat <= 5; end
                5: begin
                    beat <= 0;
                end
                default: beat <= 0;
            endcase
        end
    end
endmodule
