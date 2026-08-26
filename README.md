# 基于 EG4S20 的 HDMI 多媒体播放系统

> 2026 全国大学生嵌入式芯片与系统设计竞赛 · FPGA 创新设计赛道
> 赛道：安路科技 · 选题一《基于安路 EG4S20 的 HDMI 多媒体播放系统》
> 平台：安路 HX4S20C 开发板（主芯片 **EG4S20BG256**）
> 工具链：TangDynasty 4.6.x + ModelSim SE 10.6d + 安路下载器

## 一、一句话说明

本项目基于安路 EG4S20 FPGA 开发板（HX4S20C），设计并实现了一款 **HDMI 多媒体播放系统**，
利用 **FPGA 并行处理**优势，实现 **SD/TF 卡读取媒体内容 → FPGA 缓存 → 图像处理 → HDMI 编码 → 显示器输出** 的全流程硬件加速，
**全程不依赖外部处理器**。系统以「校园/园区**信息发布与应急广播终端**」为应用场景，支持图片轮播、短视频片段、
时间戳与滚动标语叠加、亮度/对比度实时调节、转场特效、音频输出与音频可视化，并可一键进入应急广播。

> 口径：说“**短视频片段 / 图片 / 动画**”，不说“压缩视频解码 / MP4 播放”。详见 `docs/06` 与 `docs/08`。

## 二、项目结构

```
FPGA_Competition_HDMI/
├─ FPGA_Competition_HDMI.al    # TangDynasty 工程文件（TD 4.6.96021）
├─ README.md / STRUCTURE.md    # 项目说明 / 目录规范
├─ src/                        # ★ 设计代码（可综合 RTL，按子系统分目录）
│  ├─ top/       # top / clk_gen / reset_gen
│  ├─ storage/   # sd_spi / sd_reader / fat32_scan / bmp_parser / vseq_reader
│  ├─ framebuf/  # sdram_ctrl / frame_buffer / async_fifo
│  ├─ display/   # vga_timing / color_space / image_scaler / image_enhance / transition / osd_overlay / tmds_encoder
│  ├─ audio/     # hdmi_audio / tone_gen
│  ├─ interact/  # key_filter / sw_filter / menu_fsm / seg_driver / dual_led / beep
│  └─ app/       # app_scenario（信息发布与应急广播业务）
├─ sim/                        # ★ 仿真代码（tb_*.v + 仿真脚本 .do）
├─ sim_tb/                     # ★ ModelSim 运行产物（work/波形/日志，gitignore）
├─ constraints/                # ★ 管脚(.cst) + 时钟/时序(.sdc)约束（**须与官方板卡资料核对**）
├─ tools/                      # 工具脚本（BMP生成 / 视频转帧 / 字库 / SD卡制作）
├─ docs/                       # 设计文档（01~09：需求/架构/计划/风险/验证/视频/场景/卖点/实现矩阵）
└─ data/                       # 测试用图片/视频帧/音频（默认不入库，可重新生成）
```

详细目录职责见 [STRUCTURE.md](STRUCTURE.md)。

## 三、快速开始

1. **装备**：TD 4.6.x + ModelSim 10.6d + 下载器；拿到 HX4S20C 板卡。
2. **官方板卡资料**（百度网盘，提取码 `M5N1`）：
   <https://pan.baidu.com/s/1ysv_FmmgZKuM0rBiHfSv8w>
   重点拿：板卡手册、原理图、**引脚/管脚约束**、`lab_ex_4`/`lab_ex_5`、SDRAM 与 HDMI 参考。
3. **先跑通官方 `lab_ex_5`**（640×480 24 位 BMP → SDRAM → HDMI_B 显示 + 切图/轮播 + 音频测试音）。
4. **仿真首个模块**（本仓库已含 `vga_timing` RTL+TB）：
   ```
   cd sim_tb
   vsim -c -do ../sim/run_vga_timing.do          # 编译+跑
   vsim -c -novopt -wlf wave_vga_timing.wlf tb_vga_timing -do ../sim/run_vga_timing_wave.do   # 记录波形
   ```

## 四、团队协作（fork / clone / PR）

本仓库为**公开仓库**，队员通过以下流程协作、由管理员审核：
1. **Fork** 到自己的 GitHub 账号；
2. `git clone <你的fork地址>`；
3. 新建分支 `git checkout -b feat/xxx`；
4. 修改后 `git add -A && git commit -m "feat: ..."`，`git push origin feat/xxx`；
5. 在 GitHub 上对**原仓库**（本仓库）发起 **Pull Request**；
6. 管理员 review 后 `Squash and merge`。

> 建议：提交前先 `git fetch upstream` 同步主分支，避免冲突。

## 五、目标

- 完成**基础四项**（核心功能完整性 / 显示稳定性与鲁棒性 / 基础音频输出 / 系统工程规范性）。
- 完成 **2–3 项高性价比扩展**（OSD 字幕 / 转场 / 自适应缩放 / 参数调节 + OSD / 音频可视化）。
- 目标奖项：**全国三等奖保底，冲二等奖**。
- 相关评审口径见 `docs/01` 与对外叙事见 `docs/08`。
