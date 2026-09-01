# P0-04 `frame_buffer_manager` 接口与时序说明

> Architecture Contract v1.0 保持冻结。  
> P0-04 baseline 先实现 **Image A/B 双缓冲**；视频三缓冲属于后续扩展，不在本任务扩大范围。  
> 当前状态：**[U] UNIT PASS（2026-08-31）**。
> ModelSim：CASE0~CASE6 全部通过，`PASS: frame_buffer_manager all adversarial cases passed (checks=166)`。
> 波形抽查：首次 swap 后 `read_base=307200`、`write_base=0`、`read_frame_valid=1`、`read_width=640`。

## 1. 职责

`frame_buffer_manager` 只做：

- Image A/B 所有权管理；
- read/front base 与 write/back base 分配；
- 每个物理 buffer 的 `width/height/stride/valid` metadata；
- 新帧加载状态；
- 完整帧 pending；
- frame-boundary swap；
- 读写保护。

它**不产生任何 SDRAM request**。

正式关系仍是：

```text
frame_buffer_manager
  ├─ controls framebuffer_writer (write source)
  └─ provides read_base to line_prefetcher (read source)

framebuffer_writer ─┐
                    ├─> sdram_arbiter
line_prefetcher  ───┘
```

## 2. Frozen Image buffer map

默认参数：

```text
IMAGE_A_BASE = 0
IMAGE_B_BASE = 307200
```

单位均为 32-bit word。

reset 后：

```text
read/front  = Image A
write/back  = Image B
```

两个 base 必须：

- 不相同；
- 4-word 对齐。

否则 `config_error=1`，`load_ready=0`。

## 3. Load transaction

上层请求同时携带 back-frame metadata：

```text
load_start
load_width
load_height
load_stride_words
```

只有：

```text
load_ready = 1
```

时才接受。

成功接受后：

1. 将 `load_width/load_height/load_stride_words` 写入当前物理 back buffer 的 metadata；
2. 立即清除该 back buffer 的 `valid`（因为旧内容即将被覆盖）；
3. 输出单周期：

```text
load_accept = 1
writer_start = 1
```

同时 `write_width/write_height/write_stride_words` 向 `framebuffer_writer` 提供本次配置。

并置：

```text
write_in_progress = 1
```

此时 `write_base` 保持指向 back buffer。

以下情况 `load_ready=0`：

- writer 正在写；
- 已有完整 back frame 等待 swap；
- buffer map 配置非法。

因此 pending frame 不会被下一次加载覆盖。

## 4. Writer completion

来自 `framebuffer_writer`：

```text
writer_done + writer_ok
```

若成功：

```text
write_in_progress -> 0
back_buffer.valid -> 1
pending_swap      -> 1
```

若失败：

```text
write_in_progress -> 0
pending_swap      -> 0
load_fail_pulse   -> 1 (one cycle)
```

失败不会改变 `read_base` 或当前 front metadata，所以当前显示帧保持稳定；失败的 back buffer 保持 `valid=0`，可重新加载。

## 5. Tear-free swap

只有同时满足：

```text
pending_swap == 1
display_frame_boundary == 1
write_in_progress == 0
```

才交换 front/back：

```text
old read  -> new write
old write -> new read
```

并输出：

```text
swap_pulse = 1  // one cycle
```

### 同拍 writer_done + frame boundary

当前实现采用明确的保守语义：

> **不在该拍立刻显示刚完成的 frame，而是等下一个 `display_frame_boundary`。**

原因是避免“刚完成”和“显示边界”的组合时序出现模糊判定，确保完整帧可见性是确定的。

所以：

```text
writer_done & boundary (same edge)
       ↓
pending_swap=1
       ↓
next boundary
       ↓
swap
```

最多增加一个显示帧周期延迟，但不会撕裂。

## 6. 输出

| 输出 | 含义 |
|---|---|
| `read_base` | 当前显示/front buffer，供 `line_prefetcher` 使用 |
| `read_width/read_height/read_stride_words` | 当前 front frame metadata |
| `read_frame_valid` | 当前 front buffer 是否包含已完整写入的有效 frame |
| `write_base` | 当前 back buffer，供 `framebuffer_writer` 使用 |
| `write_width/write_height/write_stride_words` | 当前 back/load metadata，供 writer 使用 |
| `read_buffer_sel` | 0=A, 1=B |
| `write_buffer_sel` | 0=A, 1=B |
| `write_in_progress` | 当前 back buffer 正在写 |
| `pending_swap` | 有完整 frame 等待显示边界 |
| `load_ready` | 可以接受下一次加载 |
| `load_accept` | load request 被接受的单周期事件 |
| `writer_start` | 启动 writer 的单周期事件 |
| `swap_pulse` | A/B 所有权完成交换的单周期事件 |
| `load_fail_pulse` | writer 失败事件 |
| `config_error` | A/B base 参数非法 |

## 7. CDC 边界

本模块本身是单时钟控制逻辑。

若未来：

- `writer_done` 来自不同 clock domain；或
- `display_frame_boundary` 来自 `clk_pix` 而 manager 在其他时钟域；

必须在 `system_top`/CDC 层先做事件同步或 async FIFO，不能直接跨域采样。
