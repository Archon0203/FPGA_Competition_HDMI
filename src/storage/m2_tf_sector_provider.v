// Same-clock SD SPI sector provider for the M2 FAT32 service.
// A request stays asserted while bytes are consumed. Complete the physical
// read into sector RAM first, so an early FAT directory end cannot let the
// next request consume the tail of the previous physical sector.
module m2_tf_sector_provider #(
    parameter integer SPI_CLK_DIV = 4,
    parameter integer SPI_INIT_CLK_DIV = SPI_CLK_DIV,
    parameter integer SPI_MODE3 = 0,
    parameter integer BOOT_BYTES = 10
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sector_req,
    input  wire [31:0] sector_lba,
    input  wire        serve_enable,
    output wire        sector_ready,
    output wire        sector_idle,
    output wire        din_valid,
    output wire [7:0]  din,
    output reg         sector_error,
    output reg  [7:0]  sector_error_detail,
    output wire        sd_ncs,
    output wire        sd_sclk,
    output wire        sd_mosi,
    input  wire        sd_miso
);
    localparam [2:0] BOOT=0, BOOT_WAIT=1, IDLE=2, FETCH=3, SERVE=4, RELEASE=5;
    reg [2:0] state;
    reg [4:0] boot_count;
    reg spi_boot_start;
    wire spi_done;
    wire [7:0] spi_dout;
    wire reader_spi_start, reader_done, reader_ok, reader_valid, reader_init_done;
    wire [7:0] reader_fail_code;
    wire reader_cs_n;
    wire [7:0] reader_spi_din, reader_data;
    reg reader_start;
    reg reader_armed;
    reg [31:0] lba_q;
    reg [7:0] sector_ram [0:511];
    reg [9:0] fill_count;
    reg [8:0] serve_index;

    assign sd_ncs = (state != FETCH) || reader_cs_n;
    assign sector_idle = (state == IDLE);
    assign sector_ready = (state == SERVE);
    assign din_valid = (state == SERVE) && serve_enable;
    assign din = sector_ram[serve_index];

    // The official divider counts from zero: a half-cycle is clk_div+2 clocks.
    localparam integer RUN_DIV = (SPI_CLK_DIV > 1) ? SPI_CLK_DIV-2 : 0;
    localparam integer INIT_DIV = (SPI_INIT_CLK_DIV > 1) ? SPI_INIT_CLK_DIV-2 : 0;
    wire [15:0] official_clk_div = reader_init_done ? RUN_DIV : INIT_DIV;
    wire official_mosi;
    assign sd_mosi = sd_ncs ? 1'b1 : official_mosi;
    m2_official_spi_master u_spi (
        .sys_clk(clk), .rst(!rst_n),
        .CPOL(SPI_MODE3 != 0), .CPHA(SPI_MODE3 != 0),
        .nCS_ctrl(sd_ncs), .nCS(),
        .clk_div(official_clk_div),
        .wr_req((state == BOOT_WAIT) ? spi_boot_start : reader_spi_start),
        .data_in((state == BOOT_WAIT) ? 8'hff : reader_spi_din),
        .wr_ack(spi_done), .data_out(spi_dout),
        .MOSI(official_mosi), .DCLK(sd_sclk), .MISO(sd_miso));

    sd_reader u_reader (
        .clk(clk), .rst_n(rst_n), .start(reader_start), .block_addr(lba_q),
        .spi_start(reader_spi_start), .spi_din(reader_spi_din),
        .spi_done(spi_done), .spi_dout(spi_dout),
        .data_valid(reader_valid), .data_out(reader_data),
        .done(reader_done), .ok(reader_ok), .init_done(reader_init_done),
        .spi_cs_n(reader_cs_n), .fail_code(reader_fail_code));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= BOOT;
            boot_count <= 0;
            spi_boot_start <= 1'b0;
            reader_start <= 1'b0;
            reader_armed <= 1'b0;
            lba_q <= 0;
            fill_count <= 0;
            serve_index <= 0;
            sector_error <= 1'b0;
            sector_error_detail <= 8'h00;
        end else begin
            spi_boot_start <= 1'b0;
            reader_start <= 1'b0;
            case (state)
                BOOT: begin
                    spi_boot_start <= 1'b1;
                    state <= BOOT_WAIT;
                end
                BOOT_WAIT: if (spi_done) begin
                    if (boot_count == BOOT_BYTES-1) state <= IDLE;
                    else begin
                        boot_count <= boot_count + 1'b1;
                        state <= BOOT;
                    end
                end
                IDLE: if (sector_req) begin
                    lba_q <= sector_lba;
                    reader_start <= 1'b1;
                    reader_armed <= 1'b0;
                    fill_count <= 0;
                    sector_error <= 1'b0;
                    sector_error_detail <= 8'h00;
                    state <= FETCH;
                end
                FETCH: begin
                    if (!reader_done) reader_armed <= 1'b1;
                    if (reader_valid && fill_count < 10'd512) begin
                        sector_ram[fill_count[8:0]] <= reader_data;
                        fill_count <= fill_count + 1'b1;
                    end
                    if (reader_armed && reader_done) begin
                        if (reader_ok && fill_count == 10'd512 && sector_req) begin
                            serve_index <= 0;
                            state <= SERVE;
                        end else begin
                            sector_error <= 1'b1;
                            // Preserve sd_reader command-stage detail.  If the
                            // reader itself reported success but the provider
                            // did not capture exactly 512 bytes, use 0x48.
                            sector_error_detail <= !reader_ok ? 
                                                   ((reader_fail_code != 8'h00) ? reader_fail_code : 8'h4F) :
                                                   8'h48;
                            state <= RELEASE;
                        end
                    end
                end
                SERVE: begin
                    if (!sector_req || (serve_enable && serve_index == 9'd511))
                        state <= RELEASE;
                    else if (serve_enable) serve_index <= serve_index + 1'b1;
                end
                RELEASE: if (!sector_req) begin
                    sector_error <= 1'b0;
                    state <= IDLE;
                end
                default: state <= BOOT;
            endcase
        end
    end
endmodule
