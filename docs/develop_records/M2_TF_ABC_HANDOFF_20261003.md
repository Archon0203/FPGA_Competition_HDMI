# M2 TF/BMP 640x480 ABC handoff — 2026-10-03

> **开发过程/候选记录：保留当时的现象、推断和修复方案，不作为当前 PASS 状态权威。当前状态以 `docs/03_plan_and_status.md` 为准。**


## Goal of this handoff

This patch keeps the current M2 board-first gate deliberately narrow:

```text
Slave TF -> FAT32 catalog -> 640x480 RGB24 BMP -> write CDC -> APUG011 SDRAM
         -> P1-05A 640x480 scanout -> Slave HDMI

Master KEY/coordinator <-> proven framed UART control/status <-> real Slave catalog
```

The local Slave HDMI path is still a hardware isolation gate. Raw pixels are **not** sent over the UART. The source-synchronous dual-board media PHY remains a later gate after the TF/SDRAM path is stable.

## New/changed integration

### A line — real media

- `m2_slave_tf_media_core` remains the real TF/FAT32/BMP provider.
- `m2_real_media_uart_bridge` is new. It exposes the real `catalog_count`, busy/done/error status, and accepts `OPEN(image_id)` from the existing Master coordinator.
- OPEN is acknowledged when queued, not after the BMP finishes loading. This avoids the existing Master ACK timeout while the Slave is legitimately reading a ~921654-byte BMP.
- Standalone behavior is preserved: with no Master connected, the Slave automatically loads image 0 after a valid catalog appears.

### B line — framebuffer safety

- `m2_slave_tf_hdmi_top` now invalidates the published single-buffer frame at the start of every new media transaction.
- `frame_ready_sdr` is cleared by a toggle CDC at a new load and is asserted again only after `m2_media_write_cdc` reports `sdr_fenced`.
- `frame_write_error` is also cleared for a new load so a recovered transaction is not permanently blocked by a stale backend error.
- The HDMI mux drops back to the deterministic diagnostic page while the single framebuffer is being overwritten, then returns to framebuffer data only at the safe display boundary after warm-up.

### C line — real control/status

- Master project top remains `m1abc_master_control_top` so the previously board-proven KEY2/KEY3/KEY4 and framed UART rollback are preserved.
- The Slave M2 top now uses the same UART frame protocol instead of holding `uart_tx` idle.
- Master discovery PING receives the real catalog count. Master OPEN commands select real TF catalog entries.
- This is a real A/C control merge; it is **not** the final M2 high-speed pixel-data merge.

## Project allocation

### Master — `FPGA_Competition_HDMI_MASTER.al`

- Active top: `m1abc_master_control_top`.
- Owns C-line keys/coordinator and existing M2 B/C loopback contract checks.
- No raw media GPIO PHY is enabled yet.

### Slave — `FPGA_Competition_HDMI_SLAVE.al`

- Active top: `m2_slave_tf_hdmi_top`.
- Owns TF/FAT32/BMP, write CDC, APUG011 SDRAM, 640x480 local HDMI hardware gate.
- Adds `src/dual_board/m2_real_media_uart_bridge.v` to the active source list.

## Verification status

Existing QuestaSim 10.7c evidence already present in the uploaded working tree remains applicable to unchanged media subchains, including the real-media transcript that reports:

```text
PASS: m2_real_media_service checks=10
Errors: 0, Warnings: 0
```

The project also contains prior M2 regressions for no-card retry, FAT32 superfloppy/MBR, full 307200-pixel BMP, media-write CDC, line packet RX/store, full-frame stream and real-card snapshot replay.

New test delivered by this handoff:

```text
sim_tb/m1abc/run_m2_real_media_uart_bridge.do
sim_tb/m1abc/tb_m2_real_media_uart_bridge.v
```

It checks PING/real catalog response, queued OPEN, error status and bad-image rejection. The current Linux preparation environment does not contain `vsim/vlog`, so this new test and the modified board top were structurally checked here but cannot honestly be marked as a newly executed Questa PASS. Run the command below in the team's QuestaSim 10.7c environment before TD synthesis.

```powershell
cd D:\AnlogicProject\FPGA_Competition_HDMI\sim_tb\m1abc
run_m2_real_media_uart_bridge.bat
```

Then rerun the existing media gates most relevant to this change:

```powershell
cd D:\AnlogicProject\FPGA_Competition_HDMI\sim_tb\storage
vsim -c -do run_m2_no_card.do
vsim -c -do run_m2_slave_tf_media_core.do
vsim -c -do run_m2_media_write_cdc.do
vsim -c -do run_m2_bmp_640.do
```

## TD6.2.1 / board order

1. Build **Slave first** from `FPGA_Competition_HDMI_SLAVE.al` and inspect final STA. Do not ignore the previously observed internal-SDRAM hard-IP setup signature around `-7.098 ns`; this handoff does not claim it is fixed by source changes.
2. Program only the Slave and connect its HDMI. With a valid TF card it should scan the FAT32 root catalog, automatically load image 0, fence SDRAM writes, warm the line buffers and replace the diagnostic page with the BMP.
3. Record the four active-high LEDs **together with screen color** if it fails. On red, the low nibble maps the current media failure class/detail; do not report LEDs without the simultaneous screen color.
4. After Slave-alone passes, build/program Master from `FPGA_Competition_HDMI_MASTER.al`, connect only the proven crossed UART pair + GND, and verify Master link/cmd LEDs plus KEY image selection. No 40-pin pixel cable is needed for this local-HDMI gate.
5. Only after TF/SDRAM/local-HDMI is stable should the source-synchronous M2 media PHY be enabled and Master HDMI ownership migration continue.

## Expected TF image contract for this gate

- FAT32 MBR partition or FAT32 boot sector directly at LBA0;
- SDHC/block addressing;
- root directory entry discoverable by the current scanner;
- 8.3 `.BMP` entry;
- 640x480, 24-bit, BI_RGB, positive height/bottom-up;
- conventional 54-byte header is supported;
- one valid image is enough for the Slave-alone gate; multiple images are needed for Master NEXT/PREV demonstration.

## Remaining boundary

This package is an M2 TF/BMP board candidate, not M2 closeout. It does not claim fresh TD `[S]`, physical TF/HDMI `[B]`, final Master HDMI ownership, or a completed high-speed dual-board pixel link. Those claims require the user's TD6.2.1 synthesis/P&R/STA and board test.
