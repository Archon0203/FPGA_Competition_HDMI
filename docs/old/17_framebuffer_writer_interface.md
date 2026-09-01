# P0-03 `framebuffer_writer` 接口与时序说明

> Architecture Contract v1.0 保持冻结。  
> 本文件是 P0-03 的实现级接口说明，不修改顶层架构。  
> 当前交付状态：**[U] UNIT PASS（2026-08-31）**。
> ModelSim：CASE0~CASE8 全部通过，`PASS: framebuffer_writer all adversarial cases passed (checks=1345)`。
> 波形抽查：首次接受写请求 `addr=740`、`data=0x00112131`，对应 `(x=0,y=1), base=100, stride=640`。

## 1. 职责

`framebuffer_writer` 是 SDRAM 的**写请求源**，负责：

```text
bmp_pixel_stream / media pixel
  RGB888 + x/y
      ↓
framebuffer_writer
  address + 0x00RRGGBB
      ↓
sdram_arbiter / mock SDRAM
```

它只做：

- RGB888 → `0x00RRGGBB`；
- `pixel_x/pixel_y` → 21-bit SDRAM word address；
- 吸收短时 `mem_wr_ready=0`；
- 等待 pending writes 全部提交后报告一帧结束；
- 检测 overflow / 非法坐标 / 上游错误 / 非法配置。

它**不做**：

- buffer A/B swap；
- SDRAM read；
- read/write 仲裁；
- APUG011 时序；
- BMP 解包。

这些职责分别属于 `frame_buffer_manager`、`sdram_arbiter`、`sdram_adapter` 等模块。

## 2. 配置与地址

输入：

| 端口 | 位宽 | 含义 |
|---|---:|---|
| `start` | 1 | 新帧写事务开始；仅在 `busy=0` 接受 |
| `frame_base` | 21 | 32-bit word base address，必须 4-word 对齐 |
| `frame_width` | 16 | 有效像素宽度 |
| `frame_height` | 16 | 有效像素高度 |
| `frame_stride_words` | 16 | 每行在 SDRAM 中的 word stride，必须 `>= frame_width` |

地址公式：

```text
word_addr = frame_base + pixel_y * frame_stride_words + pixel_x
```

正式 640×480 RGB baseline 可使用：

```text
frame_stride_words = 640
Image A base = 0
Image B base = 307200
```

输入坐标必须满足：

```text
pixel_x < frame_width
pixel_y < frame_height
word_addr < 2^21
```

因此即使 `bmp_pixel_stream` 按 BMP 文件顺序先输出底部行，例如：

```text
(x=0,y=479), (1,479), ...
```

writer 仍会把它写入正确的 display-order framebuffer row。

## 3. 像素接口

| 端口 | 方向 | 说明 |
|---|---|---|
| `pixel_valid` | in | 当前 RGB/x/y 有效 |
| `pixel_r/g/b` | in | RGB888 |
| `pixel_x/y` | in | display-coordinate 坐标 |
| `pixel_ready` | out | 内部 FIFO 当前仍能接收像素 |

写数据固定为：

```text
mem_wr_data = 0x00RRGGBB
```

### 为什么有内部 FIFO

当前冻结后的 `bmp_pixel_stream` 是 valid-only 输出，并没有 ready/backpressure 输入。
因此 writer 内置 `PIXEL_FIFO_DEPTH` 个 entry（默认 8），用于吸收 SDRAM/arbiter 的**短时 stall**。

这不是无限缓存：

```text
pixel_valid && !pixel_ready
```

意味着像素源速度超过 writer 能承受的 stall 窗口。模块必须：

- `overflow=1`；
- 本帧最终 `ok=0`；
- **禁止静默覆盖 FIFO 内旧数据**。

P0 端到端 CHAIN TB 后续仍需用 random memory stall 验证实际链路不会触发 overflow。

## 4. Memory write request

| 端口 | 方向 | 说明 |
|---|---|---|
| `mem_wr_valid` | out | FIFO head 存在有效 write request |
| `mem_wr_addr[20:0]` | out | word address |
| `mem_wr_data[31:0]` | out | `0x00RRGGBB` |
| `mem_wr_ready` | in | arbiter/mock memory 接受本次请求 |

真正提交一次写请求的条件：

```text
mem_wr_valid && mem_wr_ready
```

`mem_wr_ready=0` 时地址和数据保持来自同一个 FIFO head，不能跳过或重复推进。

## 5. Frame completion

来自像素源：

| 端口 | 说明 |
|---|---|
| `source_done` | 上游像素帧已经结束 |
| `source_ok` | 上游该帧是否合法/完整 |

writer **不能在 `source_done` 到来时立刻宣布完成**，因为 FIFO 中可能还有未被 memory 接受的写请求。

正确顺序：

```text
source_done
    ↓
latch source status
    ↓
继续 drain pending writes
    ↓
FIFO empty
    ↓
done pulse
```

输出：

- `busy`：当前帧事务仍在进行；
- `done`：**单周期脉冲**；
- `ok`：`done` 时的结果，并保留到下一次 `start`；
- `overflow`：本帧 overflow sticky flag，下一次 `start` 清零。

成功必须同时满足：

```text
source_ok == 1
no internal error
accepted_pixel_count == frame_width * frame_height
all pending writes drained
```

## 6. 当前实现的失败条件

- `frame_width==0` / `frame_height==0`；
- `frame_stride_words < frame_width`；
- `frame_base` 非 4-word 对齐；
- 坐标越界；
- word address 超出 21-bit SDRAM 地址范围；
- source 报错；
- FIFO overflow；
- `busy=1` 时重复 `start`。

## 7. 资源注意事项

当前地址表达式包含：

```text
pixel_y * frame_stride_words
```

这是**有意保留的可读 baseline 实现**。P0 首先验证功能；到 `[S]` 阶段必须查看 TD resource report。
如果该乘法导致 LUT/DSP 代价不合理，只能基于实际 synthesis 证据提出实现优化，不能擅自改变 framebuffer 地址契约。
