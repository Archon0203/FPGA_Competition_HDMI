# P0-07 `sdram_arbiter` Test Vector 说明

> Testbench：`sim_tb/framebuf/tb_sdram_arbiter.v`  
> 状态：candidate，待实际 ModelSim 回归。

## 测试矩阵

| Case | 场景 | 关键预期 |
|---|---|---|
| CASE0 | idle | 无 memory command，outstanding=0 |
| CASE1 | 单 write | addr/data 原样透传，一次 accepted write |
| CASE2 | 单 read + delayed response | request accepted，outstanding 0→1→0，response 原样返回 |
| CASE3 | read/write 同时请求 | read wins；`wr_ready=0`；read 清除后 write 才继续 |
| CASE4 | read 下游 stall + writer 等待 | strict read priority，不允许 writer 绕过 stalled read |
| CASE5 | first read accepted + zero-latency response | 同拍 request/response 合法，outstanding 保持 0 |
| CASE6 | 3 个 outstanding read | outstanding 计数准确，3 个 response 后回 0 |
| CASE7 | unsolicited `mem_rvalid` | 不转发垃圾数据，sticky `protocol_error=1` |
| CASE8 | reset | sticky/debug counters 全部恢复 |

## 关键独立检查

CASE3 必须主动观察：

```text
wr_valid=1
rd_valid=1
mem_wr_ready=1
mem_rd_ready=1
```

期望：

```text
mem_rd_valid=1
rd_ready=1
mem_wr_valid=0
wr_ready=0
```

只有看到最终：

```text
PASS: sdram_arbiter all adversarial cases passed (...)
```

才可把 P0-07 标为 `[U]`。
