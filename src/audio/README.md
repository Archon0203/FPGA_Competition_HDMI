# src/audio
- `tone_gen.v` ✅：测试音/背景音生成（DDS 相位累加，方波/三角波）。
- `audio_visual.v` ✅：音频可视化（振幅包络柱状图，攻击快/释放慢，柱高满幅映射，低资源）。
- `hdmi_audio_pack.v` ✅：L-PCM 的 IEC60958 子帧打包与偶校验（Data Island 注入另属官方参考）。
- `hdmi_audio.v`：HDMI 音频包（Data Island / L-PCM）生成与注入。
