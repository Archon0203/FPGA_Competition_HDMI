// ================================================================
// 模块   : menu_fsm
// 功能   : 主控交互状态机。接收消抖后的按键事件与拨码电平, 输出控制:
//           KEY0=播放/暂停, KEY1=下一张, KEY2=上一张, KEY3=应急切换;
//           SW[1:0]=转场模式, SW[2]=亮度档, SW[3]=对比度档。
// 作者   : FPGA 竞赛团队
// 日期   : 2026-08-27
// 版本   : v1.0
// 端口说明:
//   - clk / rst_n(低有效) : 系统时钟与复位
//   - key_event[3:0]      : 按键按下事件(单拍, 来自 key_filter)
//   - sw[3:0]             : 消抖后的拨码电平(来自 sw_filter)
//   - play_en             : 1=播放 0=暂停(KEY0 翻转)
//   - cmd_next/cmd_prev   : 上/下一张命令(单拍)
//   - emergency           : 1=应急模式(KEY3 翻转)
//   - transition_mode[1:0]: 转场模式(0=无 1=淡入 2=擦拭)
//   - contrast[7:0]/bias[7:0] : 对比度(gain/64)与亮度偏置
//   - osd_en              : OSD 使能(默认开)
// 时钟域: clk 为系统时钟域(clk_sys)。
// 修改历史:
//   2026-08-27 v1.0 初版, 按文档11任务卡 T19 实现。
// ================================================================

module menu_fsm (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [3:0]  key_event,
    input  wire [3:0]  sw,
    output reg         play_en,
    output reg         cmd_next,
    output reg         cmd_prev,
    output reg         emergency,
    output reg  [1:0]  transition_mode,
    output reg  [7:0]  contrast,
    output reg  [7:0]  bias,
    output reg         osd_en
);

    // 上/下一张命令: key_event 已是单拍, 再寄存一拍作为命令脉冲
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            play_en  <= 1'b1;
            cmd_next <= 1'b0;
            cmd_prev <= 1'b0;
            emergency<= 1'b0;
            transition_mode <= 2'd0;
            contrast <= 8'd64;
            bias     <= 8'sd0;
            osd_en   <= 1'b1;
        end else begin
            cmd_next <= key_event[1];   // 单拍
            cmd_prev <= key_event[2];   // 单拍
            if (key_event[0]) play_en <= ~play_en;
            if (key_event[3]) emergency <= ~emergency;

            // 拨码实时映射(档位)
            transition_mode <= sw[1:0];
            contrast <= sw[3] ? 8'd128 : 8'd64;
            bias     <= sw[2] ? 8'sd32 : 8'sd0;
        end
    end

endmodule
