# sim_tb/app
应用场景业务的 testbench。对应 `src/app`：

```
tb_app_scenario.v + run_app_scenario.do   # 已完成(轮播/暂停/上下张/应急)
```

运行（在 `sim_work` 目录）：
```powershell
vsim -c -do ../sim_tb/app/run_app_scenario.do
```
