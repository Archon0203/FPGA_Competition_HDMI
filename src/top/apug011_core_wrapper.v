// ================================================================
// 模块   : apug011_core_wrapper
// 功能   : P1-02A/P1-02B 官方 APUG011 `sdr_as_ram` 的项目侧薄封装。
//           - 不改变 APUG011 application-side 语义
//           - 把项目使用的低有效 rst_n 转换为官方高有效 Rst
//           - App_ref_req 由上游 sdram_adapter 直接传入
//           - 暴露 SDRAM 物理总线，便于 QuestaSim 连接官方 IS42s32200
//             行为模型；后续 hx4s20c_top 再连接 EG_PHY_SDRAM_2M_32
// 作者   : FPGA 竞赛团队
// 日期   : 2026-09-01
// 版本   : v0.3（P1-02A [C-sub]；P1-02B TD6.2 native protected-source integration）
// 时钟域 : Sdr_clk；Sdr_clk_sft 为同频相移时钟，具体相位由官方 PLL/TD 决定。
//
// 约束：
//   1) 本文件是项目 wrapper，不修改 src/vendor/anlogic/apug011 下官方源码。
//   2) P1-02A 已完成 official protected-core 仿真；P1-02B 在 TD 6.2.1
//      中严格镜像官方工程：global_def.v 设 GlobalIncluded=true，三个
//      protected .enc.v 作为独立 Verilog source；不再通过 `include 聚合。
//   3) 不在本层生成/猜测 PLL、引脚或 IOSTANDARD。
// ================================================================

module apug011_core_wrapper #(
    parameter integer SELF_REFRESH_OPEN = 1
) (
    input  wire         Sdr_clk,
    input  wire         Sdr_clk_sft,
    input  wire         rst_n,

    output wire         Sdr_init_done,
    output wire         Sdr_init_ref_vld,
    output wire         Sdr_busy,

    input  wire         App_ref_req,

    input  wire         App_wr_en,
    input  wire [20:0]  App_wr_addr,
    input  wire [3:0]   App_wr_dm,
    input  wire [31:0]  App_wr_din,

    input  wire         App_rd_en,
    input  wire [20:0]  App_rd_addr,
    output wire         Sdr_rd_en,
    output wire [31:0]  Sdr_rd_dout,

    output wire         SDRAM_CLK,
    output wire         SDR_RAS,
    output wire         SDR_CAS,
    output wire         SDR_WE,
    output wire [1:0]   SDR_BA,
    output wire [10:0]  SDR_ADDR,
    output wire [3:0]   SDR_DM,
    inout  wire [31:0]  SDR_DQ
);

    wire Rst = ~rst_n;

    sdr_as_ram #(
        .self_refresh_open(SELF_REFRESH_OPEN)
    ) u_sdr_as_ram (
        .Sdr_clk          (Sdr_clk),
        .Sdr_clk_sft      (Sdr_clk_sft),
        .Rst              (Rst),

        .Sdr_init_done    (Sdr_init_done),
        .Sdr_init_ref_vld (Sdr_init_ref_vld),
        .Sdr_busy         (Sdr_busy),

        .App_ref_req      (App_ref_req),

        .App_wr_en        (App_wr_en),
        .App_wr_addr      (App_wr_addr),
        .App_wr_dm        (App_wr_dm),
        .App_wr_din       (App_wr_din),

        .App_rd_en        (App_rd_en),
        .App_rd_addr      (App_rd_addr),
        .Sdr_rd_en        (Sdr_rd_en),
        .Sdr_rd_dout      (Sdr_rd_dout),

        .SDRAM_CLK        (SDRAM_CLK),
        .SDR_RAS          (SDR_RAS),
        .SDR_CAS          (SDR_CAS),
        .SDR_WE           (SDR_WE),
        .SDR_BA           (SDR_BA),
        .SDR_ADDR         (SDR_ADDR),
        .SDR_DM           (SDR_DM),
        .SDR_DQ           (SDR_DQ)
    );

endmodule
