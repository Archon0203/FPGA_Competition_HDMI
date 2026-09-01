# P0-05 `line_buffer_pingpong` 接口与时序说明

> Architecture Contract v1.0 保持冻结。  
> 当前交付状态：**candidate，等待 Codex/ModelSim 实际回归后才能标 `[U]`**。

## 1. 职责

`line_buffer_pingpong` 是显示侧的双行缓冲，位于：

```text
line_prefetcher -> line_buffer_pingpong -> display-order RGB stream
```

它只负责：

- 接收 `line_prefetcher` 顺序送入的一整行 RGB888；
- 两个 bank 的 fill/read 所有权管理；
- 仅将完整、成功的行标记为 ready；
- display 请求某行时连续输出 `read_width` 个 pixel；
- 请求行尚未 ready 时输出同宽黑行，并报告 underflow，从而保持显示时序连续。

它不负责：

- SDRAM 地址计算；
- memory request/response；
- frame A/B swap；
- HDMI timing；
- APUG011/APUG092 vendor 接口。

## 2. Fill 接口

```text
fill_start + fill_line_index + fill_width
              ↓
          fill_accept
              ↓
fill_valid + fill_data[23:0] × width
              ↓
fill_done + fill_ok
              ↓
      fill_commit_pulse / fill_fail_pulse
```

`fill_ready=1` 表示至少有一个 free bank。

成功 commit 必须同时满足：

- width 在 `1..MAX_LINE_PIXELS`；
- 收到的 `fill_valid` 数恰好等于 width；
- `fill_ok=1`；
- 没有 overflow/protocol error。

incomplete/overflow fill 不会形成 ready line，bank 可重新利用。

## 3. Read 接口与连续输出

输入：

```text
read_start
read_line_index
read_width
```

若 ready bank 的 `(line_index,width)` 同时匹配：

- 该 bank 立即从 ready 集合中移除并保留给 reader；
- **从 read_start 被接受后的下一个时钟开始**输出首像素；
- `pixel_valid` 连续保持 `read_width` 个周期；
- 最后一个 pixel 周期同时 `line_done=1`；
- 行结束后 bank 才重新成为 free。

若行缺失或 width 不匹配：

```text
pixel_valid = 1 for read_width cycles
pixel_data  = 24'h000000
underflow_pulse = 1
underflow_sticky = 1
```

即 underflow 的策略是“黑行替代”，而不是让 active-line pixel stream 出现空洞。

## 4. Ping-pong 所有权

每个 bank 处于以下互斥状态之一：

```text
FREE
FILLING
READY
READING
```

约束：

- `FILLING` bank 不可读；
- `READY/READING` bank 不可覆盖；
- 两 bank 都 `READY/READING` 时 `fill_ready=0`；
- reader 完整消费一行后才释放该 bank；
- 新 commit 若发现另一个 READY bank 是同一 line index，会丢弃旧 duplicate，避免陈旧副本永久占 bank。

## 5. 存储格式与资源

line buffer 内部只保存 RGB888：

```text
{R[7:0], G[7:0], B[7:0]}
```

默认：

```text
2 banks × 640 pixels × 24 bit = 30,720 bit
```

约 3.75 KiB。

**RAM 数组本身故意不做 reset/clear**；复位只清 `READY/FILLING/READING` 所有权元数据，因此未初始化 RAM 内容不会被显示。这样可以避免“整块 RAM 带异步清零”破坏 TD 的 ERAM 推断机会。

到 `[S]` 阶段仍必须在 TD resource report 中核对该数组是否按预期映射到 ERAM，而不是大量 LUT/FF；若未正确推断，应调整为安路推荐的 RAM inference/template，但不得改变本模块外部契约。

## 6. 时钟域边界

P0 当前是**单时钟抽象接口**，用于先闭合功能与随机 stall 链路。

正式 APUG011 集成时，若 `line_prefetcher` 与 HDMI pixel path 不在同一时钟域，必须在 `system_top`/wrapper 通过合法 CDC、dual-port RAM 或 async FIFO 解决；不能把普通控制脉冲直接异步跨域。

这属于 P1/`[S]` 集成约束，不改变 P0-05 的行缓冲职责。
