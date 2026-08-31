# 31 · P0 完整媒体主链端到端回归

## 目标

本阶段不新增业务功能，而是验证冻结 P0 主链：

```text
FAT32 fragmented file
  -> fat32_file_reader
  -> bmp_parser / bmp_pixel_stream
  -> frame_buffer_manager / framebuffer_writer
  -> sdram_arbiter
  -> mock_sdram
  -> line_prefetcher
  -> line_buffer_pingpong
  -> display-order RGB888
  -> independent golden
```

只有这条回归实际 PASS，才允许把 **P0 media chain** 标为 `[C] CHAIN PASS`。

## 为什么这是最终 P0 验收

此前：

- P0-01~P0-07 是模块级 `[U]`；
- P0-08 已证明 framebuffer/mock-memory 子链 `[C]`；
- 但 storage/BMP 与 framebuffer/display 仍未在同一个 TB 中闭环。

本 TB 使用真实 `fat32_file_reader` 读 fragmented FAT chain，不直接喂 BMP byte；最终只在 line-buffer display-order RGB 端与独立 golden 比较。

## 集成控制约定

`bmp_parser.bmp_ok` 在 BITMAPINFOHEADER 的 compression 字段读完后即可为真；baseline 的 `data_offset >= 54`。因此控制胶水在 `bmp_ok + width/height/bpp/data_offset` 合法后启动 `frame_buffer_manager`，在首个 pixel byte 到来前使 `framebuffer_writer` 进入 busy。

TB 有断言：

```text
bmp_pixel_valid && !writer_busy -> ERROR
bmp_pixel_valid && !pixel_ready -> ERROR
```

这专门验证 valid-only BMP pixel stream 不会在 writer 尚未准备好时丢像素。

## 状态口径

在本 TB 未实跑前：

```text
P0-09 full media chain = candidate
P0 media chain         = not [C]
```

实跑 PASS 后：

```text
P0-09 full media chain = [C]
P0 media chain         = [C]
```

注意：这里仍然使用 `mock_sdram`，不代表 APUG011/TD/板级通过。后续状态仍需 `[S]` / `[B]`。
