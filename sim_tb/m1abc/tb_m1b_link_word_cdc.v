`timescale 1ns/1ps
module tb_m1b_link_word_cdc;
    reg link_clk = 1'b0;
    reg sys_clk = 1'b0;
    reg link_rst_n = 1'b0;
    reg sys_rst_n = 1'b0;
    reg link_valid = 1'b0;
    reg [31:0] link_data = 32'd0;
    reg link_sof = 1'b0, link_eol = 1'b0, link_eof = 1'b0;
    wire link_ready, overflow_sticky;
    wire sys_valid;
    wire [31:0] sys_data;
    wire sys_sof, sys_eol, sys_eof;
    reg sys_ready = 1'b1;

    always #6.734 link_clk = ~link_clk;
    always #10.013 sys_clk = ~sys_clk;

    m1b_link_word_cdc #(.ADDR_WIDTH(4)) dut (
        .link_clk(link_clk), .link_rst_n(link_rst_n), .link_valid(link_valid),
        .link_data(link_data), .link_sof(link_sof), .link_eol(link_eol), .link_eof(link_eof),
        .link_ready(link_ready), .overflow_sticky(overflow_sticky),
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n), .sys_valid(sys_valid),
        .sys_data(sys_data), .sys_sof(sys_sof), .sys_eol(sys_eol), .sys_eof(sys_eof),
        .sys_ready(sys_ready));

    integer sent = 0;
    integer recv = 0;
    integer errors = 0;
    integer guard = 0;

    always @(posedge link_clk) begin
        if (link_rst_n) begin
            if (sent < 64 && link_ready) begin
                link_valid <= 1'b1;
                link_data <= 32'hCAFE0000 + sent;
                link_sof <= (sent == 0);
                link_eol <= ((sent & 15) == 15);
                link_eof <= (sent == 63);
                sent <= sent + 1;
            end else begin
                link_valid <= 1'b0;
                link_sof <= 1'b0; link_eol <= 1'b0; link_eof <= 1'b0;
            end
        end
    end

    always @(posedge sys_clk) begin
        if (sys_rst_n && sys_valid && sys_ready) begin
            if (sys_data !== (32'hCAFE0000 + recv)) errors = errors + 1;
            if (sys_sof !== (recv == 0)) errors = errors + 1;
            if (sys_eol !== ((recv & 15) == 15)) errors = errors + 1;
            if (sys_eof !== (recv == 63)) errors = errors + 1;
            recv = recv + 1;
        end
    end

    initial begin
        repeat (6) @(posedge sys_clk);
        link_rst_n = 1'b1;
        sys_rst_n = 1'b1;
        while (recv < 64 && guard < 10000) begin
            @(posedge sys_clk);
            guard = guard + 1;
        end
        #1;
        if (recv != 64 || errors != 0 || overflow_sticky)
            $display("FAIL: M1B CDC recv=%0d errors=%0d overflow=%0d", recv, errors, overflow_sticky);
        else
            $display("PASS: M1B link-clock -> sys-clock FIFO CDC words=%0d", recv);
        $finish;
    end
endmodule
