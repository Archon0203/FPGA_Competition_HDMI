# sim_tb/top
顶层模块、时钟、复位的 testbench。对应 `src/top`：

```
tb_reset_gen.v + run_reset_gen.do   # 已完成(RST_CLKS 延迟同步释放)
```

运行（在 `sim_work` 目录）：
```powershell
vsim -c -do ../sim_tb/top/run_reset_gen.do
```
