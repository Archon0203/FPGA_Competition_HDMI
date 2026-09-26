# sim_tb/app
应用场景业务的 testbench。对应 `src/app`：

```
tb_app_scenario.v + run_app_scenario.do   # 已完成(轮播/暂停/上下张/应急)
tb_media_command_controller.v + run_media_command_controller.do
                                            # I0 主板 media_cmd valid/ready、轮播与应急边界
```

运行（在 `sim_work` 目录）：
```powershell
vsim -c -do ../sim_tb/app/run_app_scenario.do
```
