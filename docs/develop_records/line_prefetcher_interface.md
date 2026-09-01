# P0-06 `line_prefetcher` 接口与时序说明

> Architecture Contract v1.0 保持冻结。  
> 当前交付状态：**candidate，等待 Codex/ModelSim 实际回归后才能标 `[U]`**。

## 1. 职责

`line_prefetcher` 是 SDRAM 的**读请求源**：

```text
frame_buffer_manager(read metadata)
        ↓
line_prefetcher
        ├─ memory read request -> sdram_arbiter -> mock SDRAM / APUG011
        └─ ordered RGB response -> line_buffer_pingpong
```

它负责：

- 根据 `frame_base + line_index * stride` 计算行首 word address；
- 连续发出 `frame_width` 个 32-bit word read；
- 支持最多 `MAX_OUTSTANDING` 个有序 outstanding request；
- 将 memory `0x00RRGGBB` 的低 24 bit 送入 line buffer；
- 在 line buffer 有 free bank 后才开始 memory traffic；
- timeout/非法响应时失败并释放已分配 line bank。

它不负责：

- frame swap；
- read/write 仲裁；
- APUG011 busy/refresh 时序；
- HDMI 输出。

## 2. 配置

输入：

```text
start
frame_base[20:0]
frame_width
frame_height
frame_stride_words
line_index
```

要求：

```text
frame_width > 0
frame_height > 0
line_index < frame_height
frame_stride_words >= frame_width
frame_base 4-word aligned
last_address < 2^21
```

行首：

```text
line_base = frame_base + line_index * frame_stride_words
```

第 x 个读地址：

```text
addr = line_base + x,  x=0..frame_width-1
```

## 3. Abstract memory read interface

请求：

```text
mem_rd_valid
mem_rd_addr[20:0]
mem_rd_ready
```

接受条件：

```text
mem_rd_valid && mem_rd_ready
```

响应：

```text
mem_rvalid
mem_rdata[31:0] = 0x00RRGGBB
```

当前契约要求 response 与 accepted request **保持顺序一致**。P0 不需要 response tag。

为了隐藏 SDRAM latency，模块不是严格“一请求一等待”，而是允许最多 `MAX_OUTSTANDING`（默认 8）个 read 同时在途。credit 满后暂停发新请求，收到 response 后恢复。

## 4. Line-buffer fill

只有 `lb_fill_ready=1` 后才：

```text
lb_fill_start=1
lb_fill_line_index=line_index
lb_fill_width=frame_width
```

随后每个合法 memory response 直接形成：

```text
lb_fill_valid=1
lb_fill_data=mem_rdata[23:0]
```

收到恰好 `frame_width` 个 response、且 outstanding=0 后：

```text
lb_fill_done=1
lb_fill_ok=1
```

失败且已经分配 bank 时：

```text
lb_fill_done=1
lb_fill_ok=0
```

用于明确释放 incomplete fill，不能让 line buffer 永久卡在 FILLING 状态。

## 5. Timeout / protocol error

`STALL_TIMEOUT_CYCLES` 统计“没有任何 forward progress”的连续周期：

- 等待 `lb_fill_ready`；
- request 长时间不被 `mem_rd_ready` 接受；
- 已有 outstanding request 但长期无 response。

timeout 后 `ok=0`；若 line bank 已分配则发送 failed fill completion 释放 bank。

如果失败时已经存在**被 memory 接受但尚未返回**的 read request，则当前无 tag 接口无法取消这些 response。为防止 stale response 在下一次事务中被误认为新行数据，模块置 sticky `recovery_required=1` 并拒绝新的 `start`，直到 prefetch/memory path 被复位。

没有 accepted outstanding read 的错误（如等待 line buffer 超时、request 从未被 ready 接受、非法配置）仍可不复位重试。

以下也失败：

- unexpected `mem_rvalid`（当前没有合法 outstanding request）；
- busy 时再次 `start`；
- 地址/尺寸配置非法。

> P1 接真实 APUG011 时还必须验证 adapter/arbiter 能保证“accepted read 最终有且只有一个有序 response”；若底层接口具有更复杂的 cancel/flush 语义，需要在 adapter 层吸收，而不是让 prefetcher 猜 vendor 时序。

## 6. 地址乘法资源

当前 P0 baseline 保留可读表达式：

```text
line_index * frame_stride_words
```

到 `[S]` 阶段检查 TD resource/timing。若综合结果证明代价过高，只能在保持相同接口/地址契约下做行基址累加或 strength reduction 优化。


### `recovery_required`

Sticky 安全状态；表示失败事务遗留了无法取消的 accepted read。置位后必须 reset 该 prefetch/memory path。
