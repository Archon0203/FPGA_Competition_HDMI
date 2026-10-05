# tools

运行/辅助脚本：
- ✅ `video_to_vseq.py`：默认生成 YUV444 `.vseq`（配 `vseq_yuv_unpack` 直连显示链）；也可生成 planar YUV420/RGB，并支持回读校验
- ✅ `make_sd_card.py`：生成最小 FAT32 SD 卡镜像（8.3 短名，BMP/SEQ 根目录项）
- ✅ `gen_font.py`：生成 OSD 8x16 字模 HEX（0..9、A..F）
- 资源占用/文档数据整理工具
- `run_m2_control_regression.py`：运行 M2 控制/连续加载的 14 项 Questa 单元与子链回归；运行 `python tools/run_m2_control_regression.py`，需 Questa 工具在 PATH。日志在 `sim_work/m2_control_regression/`，FAIL 文本也会导致脚本失败。

用 bundled Python 解释器运行（见 workspace dependencies）。

`build_m2_roles.py`：隔离构建 active Master/Slave，检查 TD 错误文本、final STA、BitGen 及源码哈希，产物位于 `sim_work/m2_master_output/`；使用 `--role master|slave|both` 选择角色。
