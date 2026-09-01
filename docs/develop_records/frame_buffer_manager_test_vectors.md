# P0-04 `frame_buffer_manager` Test Vector 说明

> Testbench：`sim_tb/framebuf/tb_frame_buffer_manager.v`  
> 当前状态：**[U] UNIT PASS（2026-08-31）**。
> 实测结果：CASE0~CASE6 全部通过，`PASS: frame_buffer_manager all adversarial cases passed (checks=166)`。

## Candidate CASE

| Case | 激励 | 必须满足 |
|---|---|---|
| CASE0 | reset | front=A、back=B、两 base 不同、`load_ready=1`，且 `read_frame_valid=0` |
| CASE1 | load 640×480 → writer success → boundary | writer metadata=640×480；boundary 前 read 仍 A/invalid；swap 后 B valid 且 read metadata=640×480 |
| CASE2 | 写 320×240 时给 boundary 和第二次 load request | 不 swap；第二个 load 被拒绝；完成后 swap，read metadata=320×240 |
| CASE3 | 641×2 frame 的 `writer_done` 与 boundary 同拍 | 不立即 swap；下一 boundary 后 metadata 与 frame 一起原子切换 |
| CASE4 | writer failure | front base/valid/metadata 全部不变；失败 back invalid；可重试；产生 `load_fail_pulse` |
| CASE5 | failure 后直接重试 success | 无需全局 reset；下一 boundary 正常 swap |
| CASE6 | 连续多次完整 frame | A/B 所有权反复交换，任意时刻 `read_base != write_base` |

## 关键不变量

TB 会持续检查：

```text
read_base != write_base
```

以及：

```text
write_in_progress -> no swap
pending_swap      -> no new load accepted
writer failure    -> read_base unchanged
```

这些不变量比“最后 base 看起来对”更重要，因为它们直接对应无撕裂和禁止读写同 buffer。

## Codex 运行

在 `sim_work/`：

```text
vsim -c -do ../sim_tb/framebuf/run_frame_buffer_manager.do
```

验收必须看到：

```text
PASS: frame_buffer_manager all adversarial cases passed (...)
```

P0-04 已据本次实际回归标记为 `[U]`；双缓冲 manager 的单元 PASS 不等于 framebuffer chain `[C]`。

P0-03/P0-04 的 `[U]` 仍不代表 framebuffer/media chain `[C]`。当前 P0-05/P0-06 已 `[U]`；下一步是 P0-07 `sdram_arbiter` 与 P0-08 mock framebuffer sub-chain，再继续完整 FAT32/BMP 端到端回归。
