# P0-07/P0-08 实测同步 + P0-09 Candidate

## 已实测

### P0-07 `sdram_arbiter`

```text
CASE0~CASE8 PASS
PASS: sdram_arbiter all adversarial cases passed (checks=39)
```

状态：`[U]`。

### P0-08 framebuffer/mock-memory sub-chain

```text
CASE-GOLDEN + CASE0~CASE3 PASS
PASS: framebuffer mock chain all integration cases passed (checks=1495)
```

状态：`[C-sub]`。

`[C-sub]` 只表示：

```text
manager/writer -> arbiter/mock -> prefetch/linebuffer -> display RGB
```

已经闭环，不表示完整媒体链 `[C]`。

## 新增 P0-09

```text
sim_tb/integration/tb_p0_media_chain.v
sim_tb/integration/run_p0_media_chain.do
docs/32_p0_media_chain_end_to_end.md
docs/33_p0_media_chain_test_vectors.md
```

P0-09 在 ModelSim 未实跑前保持 candidate。

## TangDynasty `.al`

P0-09 只新增 integration TB，没有新增 synthesizable RTL，因此 `.al` 不加入 TB/mock 文件。已核对冻结 P0 的七个正式业务 RTL 均在 `<Source_Files><Verilog>` 中。
