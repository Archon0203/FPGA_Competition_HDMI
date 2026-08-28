# tools

运行/辅助脚本：
- ✅ `video_to_vseq.py`：默认生成 YUV444 `.vseq`（配 `vseq_yuv_unpack` 直连显示链）；也可生成 planar YUV420/RGB，并支持回读校验
- ✅ `make_sd_card.py`：生成最小 FAT32 SD 卡镜像（8.3 短名，BMP/SEQ 根目录项）
- ✅ `gen_font.py`：生成 OSD 8x16 字模 HEX（0..9、A..F）
- 资源占用/文档数据整理工具

用 bundled Python 解释器运行（见 workspace dependencies）。
