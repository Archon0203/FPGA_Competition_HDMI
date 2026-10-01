// Internal loopback diagnostic: connects the UART TX waveform directly to
// the UART RX sampler inside the FPGA. This isolates RTL/clock/reset from
// board headers and confirms the implemented design can parse its own frames.
module dual_board_internal_loop_top #(
    parameter integer UART_CLKS_PER_BIT = 434,
    parameter integer COMMAND_INTERVAL_CYCLES = 6250000,
    parameter integer POR_CYCLES = 1000000
)(
    input wire clk,
    input wire rst_n,
    input wire uart_rx,
    output wire uart_tx,
    output wire [7:0] seg_data,
    output wire [7:0] seg_sel
);
    wire [7:0] unused_seg;
    wire [7:0] loop_rx;
    wire loop_tx;
    dual_board_master_top #(
        .UART_CLKS_PER_BIT(UART_CLKS_PER_BIT),
        .COMMAND_INTERVAL_CYCLES(COMMAND_INTERVAL_CYCLES),
        .POR_CYCLES(POR_CYCLES)
    ) u_master (
        .clk(clk), .rst_n(rst_n), .uart_rx(loop_tx), .uart_tx(loop_tx),
        .seg_data(seg_data), .seg_sel(seg_sel)
    );
    assign uart_tx = loop_tx;
endmodule
