# P0-02 `bmp_pixel_stream` Test Vector 说明

联合例化：

```text
bmp_parser + bmp_pixel_stream
```

两者共享同一 BMP byte stream，从而专门验证 parser → pixel-stream 的真实边界。

## 测试矩阵

| Case | 内容 | 预期/目的 |
|---|---|---|
| CASE0 | 2×2, padding=2, 连续无 stall | 首像素边界 + BGR→RGB + bottom-up |
| CASE1 | width=4, padding=0 | padding=0 |
| CASE2 | width=1, padding=1 | padding=1 |
| CASE3 | width=2, padding=2 | padding=2 |
| CASE4 | width=3, padding=3 | padding=3 |
| CASE5 | width=17 | 非整齐小宽度 |
| CASE6 | width=640 | 正式 baseline；RGB888 每行无 padding |
| CASE7 | width=641 | baseline 邻界；必须出现 padding |
| CASE8 | `data_offset=70` + gap/trailing bytes | 不能把 header gap 当像素 |
| CASE9 | bad magic | `bmp_ok=0` 后必须失败且不出像素 |
| CASE10 | negative/top-down height | baseline 拒绝 |
| CASE11 | zero width | 非法尺寸 |
| CASE12 | 像素中途 `file_done` | truncation 必须失败 |
| CASE13 | 上游 `file_ok=0` | 上游失败时像素阵列不完整，必须失败 |

正常 case 会随机插入 `din_valid=0` stall，DUT 只能按有效 byte 推进状态。

## Golden

TB 的 RGB pattern 独立按 `(x,y)` 生成：

```text
R = pattern_r(x,y)
G = pattern_g(x,y)
B = pattern_b(x,y)
```

BMP builder 再独立以 B/G/R 顺序和 bottom-up 行序写入 `file_mem`。

monitor 根据收到的第 N 个 pixel 独立计算期望：

```text
exp_x = N % width
exp_y = height - 1 - floor(N/width)
```

然后逐项比较：

- `pixel_x`
- `pixel_y`
- R
- G
- B
- 总 pixel count
- `done/ok`

padding byte 使用特殊值 `A5/5A/C3`，如果 DUT 错把 padding 当像素会立即失败。

## 验收

只有完整执行 CASE0..CASE13，且最终 transcript 出现：

```text
PASS: bmp_pixel_stream all adversarial cases passed (...)
```

才能标记：

```text
bmp_pixel_stream [U]
```

这仍不代表 BMP→framebuffer 主链达到 `[C]`。

## 2026-08-31 实际回归结果

ModelSim 已完整执行 CASE0~CASE13：

```text
PASS: bmp_pixel_stream all adversarial cases passed (checks=13393)
```

波形抽查 CASE0 首像素：

```text
pixel_r = 0x21
pixel_g = 0x45
pixel_b = 0x62
pixel_x = 0
pixel_y = 1
```

与 `pattern_r/g/b(0,1)` 完全一致，因此本模块正式标记 **[U] UNIT PASS**。
