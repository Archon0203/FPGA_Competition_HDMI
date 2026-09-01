# P0-03 `framebuffer_writer` Test Vector 说明

> Testbench：`sim_tb/framebuf/tb_framebuffer_writer.v`  
> 当前状态：**[U] UNIT PASS（2026-08-31）**。
> 实测结果：CASE0~CASE8 全部通过，`PASS: framebuffer_writer all adversarial cases passed (checks=1345)`。

## 1. Golden 原则

TB 不使用 SDRAM controller，而是提供独立的 abstract memory sink：

```text
mem_wr_valid / addr / data
            ↓
    ready/stall model
            ↓
       accepted log
```

只有：

```text
mem_wr_valid && mem_wr_ready
```

才记录一次实际写事务，然后与 `expected[]` 对比。

重点不是看 DUT 内部状态机，而是核对最终可观察结果：

- write count；
- 每次 write address；
- 每次 `0x00RRGGBB` data；
- `done/ok/overflow`。

## 2. Candidate CASE

| Case | 内容 | 预期/目的 |
|---|---|---|
| CASE0 | 2×2，输入坐标顺序为 bottom-up；base=100、stride=640 | 地址应为 740/741/100/101；验证坐标寻址 + `0x00RRGGBB` |
| CASE1 | 640×1 baseline，bounded random `mem_wr_ready` stall | 640 笔写全保留、顺序正确、无 overflow |
| CASE2 | memory 完全 stall 时先输入 4 pixels，再 `source_done` | `done` 必须等待 FIFO drain，不能提前完成 |
| CASE3 | width=2 时输入 `x=2` | 坐标非法，该 pixel 不写，本帧 `ok=0` |
| CASE4 | 合法 pixel 后 `source_ok=0` | pending write 可正常 drain，但最终失败 |
| CASE5 | `stride < width` | start 即失败、0 write |
| CASE6 | `frame_base` 非 4-word 对齐 | start 即失败、0 write |
| CASE7 | memory 永久 stall，source 故意无视 `pixel_ready` 连发超过 FIFO depth | `overflow=1`、本帧失败；FIFO 中旧数据不得被覆盖 |
| CASE8 | CASE7 之后不 reset，启动新 1×1 帧 | 新帧成功，证明 transaction 可独立重启 |

## 3. 关键地址向量

CASE0 采用显式固定值，而不是从 DUT 公式复制 golden：

```text
base = 100 words
stride = 640 words

pixel (0,1) -> 740
pixel (1,1) -> 741
pixel (0,0) -> 100
pixel (1,0) -> 101
```

这会直接抓住：

- 忽略 `pixel_y`；
- 误把 byte address 当 word address；
- bottom-up 坐标处理错误；
- 行 stride off-by-one。

## 4. 建议 Codex 运行

在项目 `sim_work/`：

```text
vsim -c -do ../sim_tb/framebuf/run_framebuffer_writer.do
```

验收输出必须是：

```text
PASS: framebuffer_writer all adversarial cases passed (...)
```

若 FAIL，**不要把模块标 `[U]`**；保留 transcript/首个 ERROR 交回修改。
