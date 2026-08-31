# P0-02 `bmp_pixel_stream` 接口与时序说明

> Architecture Contract v1.0  
> 目标：`[U] UNIT PASS`  
> 本模块只负责 BMP 像素阵列 → RGB888 像素流，不感知 SDRAM。

## Baseline

仅支持冻结架构规定的 BMP baseline：

- 24-bit
- `BI_RGB` / uncompressed
- positive height / bottom-up
- 每行按 4-byte 边界 padding
- BGR888 文件字节顺序
- `bmp_parser` 已完成头字段合法性判断

不支持：

- top-down BMP
- RLE/compressed BMP
- 8/16/32-bit BMP
- palette BMP
- framebuffer address / SDRAM write

## 接口

| 端口 | 方向 | 说明 |
|---|---|---|
| `clk` | in | 文件流时钟域 |
| `rst_n` | in | 异步低有效复位 |
| `start` | in | 新 BMP 开始；允许不复位连续处理多个文件 |
| `din[7:0]` | in | 与 `bmp_parser` 共享的完整文件 byte stream |
| `din_valid` | in | 当前 `din` 有效 |
| `header_done` | in | `bmp_parser.done` |
| `bmp_ok` | in | `bmp_parser` 的 baseline 合法性结果 |
| `width/height` | in | BMP 尺寸 |
| `file_done/file_ok` | in | 上游文件流结束状态 |
| `pixel_valid` | out | 一拍 RGB 像素有效 |
| `pixel_r/g/b` | out | RGB888 |
| `pixel_x/y` | out | display-order 坐标 |
| `done` | out | 像素阵列完成或失败 |
| `ok` | out | `done=1` 时的成功/失败状态 |

## 关键边界

`bmp_parser` 在消费 `data_offset-1` 的 header 最后一个 byte 后拉高 `done`。
若 byte stream 连续，则下一拍就是首个像素 B byte；此时本模块看到：

```text
header_done = 1
din_valid   = 1
din         = first_pixel.B
```

所以进入像素态的同一拍必须直接保存这个 B byte，不能等下一拍。

## 像素/行逻辑

BMP 文件中每像素为：

```text
B, G, R
```

输出：

```text
pixel_b = B
pixel_g = G
pixel_r = R
```

行字节数：

```text
row_bytes = width * 3
padding   = (4 - (row_bytes mod 4)) mod 4
```

padding 范围固定为 0..3。

bottom-up 映射：

```text
第一条文件像素行 -> pixel_y = height-1
...
最后一条文件像素行 -> pixel_y = 0
```

每行内部 `pixel_x` 从 0 递增到 `width-1`。

## 完成/失败

成功：
- 已消费最后一行最后一个像素及其必要 padding；
- `done=1, ok=1`，保持到下一次 `start`。

失败：
- header 完成前 `file_done`
- `bmp_ok=0`
- `width=0`
- `height=0`
- baseline 不支持的 top-down height
- 像素/行 padding 尚未完整时 `file_done`

像素阵列完成后的 trailing bytes 不属于本模块职责，可忽略。
