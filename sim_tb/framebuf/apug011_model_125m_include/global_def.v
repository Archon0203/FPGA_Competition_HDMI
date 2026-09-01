// P1-02A simulation-only APUG011 global configuration.
// Derived from vendor global_def.v, but clock period is set to 125 MHz so the
// bundled IS42s32200 -7 behavioral model (tCK >= 7 ns, tRCD >= 21 ns) is used
// inside its declared timing envelope. Vendor source under src/vendor is not modified.

`define DATA_WIDTH 32
`define ADDR_WIDTH 21
`define DM_WIDTH   4
`define ROW_WIDTH  11
`define BA_WIDTH   2

`define SDR_CLK_PERIOD 1000000000/125000000
`define SELF_REFRESH_INTERVAL 64000000/`SDR_CLK_PERIOD/2**(`ROW_WIDTH)
