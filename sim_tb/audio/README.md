# sim_tb/audio
HDMI 音频 / 测试音的 testbench。对应 `src/audio`：

```
tb_tone_gen.v + run_tone_gen.do   # 已完成(DDS 方波/三角波)
```

运行（在 `sim_work` 目录）：
```powershell
vsim -c -do ../sim_tb/audio/run_tone_gen.do
```
