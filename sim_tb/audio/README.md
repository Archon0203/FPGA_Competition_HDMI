# sim_tb/audio
HDMI 音频 / 测试音的 testbench。对应 `src/audio`：

```
tb_tone_gen.v + run_tone_gen.do   # 已完成(DDS 方波/三角波)
tb_audio_visual.v + run_audio_visual.do   # 已完成(振幅包络柱状图)
tb_hdmi_audio_pack.v + run_hdmi_audio_pack.do   # 已完成(IEC60958 子帧打包/校验)
```

运行（在 `sim_work` 目录）：
```powershell
vsim -c -do ../sim_tb/audio/run_tone_gen.do
```
