# P0-08 `tb_framebuffer_mock_chain` Test Vector 说明

> Testbench：`sim_tb/framebuf/tb_framebuffer_mock_chain.v`

## CASE-GOLDEN

先用 literal 检查 integration TB 自己的 RGB golden generator：

```text
seed=0x10, x=0, y=0 -> 0x1050B0
seed=0x10, x=1, y=2 -> 0x1D5BC7
```

这是吸取 P0-05 TB width bug 的教训：**golden 本身也必须被固定向量校验**。

## CASE0 — 第一次完整 frame

```text
17x5, seed=0x10
```

流程：

```text
manager load -> Image B
writer -> arbiter -> mock_sdram
writer success
frame boundary
B becomes front
逐行 prefetch 0..4
line buffer -> display RGB compare
```

验证 manager/writer/readback/line-buffer 的基础闭环。

## CASE1 — 读写并发 + 640 baseline

保持 Image B(17x5) 正在显示，同时：

```text
writer: 加载 640x2 seed=0x20 到 Image A
reader: 从仍为 front 的 Image B 预取 line 3
```

必须实际观察到 contention，并证明：

```text
prefetch read accepted
writer 同拍 wr_ready=0
```

第二帧写完后只在 frame boundary swap 到 Image A，再读取 640-pixel line 0/1，逐像素 compare。

## CASE2 — 不 reset 再次复用 B

加载 `9x3 seed=0x33`，验证 A/B ownership 第三轮交替以及 line-buffer bank reuse。

## CASE3 — 最终状态

必须全部为安全状态：

```text
arbiter protocol_error = 0
arbiter outstanding = 0
mock pending reads = 0
mock range_error = 0
mock queue_error = 0
line buffer protocol_error = 0
line buffer underflow_sticky = 0
```

同时要求 read/write 都有大量 command 真正通过 arbiter。

## 验收

只有看到：

```text
PASS: framebuffer mock chain all integration cases passed (...)
```

才可把 P0-08 标为 framebuffer/mock sub-chain `[C]`；仍不得把 FAT32→BMP→display 全链标 `[C]`。
