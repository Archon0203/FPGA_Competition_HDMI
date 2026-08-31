# 14 · `fat32_file_reader` 测试向量与回归记录（P0-01）

> Testbench：`sim_tb/storage/tb_fat32_file_reader.v`  
> 运行脚本：`sim_tb/storage/run_fat32_file_reader.do`  
> 2026-08-31 实际 ModelSim 结果：**PASS，checks=18**。

## 1. Block-device model

当前 TB 使用自检的随机 stall block-device model：

- 每次 request 接受后随机等待 `0..7` cycle；
- 正常传输阶段约 75% cycle 给出一个 `din_valid` byte；
- 约 25% cycle 随机 stall；
- 每个 sector 结束后强制产生 `sector_ready=0` 的事务间隔；
- payload 使用确定性 pattern 填充，输出写入 `got[]` 后与独立 `golden[]` 逐 byte 比较。

因此 TB 不依赖“每拍必有 byte”的理想模型，可检测 stall 下重复/漏 byte、地址/边界 off-by-one 等问题。

## 2. 已执行 Case

| Case | FAT / 参数 | `file_size` | 预期 | 验证目的 |
|---|---|---:|---|---|
| CASE0 | zero-length | 0 | `ok=1`, 0 byte | 空文件无需 sector IO |
| CASE1 | 单 cluster 3 | 100 | `ok=1`, 100 byte | `<512B`；最终 sector padding 不输出 |
| CASE2 | 单 cluster 3 | 512 | `ok=1`, 512 byte | 恰好一个 sector，不需 FAT traversal |
| CASE3 | `3 → 4 → EOC`, SPC=1 | 513 | `ok=1`, 513 byte | 跨 sector / cluster 边界；连续 chain |
| CASE4 | `3 → 7 → 5 → EOC`, SPC=2 | 2050 | `ok=1`, 2050 byte | fragmented chain + multi-sector cluster |
| CASE5 | `3 → EOC`，但仍需 513B | 513 | `ok=0`, 已输出 512 byte | premature EOC |
| CASE6 | `FAT[3]=0` | 513 | `ok=0`, 已输出 512 byte | free/invalid next cluster |
| CASE7 | `127 → 130 → EOC` | 513 | `ok=1`, 513 byte | FAT entry offset=508 边界，检测错误 8-bit offset |
| CASE8 | `sectors_per_cluster=0` | 100 | `ok=0`, 0 byte | 非法参数立即失败 |

## 3. 实际 transcript

```text
CASE0 zero-length
CASE1 single cluster 100B
CASE2 exact 512B
CASE3 contiguous 513B
CASE4 fragmented SPC=2 2050B
CASE5 premature EOC
CASE6 invalid/free next cluster
CASE7 FAT offset=508 boundary
CASE8 invalid SPC=0
PASS: fat32_file_reader all adversarial cases passed (checks=18)
```

## 4. `[U]` 验收结论

上述实际回归足以将 `fat32_file_reader` 标记为 **[U] UNIT PASS**。

仍未覆盖/不能由本结果推出：

- 真 SD/TF 卡 `[B]`；
- `fat32_scan` 与本模块的真实集成 `[C]`；
- BMP 像素流与 framebuffer 链 `[C]`；
- TD synthesis/P&R `[S]`。

后续 P0-02 开始后，不应为了实现方便修改本模块已冻结的对外接口；若确需修改，先同步架构/接口文档并重新回归。
