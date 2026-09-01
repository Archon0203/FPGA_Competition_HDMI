# P0-05 TB Golden 修复 / P0-06 状态同步

## P0-05 `line_buffer_pingpong`

旧回归：

```text
CASE0~CASE8 PASS
PASS: line_buffer_pingpong all adversarial cases passed (checks=2202)
```

但该结果**撤销作为 `[U]` 的依据**，原因是 TB `pattern()` 的 Verilog 表达式宽度错误导致 96-bit 拼接截断，只真正变化了 B 通道；stimulus 与 golden 又共用同一错误函数，因此发生 false PASS。

本次修复：

- R/G/B 各自先落入 `reg [7:0]`；
- 再用 `{r,g,b}` 组成 24-bit RGB；
- 新增固定 literal 的 `CASE-GOLDEN`：
  - `pattern(10,0) == 24'h0A40B2`
  - `pattern(10,1) == 24'h0B43B3`

修复后已重新执行 CASE-GOLDEN+CASE0~CASE8，最终 PASS（checks=2204），因此 P0-05 正式 `[U]`。

## P0-06 `line_prefetcher`

实测：

```text
CASE0~CASE13 全部通过
PASS: line_prefetcher all adversarial cases passed (checks=2713)
```

且其 `mem_rgb(a)` 三通道均为显式 8-bit，不存在 P0-05 的 golden 截断问题。

因此：

```text
P0-06 line_prefetcher [U]
```

仍然不能把 framebuffer/media 主链标为 `[C]`。
