# P0-05 `line_buffer_pingpong` Test Vector 说明

> TB：`sim_tb/framebuf/tb_line_buffer_pingpong.v`  
> 当前状态：candidate，等待实际 ModelSim PASS。

| Case | 场景 | 目的 |
|---|---|---|
| CASE0 | 4-pixel 基本 fill/read | RGB 数据与 line metadata 保真 |
| CASE1 | 两 bank 均 ready | 第三次 fill 必须被 backpressure，消费一行后恢复 `fill_ready` |
| CASE2 | 请求不存在的 line | 输出连续同宽黑行 + underflow，不允许 `pixel_valid` 断流 |
| CASE3 | line index 命中但 width 不匹配 | 不能误读陈旧/错误尺寸数据；按 underflow 处理 |
| CASE4 | incomplete fill | 不得形成 ready line，bank 必须可复用 |
| CASE5 | 超过声明 width 的 fill data | 必须失败并置 protocol error，禁止覆盖/静默截断后宣称成功 |
| CASE6 | width=640 | 正式 baseline 整行连续输出；逐 pixel golden compare |
| CASE7 | 多轮 bank 重用且不 reset | 验证 ping-pong ownership 长序列 |
| CASE8 | width=641 > MAX | 非法 fill/read 拒绝 |

Golden 数据由独立 `pattern(line,x)` 生成，读出阶段逐 pixel 比较。

连续性检查不是只数 pixel 数量：从首个 `pixel_valid` 到最后一个 pixel 之间，TB 每个周期都要求 `pixel_valid==1`，并检查 `line_done` 只在最后一个 pixel 同拍出现。

验收字符串：

```text
PASS: line_buffer_pingpong all adversarial cases passed (...)
```

只有实际出现 PASS 才可将 P0-05 标为 `[U]`。


## Golden 生成宽度修正（2026-08-31）

原 testbench 的 `pattern()` 曾直接把三个 `integer` 算术表达式放入拼接：

```verilog
pattern = { ((line_no + x) & 8'hff),
            ((8'h40 + x*3) & 8'hff),
            ((8'h80 + line_no*5 + x) & 8'hff) };
```

在 Verilog 中这些表达式会按 32-bit integer 宽度参与拼接，形成 96-bit 值，再赋给 24-bit 返回值时只保留最低 24 bit，导致 R/G 实际恒为 0。由于 stimulus 与 golden 共用同一函数，旧 TB 会“自洽 PASS”。

已修复为三个显式 `reg [7:0]` 通道后再拼接：

```verilog
r = (line_no + x) & 8'hff;
g = (8'h40 + x*3) & 8'hff;
b = (8'h80 + line_no*5 + x) & 8'hff;
pattern = {r, g, b};
```

并新增 **CASE-GOLDEN** 固定字面值检查，避免 golden generator 自身再次出现宽度错误：

```text
pattern(10,0) == 0x0A40B2
pattern(10,1) == 0x0B43B3
```

因此 P0-05 必须重新跑完整 CASE0~CASE8；旧的 `PASS (checks=2202)` 不再作为 `[U]` 依据。

## 实测回归结果（2026-08-31）

修复 golden width 后重新执行：

```text
CASE-GOLDEN + CASE0~CASE8 全部通过
PASS: line_buffer_pingpong all adversarial cases passed (checks=2204)
```

波形复核：

```text
line=10, x=0
fill_data  = 0x0A40B2
pixel_data = 0x0A40B2
bank0[0]   = 0x0A40B2
```

因此 P0-05 正式达到 `[U] UNIT PASS`。
