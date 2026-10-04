# M2 ABC implementation record

> **开发过程/候选记录：保留当时的现象、推断和修复方案，不作为当前 PASS 状态权威。当前状态以 `docs/03_plan_and_status.md` 为准。**


## Delivered RTL

- `src/dual_board/m2_media_line_source.v`: deterministic A-line source used for bring-up; catalog, descriptor, play/pause and credit handshakes are explicit.
- `src/dual_board/m2_line_packet_tx.v`: M2 wrapper around the reviewed line packetizer.
- `src/dual_board/m2_line_packet_rx.v`: packet header/CRC16/sequence validation and backpressure-safe line release.
- `src/dual_board/m2_frame_commit.v`: line ordering and complete-frame commit boundary.
- `src/dual_board/m2_abc_loopback_diag.v`: local A/B/C diagnostic used by the Master top.

## Verification evidence

QuestaSim 10.7c testbench `sim_tb/m1abc/tb_m2_abc_loop.v` passes normal frame submission, RX backpressure, CRC corruption recovery and reset recovery:

```text
PASS: m2 abc loop boundaries=1 errors_recovered=0
Errors: 0, Warnings: 0
```

The Master TD6.2.1 project opens and analyzes 15 sources and its routed implementation/BitGen completed. Final routed timing is SWNS `+8.123 ns`, HWNS `+0.223 ns`, with zero violating endpoints.

The Slave TD6.2.1 project opens and analyzes 27 sources. M2 source files are assigned to the Slave project but excluded from the frozen HDMI rollback top until the source-synchronous board pin map is frozen. The previously routed Slave rollback implementation remains available in `FPGA_Competition_HDMI_SLAVE_Runs/phy_1`; its final timing is SWNS `+0.671 ns`, HWNS `+0.003 ns`, with zero violating endpoints, and its BitGen output is copied to `m2_slave.bit`.

## Boundary

This milestone is the M2 RTL/loopback contract gate. It does not claim a real TF/FAT32/BMP provider, cross-board source-synchronous GPIO data plane, Master HDMI ownership migration, or 1920×1080 board validation. Those remain the next integration gates.
