`timescale 1ns/1ps

// ================================================================
// Testbench : tb_sd_spi
// 用行为级 SPI 从机(MSB 先发)验证:
//   - 主机发送字节 din, 从机按位收齐(模式0)
//   - 主机从 miso 收齐从机字节, dout 正确
//   - 连续两次传输可复用
// 结局: PASS / FAIL
// ================================================================

module tb_sd_spi;
    localparam CLK_DIV = 2;

    reg        clk = 1'b0;
    reg        rst_n = 1'b0;
    reg        start = 1'b0;
    reg  [7:0] din = 8'd0;
    wire       busy, done;
    wire [7:0] dout;
    wire       mosi;
    reg        miso;
    wire       sclk;

    sd_spi #(.CLK_DIV(CLK_DIV)) u_dut (
        .clk(clk), .rst_n(rst_n), .start(start), .din(din),
        .busy(busy), .done(done), .dout(dout),
        .mosi(mosi), .sclk(sclk), .miso(miso)
    );

    always #5 clk = ~clk;

    // ---- 行为级 SPI 从机 ----
    reg  [7:0] slave_tx = 8'hA5;
    reg  [7:0] slave_rx = 8'h00;
    reg  [7:0] sr = 8'hA5;
    reg  [2:0] sbc = 3'd0;
    reg        slave_active = 1'b0;

    always @(posedge clk) begin
        if (start) begin
            sr <= slave_tx; sbc <= 3'd0; slave_active <= 1'b1;
            miso <= slave_tx[7];
        end
    end
    // 从机在 SCLK 上升沿采集 MOSI
    always @(posedge sclk) begin
        if (slave_active) slave_rx <= {slave_rx[6:0], mosi};
    end
    // 从机在 SCLK 下降沿送出下一位
    always @(negedge sclk) begin
        if (slave_active && sbc < 3'd7) begin
            miso <= sr[6];
            sr   <= {sr[6:0], 1'b0};
            sbc  <= sbc + 1'b1;
        end
    end

    integer errors = 0;
    integer checks = 0;
    integer k;

    task check;
        input [31:0] val;
        input [31:0] exp;
        input [255:0] msg;
        begin
            checks = checks + 1;
            if (val !== exp) begin
                $display("ERROR: %s got=%0h exp=%0h", msg, val, exp);
                errors = errors + 1;
            end
        end
    endtask

    task xfer;
        input [7:0] txbyte;
        input [7:0] rxbyte;
        begin
            @(posedge clk);
            din = txbyte; start = 1'b1;
            @(posedge clk);
            start = 1'b0;
            k = 0;
            while (!done && k < 1000) begin
                @(posedge clk);
                k = k + 1;
            end
            check(done, 1, "done asserted");
            #1;
            check(dout, rxbyte, "dout from slave");
            check(slave_rx, txbyte, "slave rx from master");
            @(posedge clk);
        end
    endtask

    initial begin
        rst_n = 1'b0; #20; rst_n = 1'b1; #10;

        slave_tx = 8'hA5;
        xfer(8'hAB, 8'hA5);
        slave_tx = 8'h3C;
        xfer(8'h55, 8'h3C);

        if (errors == 0)
            $display("PASS: sd_spi ok (checks=%0d)", checks);
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
