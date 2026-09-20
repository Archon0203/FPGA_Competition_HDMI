# P1-05B `p1_media_framebuffer_loader` 接口与边界

> 状态：`[U] PASS`（ModelSim 10.6d，2026-09-20，checks=225）；下一步才是 board top 集成。本文是开发记录，不替代 `docs/03_plan_and_status.md` 的状态权威。

## 职责

`p1_media_framebuffer_loader` 是 P1-05B 写入侧的第一个集成模块：

```text
FAT32 文件 metadata + sector provider
    -> fat32_file_reader
    -> bmp_parser / bmp_pixel_stream
    -> framebuffer_writer
    -> abstract mem_wr interface
```

它只产生写请求，连接既有：

```text
sdram_arbiter -> p1_sdram_cached_adapter -> APUG011 -> internal SDRAM
```

它不例化或改动 HDMI PLL、APUG092/PHY、P1-05A 读 CDC、line prefetch、line buffer 或 scanout。

## 时钟与 CDC

模块内 `fat32_file_reader`、BMP 解码和 `framebuffer_writer` 共享 `clk`。因此 `sector_req/sector_ready/sector_din_valid/sector_din` 也必须在同一时钟域。实际 TF/SD 物理 reader 若处于独立时钟域，必须先经显式 request/response CDC bridge 后才能连接；禁止直接把异步 byte stream 接入。

## 固定 P1-05B 首个媒体基线

- 24-bit、BI_RGB、positive-height/bottom-up BMP；
- 默认精确 640×480；无 scaler、无裁剪、无隐式地址重排；
- 每像素一个 32-bit word，`0x00RRGGBB`；
- `frame_base` 必须 4-word 对齐；默认 stride=640；
- 非 640×480 或无效 header 必须失败，不能写入部分帧后声明成功。

## 完成语义

`done` 仅在 FAT reader、BMP pixel stream 与 framebuffer writer 都达到 terminal state 后脉冲。成功要求：

```text
file_ok && pixels_ok && writer_ok && !overflow && !source_error
```

`framebuffer_writer` 会等待 FIFO 全部排空，因而 loader 成功表示所有 abstract write 已被 `sdram_arbiter` 接受。后端 cached-adapter 的最后一组 APUG011 命令仍可能在其内部寄存器中完成；上板集成的 `frame_ready` 只能在确认后端没有 protocol/provider error 后释放。

## 后续集成顺序

1. 本模块取得 `[U]`；
2. 在不修改 P1-05A read/display path 的情况下，把 `mem_wr_*` 接入其既有 arbiter/cached-adapter；
3. 添加 storage-side CDC/provider wrapper；
4. 取得一张真实 BMP 写入 SDRAM 的 board evidence；
5. 再扩展 A/B metadata 和 frame-boundary swap。 
