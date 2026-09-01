# P0-08 Mock SDRAM / Framebuffer Mini-Chain

> 状态：**candidate，待 ModelSim integration regression**

## 1. 目标

把已经单元验证的 framebuffer 模块第一次连成真正的数据闭环：

```text
frame_buffer_manager
     │
     ├─ framebuffer_writer -----------\
     │                                 \
     │                           sdram_arbiter
     │                                 │
     │                            mock_sdram
     │                                 │
     └─ line_prefetcher <--------------/
              │
              ↓
      line_buffer_pingpong
              │
              ↓
       display-order RGB888
```

P0-08 不包含 FAT32/BMP，因此它不是完整媒体主链 `[C]`；它验证的是 **framebuffer/mock-memory sub-chain**。

## 2. `mock_sdram.v`

该模块只存在于 `sim_tb/framebuf/`，不加入 TD synthesis project。

行为：

- 32-bit word address；
- depth 默认在 integration TB 中设为 400000 words，可覆盖 Image A=0 和 Image B=307200 的测试区域；
- write command 可随机 stall；
- read request 可随机 stall；
- accepted read 进入有序 response queue；
- response 带 1~7 cycle 随机 latency，并可额外随机 stall；
- response 顺序严格保持 request acceptance 顺序；
- memory array 不在 reset 时整块清零。

这模拟 APUG011 集成阶段最需要面对的三类现象：command backpressure、read latency、response burst/stall。

## 3. 集成不变量

integration TB 必须同时证明：

1. writer 写入的是 `0x00RRGGBB`；
2. manager 只在 frame boundary swap A/B；
3. prefetcher 读的是当前 front buffer；
4. writer 写 back buffer 时，仍允许读取 front buffer；
5. read/write 同时争用时 read priority 生效；
6. line buffer 最终输出 display-order RGB；
7. active line 一旦开始，`pixel_valid` 中途不得产生 gap；
8. 最终无 underflow、无 outstanding read、无 range/queue/protocol error。

## 4. 与下一阶段的关系

P0-08 PASS 后，下一步不是直接上 APUG011，而是再做：

```text
fat32_file_reader
 -> bmp_parser / bmp_pixel_stream
 -> framebuffer_writer
 -> sdram_arbiter / mock_sdram
 -> line_prefetcher / line_buffer_pingpong
 -> display-order RGB
 -> independent golden
```

该完整链通过后才标 P0 media chain `[C]`。
