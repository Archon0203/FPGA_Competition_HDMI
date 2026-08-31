# sim_tb/framebuf

对应 `src/framebuf` 的 unit/adversarial/integration testbench：

```text
tb_async_fifo.v               + run_async_fifo.do               # [U]
tb_framebuffer_writer.v       + run_framebuffer_writer.do       # P0-03 [U], checks=1345
tb_frame_buffer_manager.v     + run_frame_buffer_manager.do     # P0-04 [U], checks=166
tb_line_buffer_pingpong.v     + run_line_buffer_pingpong.do     # P0-05 [U], checks=2204
tb_line_prefetcher.v          + run_line_prefetcher.do          # P0-06 [U], checks=2713
tb_sdram_arbiter.v            + run_sdram_arbiter.do            # P0-07 candidate
tb_framebuffer_mock_chain.v   + run_framebuffer_mock_chain.do   # P0-08 integration candidate
mock_sdram.v                                                      # simulation-only memory model
```

当前已有 **33 个 ModelSim testbench PASS**。新增 P0-07/P0-08 后工程共有 **35 个 `tb_*.v`**。

从 `sim_work/` 运行本轮 candidate：

```powershell
vsim -c -do ../sim_tb/framebuf/run_sdram_arbiter.do
vsim -c -do ../sim_tb/framebuf/run_framebuffer_mock_chain.do
```

预期验收字符串：

```text
PASS: sdram_arbiter all adversarial cases passed (...)
PASS: framebuffer mock chain all integration cases passed (...)
```

P0-08 若 PASS，只能证明 framebuffer/mock-memory sub-chain；完整 FAT32→BMP→display media chain 仍需下一轮端到端回归。
