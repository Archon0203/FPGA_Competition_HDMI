> **状态更新**：本文件是当时的 candidate release 记录。当前 P0-07 已 `[U]`，P0-08 已 `[C-sub]`，完整 P0-09 正在等待端到端回归。

# P0-07 / P0-08 Candidate Release

日期：2026-08-31

## 已确认状态同步

- P0-05 `line_buffer_pingpong`：`[U]`，CASE-GOLDEN+CASE0~CASE8 PASS（checks=2204）。
- P0-06 `line_prefetcher`：`[U]`，CASE0~CASE13 PASS（checks=2713）。
- 当前已记录 33 个 ModelSim testbench PASS。

## 本轮新增

### P0-07

```text
src/framebuf/sdram_arbiter.v
sim_tb/framebuf/tb_sdram_arbiter.v
sim_tb/framebuf/run_sdram_arbiter.do
docs/27_sdram_arbiter_interface.md
docs/28_sdram_arbiter_test_vectors.md
```

### P0-08

```text
sim_tb/framebuf/mock_sdram.v
sim_tb/framebuf/tb_framebuffer_mock_chain.v
sim_tb/framebuf/run_framebuffer_mock_chain.do
docs/29_mock_sdram_framebuffer_chain.md
docs/30_framebuffer_mock_chain_test_vectors.md
```

工程 TB 总数由 33 增至 35；新增两个尚未计入 PASS。

## TangDynasty `.al` 项目同步

`FPGA_Competition_HDMI.al` 已补入当前 P0 正式 RTL 源文件：

```text
src/storage/fat32_file_reader.v
src/storage/bmp_pixel_stream.v
src/framebuf/framebuffer_writer.v
src/framebuf/frame_buffer_manager.v
src/framebuf/line_buffer_pingpong.v
src/framebuf/line_prefetcher.v
src/framebuf/sdram_arbiter.v
```

`mock_sdram.v` 与所有 `tb_*.v` 是 simulation-only，**不加入 TD synthesis source list**。

当前 `.al` 的 `ADC_FILE/SDC_FILE` 仍保持未绑定：项目中的 constraints 还是占位模板，必须等官方 HX4S20C 工程/原理图核对后再由人工绑定，不能为了“项目完整”把占位约束加入正式 TD 工程。

TD 生成的 `*_rtl.db/*_gate.db/*_pr.db` 没有伪造更新；只有实际 TD synthesis/P&R 后才能刷新。

## Git

本 release 在压缩包内保留 `.git`；本轮代码/文档/`.al` 状态已提交到当前 `fix/fix-TD-project` 分支，可用 `git log -1 --oneline` 查看。未执行任何远端 push。

## ModelSim 回归入口

```powershell
cd sim_work
vsim -c -do ../sim_tb/framebuf/run_sdram_arbiter.do
vsim -c -do ../sim_tb/framebuf/run_framebuffer_mock_chain.do
```

P0-07 目标：`[U]`。  
P0-08 目标：framebuffer/mock-memory **sub-chain `[C]`**。

完整 media chain `[C]` 仍需后续 FAT32/BMP→framebuffer→display-order RGB 端到端测试。
