# M2 Dual-Control Handoff — 2026-10-03

> **开发过程/候选记录：保留当时的现象、推断和修复方案，不作为当前 PASS 状态权威。当前状态以 `docs/03_plan_and_status.md` 为准。**


This package starts from the DIAG5 board-success baseline and preserves the verified CMD17 end-bit fix.

Active TD projects:

```text
Master: FPGA_Competition_HDMI_MASTER.al
Top   : m1abc_master_control_top

Slave : FPGA_Competition_HDMI_SLAVE.al
Top   : m2_slave_tf_hdmi_top
```

Board wiring (power off before wiring):

```text
Master J1-8  (J13 TX) -> Slave J1-4 (F13 RX)
Slave  J1-8  (J13 TX) -> Master J1-4 (F13 RX)
Master J1-12 GND       <-> Slave J1-12 GND
```

Do not connect 5 V between the boards.

Master controls:

```text
KEY2 NEXT
KEY3 PREV
KEY4 PLAY/PAUSE
Default play_en = 1, carousel period ~= 2 s at 50 MHz
```

New/updated control-safety logic:

```text
m2_open_dispatcher: one standalone OPEN(0), then Master-owned OPEN requests
m2_media_write_cdc: per-transaction done toggle and one-cycle SDRAM fence
m2_slave_tf_hdmi_top: do not accept next post-success OPEN until previous frame is fenced
```

Before board test run in QuestaSim 10.7c:

```text
sim_tb/m1abc/run_m2_open_dispatcher.do
sim_tb/storage/run_m2_media_write_cdc.do
sim_tb/m1abc/run_m2_real_media_uart_bridge.do
```

Then run TD6.2.1 synthesis -> P&R -> final STA -> BitGen separately for Master and Slave. The archived +0.659/+0.014 ns timing report in evidence belongs to the preceding DIAG4 build, not this modified candidate.
