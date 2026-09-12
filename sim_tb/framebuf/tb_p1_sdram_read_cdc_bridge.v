`timescale 1ns/1ps

module tb_p1_sdram_read_cdc_bridge;
    reg pix_clk = 1'b0;
    reg sdr_clk = 1'b0;
    reg pix_rst_n = 1'b0;
    reg sdr_rst_n = 1'b0;

    reg         pix_rd_valid = 1'b0;
    reg  [20:0] pix_rd_addr  = 21'd0;
    wire        pix_rd_ready;
    wire        pix_rvalid;
    wire [31:0] pix_rdata;

    wire        sdr_rd_valid;
    wire [20:0] sdr_rd_addr;
    reg         sdr_rd_ready = 1'b1;
    reg         sdr_rvalid = 1'b0;
    reg  [31:0] sdr_rdata  = 32'd0;
    wire        protocol_error;

    integer sent = 0;
    integer received = 0;
    integer checks = 0;
    reg pending_valid = 1'b0;
    reg [20:0] pending_addr = 21'd0;

    always #20 pix_clk = ~pix_clk; // 25 MHz
    always #3.333 sdr_clk = ~sdr_clk; // ~150 MHz

    p1_sdram_read_cdc_bridge dut (
        .pix_clk(pix_clk), .pix_rst_n(pix_rst_n),
        .pix_mem_rd_valid(pix_rd_valid), .pix_mem_rd_addr(pix_rd_addr),
        .pix_mem_rd_ready(pix_rd_ready), .pix_mem_rvalid(pix_rvalid),
        .pix_mem_rdata(pix_rdata),
        .sdr_clk(sdr_clk), .sdr_rst_n(sdr_rst_n),
        .sdr_mem_rd_valid(sdr_rd_valid), .sdr_mem_rd_addr(sdr_rd_addr),
        .sdr_mem_rd_ready(sdr_rd_ready), .sdr_mem_rvalid(sdr_rvalid),
        .sdr_mem_rdata(sdr_rdata), .protocol_error(protocol_error)
    );

    // One-cycle ordered SDR response model.
    always @(posedge sdr_clk) begin
        if (!sdr_rst_n) begin
            pending_valid <= 1'b0;
            pending_addr  <= 21'd0;
            sdr_rvalid    <= 1'b0;
            sdr_rdata     <= 32'd0;
        end else begin
            sdr_rvalid <= pending_valid;
            if (pending_valid)
                sdr_rdata <= 32'hA5000000 | pending_addr;

            pending_valid <= sdr_rd_valid && sdr_rd_ready;
            if (sdr_rd_valid && sdr_rd_ready)
                pending_addr <= sdr_rd_addr;
        end
    end

    always @(posedge pix_clk) begin
        if (pix_rst_n && pix_rd_valid && pix_rd_ready) begin
            sent = sent + 1;
            pix_rd_addr <= pix_rd_addr + 21'd1;
            if (sent == 12)
                pix_rd_valid <= 1'b0;
        end

        if (pix_rst_n && pix_rvalid) begin
            if (pix_rdata !== (32'hA5000000 | (21'd100 + received))) begin
                $display("FAIL: response %0d got=%h", received, pix_rdata);
                $finish;
            end
            received = received + 1;
            checks = checks + 1;
        end
    end

    initial begin
        repeat (4) @(posedge pix_clk);
        pix_rst_n <= 1'b1;
        sdr_rst_n <= 1'b1;
        @(posedge pix_clk);
        pix_rd_addr  <= 21'd100;
        pix_rd_valid <= 1'b1;

        wait (received == 12);
        repeat (5) @(posedge pix_clk);

        if (protocol_error) begin
            $display("FAIL: protocol_error set");
            $finish;
        end
        checks = checks + 1;

        $display("PASS: p1_sdram_read_cdc_bridge passed (checks=%0d)", checks);
        $finish;
    end

    initial begin
        #200000;
        $display("FAIL: timeout sent=%0d received=%0d", sent, received);
        $finish;
    end
endmodule
