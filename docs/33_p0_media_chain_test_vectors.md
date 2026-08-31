# 32 · P0 完整媒体主链测试向量

Testbench：

```text
sim_tb/integration/tb_p0_media_chain.v
```

运行：

```text
cd sim_work
vsim -c -do ../sim_tb/integration/run_p0_media_chain.do
```

## CASE-GOLDEN

固定字面量校验独立 display golden：

```text
seed=0x12, x=0, y=0 -> 0x125492
```

另固定检查 `seed=0x12, x=1, y=2 -> 0x1D659F`。用于避免 stimulus/golden 共用同一错误函数导致 false PASS。

## CASE0 — fragmented FAT32 + 17×12 BMP

- BMP: 24-bit BI_RGB, bottom-up
- `width=17`, 因 `17*3=51`，每行 padding=1
- file > 512 byte
- FAT chain: `3 -> 7 -> EOC`
- SD sector model 有随机 startup delay 与 `din_valid` stall
- SDRAM mock 同时有独立随机 stall/latency
- 最终检查全部 17×12 display-order RGB

目的：

- fragmented cluster 跳转；
- FAT entry lookup；
- BMP header→pixel 边界；
- BGR→RGB；
- bottom-up→display y；
- row padding；
- framebuffer word round-trip。

## CASE1 — 640×2 baseline + 8 个碎片 cluster

BMP file 约 3.9KB，chain：

```text
3 -> 7 -> 5 -> 12 -> 9 -> 20 -> 4 -> 15 -> EOC
```

检查：

- 至少 8 个 data-cluster transaction；
- 至少 7 次 FAT traversal；
- `read_width=640`；
- 两条 640-pixel active line 从第一个 `pixel_valid` 开始不得出现 gap；
- 1280 个最终 RGB 全部与独立 golden 一致。

## CASE2 — 不 reset 连续第三个媒体文件

- 13×4
- `data_offset=70`
- header 与 pixel array 之间填 `0xEE` gap
- 单 cluster
- A/B buffer 再次切换

目的：

- parser 不把 gap byte 当像素；
- storage/parser/writer/manager/display 整链可无全局 reset 复用。

## CASE3 — 最终 sticky 状态

必须全部为正常：

```text
arbiter protocol_error = 0
arbiter outstanding    = 0
mock pending_reads     = 0
mock range_error       = 0
mock queue_error       = 0
linebuffer protocol_error = 0
linebuffer underflow_sticky = 0
prefetch recovery_required = 0
```

最终预期：

```text
PASS: P0 media chain end-to-end all cases passed (...)
```
