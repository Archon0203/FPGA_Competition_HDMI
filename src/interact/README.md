# src/interact
（✓=已完成并有 testbench）
- `key_filter.v` ✓：4 路按键消抖（防抖/边沿）。
- `sw_filter.v` ✓：4 路拨码滤波 + 电平变化事件。
- `menu_fsm.v` ✓：主控状态机（播放/暂停/上下一张/应急/转场/调参）。
- `seg_driver.v` ✓：8 位数码管扫描 + 译码。
- `dual_led.v` ✓：双色 LED 状态指示（常亮/慢/快闪/交替）。
- `beep.v` ✓：蜂鸣器提示/应急告警（音调 + 门控）。
