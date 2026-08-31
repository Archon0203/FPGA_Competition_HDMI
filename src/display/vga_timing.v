// ================================================================
// 模块   : vga_timing
// 功能   : 生成行同步(HS) / 场同步(VS) / 数据有效(DE) 及像素坐标。
//           用于通用的逐行(progressive)视频时序。
//           默认: 640x480 @60Hz (像素时钟 25.175 MHz)。
// 时序   : 行总 800 (有效640, 前肩16, 同步96, 后肩48)
//           场总 525 (有效480, 前肩10, 同步2,  后肩33)
// 作者   : 请输入文本队--张宗
// 日期   : 2026-08-26
// 说明   : 纯 RTL, 不使用厂商 IP。用 tb_vga_timing 仿真。
//           通过参数可覆盖各段大小, 以适配不同输出分辨率。
// ================================================================

module vga_timing #(
    parameter H_ACTIVE = 640,   // 每行有效像素数
    parameter H_FP     = 16,    // 行前肩
    parameter H_SYNC   = 96,    // 行同步宽度
    parameter H_BP     = 48,    // 行后肩
    parameter V_ACTIVE = 480,   // 每帧有效行数
    parameter V_FP     = 10,    // 场前肩
    parameter V_SYNC   = 2,     // 场同步宽度
    parameter V_BP     = 33,    // 场后肩
    parameter H_POL    = 1'b1,  // 行同步有效极性 (1 = 高有效)
    parameter V_POL    = 1'b1   // 场同步有效极性 (1 = 高有效)
)(
    input  wire        clk_pix,  // 像素时钟
    input  wire        rst_n,    // 异步复位, 低有效
    output wire        hs,       // 行同步
    output wire        vs,       // 场同步
    output wire        de,       // 数据有效(有效显示区)
    output wire [11:0] pixel_x,  // 0..H_ACTIVE-1
    output wire [11:0] pixel_y   // 0..V_ACTIVE-1
);

    localparam H_TOTAL = H_ACTIVE + H_FP + H_SYNC + H_BP;  // 每行总像素数
    localparam V_TOTAL = V_ACTIVE + V_FP + V_SYNC + V_BP;  // 每帧总行数

    reg [11:0] hcnt;   // 行计数器 (0..H_TOTAL-1)
    reg [11:0] vcnt;   // 场计数器 (0..V_TOTAL-1)

    // ---- 行计数器 ----
    always @(posedge clk_pix or negedge rst_n) begin
        if (!rst_n)                 hcnt <= 12'd0;
        else if (hcnt == H_TOTAL-1) hcnt <= 12'd0;
        else                        hcnt <= hcnt + 1'b1;
    end

    // ---- 场计数器 (每行末前进一行) ----
    always @(posedge clk_pix or negedge rst_n) begin
        if (!rst_n) vcnt <= 12'd0;
        else if (hcnt == H_TOTAL-1) begin
            if (vcnt == V_TOTAL-1) vcnt <= 12'd0;
            else                   vcnt <= vcnt + 1'b1;
        end
    end

    // ---- 同步脉冲 (位于总时段内的指定区间) ----
    wire hsync_pos = (hcnt >= H_ACTIVE+H_FP) && (hcnt < H_ACTIVE+H_FP+H_SYNC);
    wire vsync_pos = (vcnt >= V_ACTIVE+V_FP) && (vcnt < V_ACTIVE+V_FP+V_SYNC);
    assign hs = (H_POL) ? hsync_pos : ~hsync_pos;
    assign vs = (V_POL) ? vsync_pos : ~vsync_pos;

    // ---- 数据有效与像素坐标 ----
    assign de      = (hcnt < H_ACTIVE) && (vcnt < V_ACTIVE);
    assign pixel_x = de ? hcnt : 12'd0;
    assign pixel_y = de ? vcnt : 12'd0;

`ifndef SYNTHESIS
    // 仅供仿真观察, 综合时剔除
    initial begin
        $display("vga_timing: H_TOTAL=%0d V_TOTAL=%0d", H_TOTAL, V_TOTAL);
    end
`endif

endmodule
