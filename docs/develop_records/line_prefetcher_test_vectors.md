# P0-06 `line_prefetcher` Test Vector 说明

> TB：`sim_tb/framebuf/tb_line_prefetcher.v`  
> 当前状态：candidate，等待实际 ModelSim PASS。

Memory model：

- request `ready` 可随机拉低；
- response 保持 accepted-request 顺序；
- 每个 response 带随机 0..7 cycle head latency；
- 允许连续 response；
- 记录最大 outstanding depth，CASE2 必须实际出现 `>1` outstanding。

| Case | 场景 | 目的 |
|---|---|---|
| CASE0 | base=100, width=4, line=0 | 精确地址、RGB response 转发 |
| CASE1 | `lb_fill_ready=0` 延迟后释放 | 未获得 bank 前禁止发 memory request |
| CASE2 | width=640 + random ready/latency | baseline 全行 + multiple outstanding + stall |
| CASE3 | 640×480 最后一行 line=479 | 首地址 `479*640`、末地址 307199 |
| CASE4 | `line_index >= frame_height` | 配置拒绝，无 memory/line-buffer 副作用 |
| CASE5 | stride<width / base 非 4-word 对齐 | 配置边界 |
| CASE6 | line buffer 永远无 free bank | allocation timeout，不需要 release 未分配 bank |
| CASE7 | memory request 永远不 ready | bank 已分配后的 timeout，必须 failed-completion 释放 |
| CASE8 | request accepted、response 永不返回 | outstanding response timeout + failed fill release，并置 `recovery_required` |
| CASE9 | CASE8 后直接 restart | stale-response quarantine 必须拒绝；不得发新 request；reset 后解除 |
| CASE10 | zero-outstanding 时注入 `mem_rvalid` | unexpected response 必须失败，不能转发垃圾 pixel |
| CASE11 | busy 时第二次 start | protocol failure + release |
| CASE12 | 21-bit address overflow | 在发请求前拒绝 |
| CASE13 | 可恢复错误后正常小行 | 无全局 reset 正常恢复；`recovery_required=0` |

Golden 不复制 DUT 状态机：accepted request address 单独记录；memory data 由 `mem_word(address)` 生成，line-buffer payload 通过独立 `mem_rgb(address)` 比较。

验收字符串：

```text
PASS: line_prefetcher all adversarial cases passed (...)
```

实际 PASS 后只标 P0-06 `[U]`，仍不能把 framebuffer/display chain 标为 `[C]`。

## 实测回归结果（2026-08-31）

```text
CASE0~CASE13 全部通过
PASS: line_prefetcher all adversarial cases passed (checks=2713)
```

首个 accepted read 抽查 `mem_rd_addr=100`，与 CASE0 预期一致；stale-response quarantine、outstanding、timeout 与 error path 均通过。

因此 P0-06 正式达到 `[U] UNIT PASS`。
