`timescale 1ns/1ps

// ================================================================
// Testbench : tb_async_fifo
// 功能      : 验证异步 FIFO(格雷码 CDC)的:
//             1) 复位后 empty=1 / full=0
//             2) 写满 DEPTH 个后 full=1, 拒绝再写
//             3) 按序读出并比对(写入序列), 全部读出后 empty=1
//             4) 长序列并发读写的数据完整性
// 结局      : 输出 PASS / FAIL
// ================================================================

module tb_async_fifo;
    localparam DATA_WIDTH = 8;
    localparam ADDR_WIDTH = 4;
    localparam DEPTH      = 16;

    reg          wr_clk = 1'b0;
    reg          wr_rst_n = 1'b0;
    reg          wr_en = 1'b0;
    reg [DATA_WIDTH-1:0] din = 8'd0;
    reg          rd_clk = 1'b0;
    reg          rd_rst_n = 1'b0;
    reg          rd_en = 1'b0;
    wire [DATA_WIDTH-1:0] dout;
    wire         full;
    wire         empty;

    async_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_dut (
        .wr_clk  (wr_clk),
        .wr_rst_n(wr_rst_n),
        .wr_en   (wr_en),
        .din     (din),
        .rd_clk  (rd_clk),
        .rd_rst_n(rd_rst_n),
        .rd_en   (rd_en),
        .dout    (dout),
        .full    (full),
        .empty   (empty)
    );

    // 独立双时钟
    always #5.0  wr_clk = ~wr_clk;    // 10ns 周期
    always #6.5  rd_clk = ~rd_clk;    // 13ns 周期

    integer errors = 0;
    integer checks = 0;
    integer i, j, k;              // 模块级循环/暂存变量

    // 一次检查
    task check;
        input [31:0] val;
        input [31:0] exp;
        input [255:0] msg;
        begin
            checks = checks + 1;
            if (val !== exp) begin
                $display("ERROR: %s got=%0d expect=%0d", msg, val, exp);
                errors = errors + 1;
            end
        end
    endtask

    // 写一个字节(在写域)
    task wr_word;
        input [DATA_WIDTH-1:0] val;
        begin
            @(posedge wr_clk);
            wr_en = 1'b1;
            din   = val;
            @(posedge wr_clk);
            wr_en = 1'b0;
        end
    endtask

    // ---------- 读数据比对(在读域, 每拍有效时采样) ----------
    reg [DATA_WIDTH-1:0] exp_read = 8'd0;
    integer read_count = 0;
    wire rd_act = rd_en & ~empty;
    always @(posedge rd_clk) begin
        if (rd_act) begin
            if (dout !== exp_read) begin
                $display("ERROR: read mismatch @%0d got=%0d exp=%0d",
                         read_count, dout, exp_read);
                errors = errors + 1;
            end
            exp_read = exp_read + 1'b1;
            read_count = read_count + 1;
        end
    end

    // ---------- 主流程 ----------
    task reset_dut;
        begin
            wr_rst_n = 1'b0; rd_rst_n = 1'b0;
            wr_en = 1'b0; rd_en = 1'b0; din = 8'd0;
            repeat(3) @(posedge wr_clk);
            repeat(3) @(posedge rd_clk);
            wr_rst_n = 1'b1; rd_rst_n = 1'b1;
            repeat(2) @(posedge wr_clk);
            repeat(2) @(posedge rd_clk);
        end
    endtask

    // 等待 empty 变为 0, 最多 N 个读域周期
    task wait_not_empty;
        input integer n;
        begin
            k = 0;
            while (empty && k < n) begin
                @(posedge rd_clk);
                k = k + 1;
            end
        end
    endtask

    // 等待 empty 变为 1, 最多 N 个读域周期
    task wait_empty;
        input integer n;
        begin
            k = 0;
            while (!empty && k < n) begin
                @(posedge rd_clk);
                k = k + 1;
            end
        end
    endtask

    // ---------- 主流程 ----------
    initial begin
        // 复位
        reset_dut;

        // ---- 测试1: 复位状态 ----
        check(empty, 1, "reset empty");
        check(full,  0, "reset full");

        // ---- 测试2: 写满并验证 full ----
        for (i = 0; i < DEPTH; i = i + 1) wr_word(i[7:0]);
        @(posedge wr_clk);   // 等 wr_ptr 更新
        check(full, 1, "full after DEPTH writes");

        // ---- 测试3: 满时拒绝额外写入(不破坏已存数据) ----
        wr_en = 1'b1; din = 8'hAA;
        @(posedge wr_clk);
        wr_en = 1'b0;
        @(posedge wr_clk);
        check(full, 1, "full still 1 after rejected write");

        // ---- 测试4: 按序读出全部, 验证 empty=1 ----
        exp_read = 8'd0; read_count = 0;
        wait_not_empty(100);
        check((empty == 1'b0), 1, "empty deasserted before read");
        rd_en = 1'b1;
        repeat(DEPTH) @(posedge rd_clk);
        rd_en = 1'b0;
        wait_empty(100);
        check(empty, 1, "empty after full readout");
        check(read_count, DEPTH, "read DEPTH words");

        // ---- 测试5: 长序列并发读写(数据完整性) ----
        exp_read = 8'd0; read_count = 0;
        fork
            begin : wr_driver
                for (i = 0; i < 48; i = i + 1) begin
                    @(posedge wr_clk);
                    while (full) @(posedge wr_clk);
                    wr_en = 1'b1;
                    din   = i[7:0];
                    @(posedge wr_clk);
                    wr_en = 1'b0;
                end
            end
            begin : rd_driver
                for (j = 0; j < 48; j = j + 1) begin
                    @(posedge rd_clk);
                    while (empty) @(posedge rd_clk);
                    rd_en = 1'b1;
                    @(posedge rd_clk);
                    rd_en = 1'b0;
                end
            end
        join
        check(read_count, 48, "read 48 words in concurrency");

        // 结语
        if (errors == 0)
            $display("PASS: async_fifo ok (checks=%0d)", checks);
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end

endmodule
