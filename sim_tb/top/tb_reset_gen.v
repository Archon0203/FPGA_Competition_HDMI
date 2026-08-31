`timescale 1ns/1ps

// ================================================================
// Testbench : tb_reset_gen
// 验证: async 拉低立即 sync=0; 释放后保持 RST_CLKS 拍再变 1; 无提前释放。
// 结局: PASS / FAIL
// ================================================================

module tb_reset_gen;
    localparam RST_CLKS = 4;

    reg  clk = 1'b0;
    reg  async_rst_n = 1'b0;
    wire sync_rst_n;

    reset_gen #(.RST_CLKS(RST_CLKS)) u_dut (
        .clk(clk), .async_rst_n(async_rst_n), .sync_rst_n(sync_rst_n)
    );

    always #5 clk = ~clk;

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
                $display("ERROR: %s got=%0b exp=%0b", msg, val, exp);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        // 复位有效
        async_rst_n = 1'b0;
        #3;
        check(sync_rst_n, 0, "async low -> sync low");

        // 释放: 前 RST_CLKS 拍应保持 0
        async_rst_n = 1'b1;
        for (k = 0; k < RST_CLKS - 1; k = k + 1) begin
            @(posedge clk); #1;
            check(sync_rst_n, 0, "still low before release");
        end
        @(posedge clk); #1;
        check(sync_rst_n, 1, "released after RST_CLKS");

        // 释放后保持 1
        repeat(3) @(posedge clk);
        check(sync_rst_n, 1, "stays released");

        // 再次异步打断
        async_rst_n = 1'b0;
        #3;
        check(sync_rst_n, 0, "re-assert works");

        if (errors == 0)
            $display("PASS: reset_gen ok (checks=%0d)", checks);
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
