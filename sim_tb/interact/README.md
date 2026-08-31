# sim_tb/interact
按键 / 拨码 / 状态机 / 数码管 / LED / 蜂鸣 的 testbench。对应 `src/interact`：

```
tb_key_filter.v + run_key_filter.do
tb_sw_filter.v  + run_sw_filter.do
tb_menu_fsm.v   + run_menu_fsm.do
tb_seg_driver.v + run_seg_driver.do
tb_dual_led.v   + run_dual_led.do
tb_beep.v       + run_beep.do
```

运行（在 `sim_work` 目录）：
```powershell
vsim -c -do ../sim_tb/interact/run_key_filter.do
```
