// ================================================================
// 模块   : async_fifo
// 功能   : 参数化跨时钟域异步 FIFO（格雷码指针 CDC，双时钟）。
//           深度 = 2^ADDR_WIDTH。full/empty 由同步后的对侧指针判断。
// 作者   : FPGA 竞赛团队
// 日期   : 2026-08-27
// 版本   : v1.0
// 端口说明:
//   - 写域: wr_clk / wr_rst_n(低有效) / wr_en / din[DATA_WIDTH-1:0]
//     写域标志: full(高 = 已满, 禁止写入)
//   - 读域: rd_clk / rd_rst_n(低有效) / rd_en
//     读域标志: empty(高 = 已空, 禁止读出)
//   - 输出: dout[DATA_WIDTH-1:0] (组合读出, 随 rd_ptr 变化)
// 时钟域: 写数据在 wr_clk 域, 读数据在 rd_clk 域; 两域完全独立。
//         指针用二进制计数以避免"满/空"边界歧义, 跨域通信用格雷码 + 2 拍同步。
// 修改历史:
//   2026-08-27 v1.0 初版, 按文档11任务卡 T3 实现。
// ================================================================

module async_fifo #(
    parameter DATA_WIDTH = 8,           // 数据位宽
    parameter ADDR_WIDTH = 4            // 地址位宽, 深度 = 2^ADDR_WIDTH
)(
    input  wire                  wr_clk,
    input  wire                  wr_rst_n,
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] din,
    input  wire                  rd_clk,
    input  wire                  rd_rst_n,
    input  wire                  rd_en,
    output wire [DATA_WIDTH-1:0] dout,
    output wire                  full,
    output wire                  empty
);

    localparam PTR_W = ADDR_WIDTH + 1;              // 指针位宽(含一圈标记 MSB)
    localparam DEPTH = (1 << ADDR_WIDTH);           // FIFO 深度

    // ---------- 存储体 ----------
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // ---------- 二进制读写指针(PTR_W 位) ----------
    reg [PTR_W-1:0] wr_ptr;    // 下一个写入槽
    reg [PTR_W-1:0] rd_ptr;    // 下一个读出槽

    // ---------- 格雷码(用于跨时钟域) ----------
    wire [PTR_W-1:0] wr_gray = (wr_ptr >> 1) ^ wr_ptr;
    wire [PTR_W-1:0] rd_gray = (rd_ptr >> 1) ^ rd_ptr;

    // ---------- 跨时钟域同步(2 拍) ----------
    // 写指针 -> 读域
    reg [PTR_W-1:0] wr_gray_sync1, wr_gray_sync2;
    // 读指针 -> 写域
    reg [PTR_W-1:0] rd_gray_sync1, rd_gray_sync2;

    // ---------- 格雷码 -> 二进制 ----------
    function [PTR_W-1:0] gray2bin;
        input [PTR_W-1:0] g;
        reg   [PTR_W-1:0] b;
        integer i;
        begin
            b = g;
            for (i = 1; i < PTR_W; i = i + 1)
                b[PTR_W-1-i] = b[PTR_W-i] ^ g[PTR_W-1-i];
            gray2bin = b;
        end
    endfunction

    // 同步后的指针对端(各自域内为二进制)
    wire [PTR_W-1:0] wr_ptr_sync = gray2bin(wr_gray_sync2);  // 读域内: 同步写入指针
    wire [PTR_W-1:0] rd_ptr_sync = gray2bin(rd_gray_sync2);  // 写域内: 同步读出指针

    // ---------- 读写使能(已满/已空时禁止) ----------
    wire wr_inc = wr_en & ~full;
    wire rd_inc = rd_en & ~empty;

    // ---------- 空/满标志(二进制比较) ----------
    // 空: 读写指针完全相等(读域内用同步写入指针判断)
    assign empty = (rd_ptr == wr_ptr_sync);
    // 满: 写指针比读指针恰好领先一圈(低位相同, MSB 不同), 写域内用同步读出指针判断
    assign full  = (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr_sync[ADDR_WIDTH-1:0]) &&
                   (wr_ptr[ADDR_WIDTH]     != rd_ptr_sync[ADDR_WIDTH]);

    // ---------- 写指针 ----------
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n)                       wr_ptr <= {PTR_W{1'b0}};
        else if (wr_inc)                     wr_ptr <= wr_ptr + 1'b1;
    end

    // ---------- 读指针 ----------
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n)                       rd_ptr <= {PTR_W{1'b0}};
        else if (rd_inc)                     rd_ptr <= rd_ptr + 1'b1;
    end

    // ---------- 存储体写入 ----------
    always @(posedge wr_clk) begin
        if (wr_inc) mem[wr_ptr[ADDR_WIDTH-1:0]] <= din;
    end

    // ---------- 组合读出 ----------
    assign dout = mem[rd_ptr[ADDR_WIDTH-1:0]];

    // ---------- 读指针格雷码同步到写域 ----------
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            rd_gray_sync1 <= {PTR_W{1'b0}};
            rd_gray_sync2 <= {PTR_W{1'b0}};
        end else begin
            rd_gray_sync1 <= rd_gray;
            rd_gray_sync2 <= rd_gray_sync1;
        end
    end

    // ---------- 写指针格雷码同步到读域 ----------
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wr_gray_sync1 <= {PTR_W{1'b0}};
            wr_gray_sync2 <= {PTR_W{1'b0}};
        end else begin
            wr_gray_sync1 <= wr_gray;
            wr_gray_sync2 <= wr_gray_sync1;
        end
    end

endmodule
