# P0-05 / P0-06 回归归档

该文件保留 P0-05/P0-06 一轮开发/修复历史，最终状态以当前项目状态表为准。

## 最终实测

### P0-05 `line_buffer_pingpong`

首轮 TB 虽 PASS，但发现 `pattern()` 中 32-bit integer 拼接导致 96→24 bit 截断，只真正校验 B 通道。修复为显式 8-bit R/G/B，并增加固定 `CASE-GOLDEN` 后重新完整回归：

```text
CASE-GOLDEN + CASE0~CASE8 PASS
PASS: line_buffer_pingpong all adversarial cases passed (checks=2204)
```

波形确认：

```text
fill_data  = 0x0A40B2
pixel_data = 0x0A40B2
```

最终状态：`[U]`。

### P0-06 `line_prefetcher`

```text
CASE0~CASE13 PASS
PASS: line_prefetcher all adversarial cases passed (checks=2713)
```

覆盖多 outstanding、有序 response、timeout、unexpected response 和 stale-response quarantine。

最终状态：`[U]`。

## 后续

P0-07：`sdram_arbiter` candidate。  
P0-08：`mock_sdram + framebuffer mini-chain` integration candidate。

即使 P0-08 通过，完整 FAT32→BMP→framebuffer→display-order RGB 主链仍需下一轮端到端 `[C]` 验证。
