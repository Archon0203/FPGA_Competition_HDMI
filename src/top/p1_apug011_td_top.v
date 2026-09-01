// ================================================================
// 模块   : p1_apug011_td_top
// 功能   : P1-02B TD-only synthesis/P&R integration harness。
//
// 该 top 不是 HX4S20C 最终 board top，不绑定任何板级 pin/IOSTANDARD。
// 它严格复用 APUG011 v1.2 官方参考 PLL：25 MHz refclk -> 150 MHz 0°/180°，
// 并连接 EG4S20 的 EG_PHY_SDRAM_2M_32 internal SDRAM primitive。
//
// 验证链：
//   p1_apug011_bist
//     -> sdram_arbiter
//     -> sdram_adapter
//     -> apug011_core_wrapper / official protected sdr_as_ram
//     -> EG_PHY_SDRAM_2M_32
//
// P1-02B 通过 TD synthesis/P&R/timing/resource 后，只证明 SDRAM backend
// 子系统的 vendor/primitive 集成；最终 50 MHz HX4S20C board PLL、真实 pin
// constraints 和 system_top/hx4s20c_top 仍在后续 P1-04 验证。
// ================================================================

module p1_apug011_td_top (
    input  wire       REF_CLK_25M,
    output wire       PLL_LOCK,
    output wire       SDRAM_INIT_DONE,
    output wire       PROBE_DONE,
    output wire       PROBE_PASS,
    output wire       PROBE_FAIL,
    output wire [3:0] PROBE_STATE
);

    wire clk_unused_12m5;
    wire clk_sdr_150m;
    wire clk_sdr_150m_shift;

    clk_pll u_apug011_ref_pll (
        .refclk  (REF_CLK_25M),
        .reset   (1'b0),
        .extlock (PLL_LOCK),
        .clk0_out(clk_unused_12m5),
        .clk1_out(clk_sdr_150m),
        .clk2_out(clk_sdr_150m_shift)
    );

    wire rst_n = PLL_LOCK;

    // BIST <-> arbiter
    wire        bist_wr_valid;
    wire [20:0] bist_wr_addr;
    wire [31:0] bist_wr_data;
    wire        bist_wr_ready;
    wire        bist_rd_valid;
    wire [20:0] bist_rd_addr;
    wire        bist_rd_ready;
    wire        bist_rd_rvalid;
    wire [31:0] bist_rd_rdata;

    // arbiter <-> adapter
    wire        mem_wr_valid;
    wire [20:0] mem_wr_addr;
    wire [31:0] mem_wr_data;
    wire        mem_wr_ready;
    wire        mem_rd_valid;
    wire [20:0] mem_rd_addr;
    wire        mem_rd_ready;
    wire        mem_rvalid;
    wire [31:0] mem_rdata;

    wire        arb_protocol_error;
    wire        arb_contention_seen;
    wire [15:0] arb_rd_outstanding;
    wire [31:0] arb_read_count;
    wire [31:0] arb_write_count;

    sdram_arbiter #(
        .MAX_READ_OUTSTANDING(4)
    ) u_arbiter (
        .clk                    (clk_sdr_150m),
        .rst_n                  (rst_n),
        .wr_valid               (bist_wr_valid),
        .wr_addr                (bist_wr_addr),
        .wr_data                (bist_wr_data),
        .wr_ready               (bist_wr_ready),
        .rd_valid               (bist_rd_valid),
        .rd_addr                (bist_rd_addr),
        .rd_ready               (bist_rd_ready),
        .rd_rvalid              (bist_rd_rvalid),
        .rd_rdata               (bist_rd_rdata),
        .mem_wr_valid           (mem_wr_valid),
        .mem_wr_addr            (mem_wr_addr),
        .mem_wr_data            (mem_wr_data),
        .mem_wr_ready           (mem_wr_ready),
        .mem_rd_valid           (mem_rd_valid),
        .mem_rd_addr            (mem_rd_addr),
        .mem_rd_ready           (mem_rd_ready),
        .mem_rvalid             (mem_rvalid),
        .mem_rdata              (mem_rdata),
        .protocol_error         (arb_protocol_error),
        .contention_seen        (arb_contention_seen),
        .rd_outstanding_debug   (arb_rd_outstanding),
        .read_accept_count_debug(arb_read_count),
        .write_accept_count_debug(arb_write_count)
    );

    // adapter <-> APUG011 application side
    wire        ready_for_traffic;
    wire        App_ref_req;
    wire        App_wr_en;
    wire [20:0] App_wr_addr;
    wire [3:0]  App_wr_dm;
    wire [31:0] App_wr_din;
    wire        App_rd_en;
    wire [20:0] App_rd_addr;
    wire        Sdr_rd_en;
    wire [31:0] Sdr_rd_dout;
    wire        Sdr_init_ref_vld;
    wire        Sdr_busy;

    wire        adapter_protocol_error;
    wire        provider_fault;
    wire        adapter_contention_seen;
    wire [15:0] adapter_outstanding;
    wire [31:0] adapter_read_accept_count;
    wire [31:0] adapter_write_accept_count;
    wire [31:0] adapter_app_read_word_count;
    wire [31:0] adapter_app_write_word_count;

    sdram_adapter u_adapter (
        .clk                    (clk_sdr_150m),
        .rst_n                  (rst_n),
        .mem_wr_valid           (mem_wr_valid),
        .mem_wr_addr            (mem_wr_addr),
        .mem_wr_data            (mem_wr_data),
        .mem_wr_ready           (mem_wr_ready),
        .mem_rd_valid           (mem_rd_valid),
        .mem_rd_addr            (mem_rd_addr),
        .mem_rd_ready           (mem_rd_ready),
        .mem_rvalid             (mem_rvalid),
        .mem_rdata              (mem_rdata),
        .Sdr_init_done          (SDRAM_INIT_DONE),
        .Sdr_init_ref_vld       (Sdr_init_ref_vld),
        .Sdr_busy               (Sdr_busy),
        .Sdr_rd_en              (Sdr_rd_en),
        .Sdr_rd_dout            (Sdr_rd_dout),
        .App_ref_req            (App_ref_req),
        .App_wr_en              (App_wr_en),
        .App_wr_addr            (App_wr_addr),
        .App_wr_dm              (App_wr_dm),
        .App_wr_din             (App_wr_din),
        .App_rd_en              (App_rd_en),
        .App_rd_addr            (App_rd_addr),
        .ready_for_traffic      (ready_for_traffic),
        .protocol_error         (adapter_protocol_error),
        .provider_fault         (provider_fault),
        .contention_seen        (adapter_contention_seen),
        .read_outstanding_debug (adapter_outstanding),
        .read_accept_count_debug(adapter_read_accept_count),
        .write_accept_count_debug(adapter_write_accept_count),
        .app_read_word_count_debug(adapter_app_read_word_count),
        .app_write_word_count_debug(adapter_app_write_word_count)
    );

    // Official APUG011 physical bus -> internal EG SDRAM primitive.
    wire        SDRAM_CLK;
    wire        SDR_RAS;
    wire        SDR_CAS;
    wire        SDR_WE;
    wire [1:0]  SDR_BA;
    wire [10:0] SDR_ADDR;
    wire [3:0]  SDR_DM;
    wire [31:0] SDR_DQ;

    apug011_core_wrapper u_apug011 (
        .Sdr_clk          (clk_sdr_150m),
        .Sdr_clk_sft      (clk_sdr_150m_shift),
        .rst_n            (rst_n),
        .Sdr_init_done    (SDRAM_INIT_DONE),
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

    EG_PHY_SDRAM_2M_32 u_internal_sdram (
        .clk  (SDRAM_CLK),
        .ras_n(SDR_RAS),
        .cas_n(SDR_CAS),
        .we_n (SDR_WE),
        .addr (SDR_ADDR),
        .ba   (SDR_BA),
        .dq   (SDR_DQ),
        .cs_n (1'b0),
        .dm0  (SDR_DM[0]),
        .dm1  (SDR_DM[1]),
        .dm2  (SDR_DM[2]),
        .dm3  (SDR_DM[3]),
        .cke  (1'b1)
    );

    p1_apug011_bist u_bist (
        .clk                   (clk_sdr_150m),
        .rst_n                 (rst_n),
        .backend_ready         (ready_for_traffic),
        .wr_valid              (bist_wr_valid),
        .wr_addr               (bist_wr_addr),
        .wr_data               (bist_wr_data),
        .wr_ready              (bist_wr_ready),
        .rd_valid              (bist_rd_valid),
        .rd_addr               (bist_rd_addr),
        .rd_ready              (bist_rd_ready),
        .rd_rvalid             (bist_rd_rvalid),
        .rd_rdata              (bist_rd_rdata),
        .arb_protocol_error    (arb_protocol_error),
        .adapter_protocol_error(adapter_protocol_error),
        .provider_fault        (provider_fault),
        .done                  (PROBE_DONE),
        .pass                  (PROBE_PASS),
        .fail                  (PROBE_FAIL),
        .state_debug           (PROBE_STATE)
    );

endmodule
