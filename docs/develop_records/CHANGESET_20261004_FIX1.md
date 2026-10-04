# M2 DUALCTRL2 compile fix 1 — 2026-10-04

## Symptom

Tang Dynasty synthesis stopped while analyzing `src/dual_board/m2_real_media_uart_bridge.v`:

- `ERROR: 'source_valid' is not declared ... (51)`
- the module was ignored because of the previous error
- source analysis failed

## Root cause

DUALCTRL2 changed the bridge STATUS logic so that a completed image remains visible as
`STATUS_DONE` after the one-cycle `source_done` pulse.  The expression used a persistent
`source_valid` signal, but that signal was accidentally omitted from the bridge module port
list and from its instantiations.

The existing Slave top already has the intended persistent state: `media_succeeded`.
It is cleared when a new dispatched OPEN starts and set when the real media service pulses
`media_done`, so it is the correct signal to expose to the UART bridge.

## Fix

- Added `input wire source_valid` to `m2_real_media_uart_bridge`.
- Connected `.source_valid(media_succeeded)` in `m2_slave_tf_hdmi_top`.
- Added `source_valid` to `tb_m2_real_media_uart_bridge`.
- Extended the bridge TB to check that STATUS still reports DONE when `source_done=0`
  but `source_valid=1`.

No TF/SPI/FAT32/BMP/SDRAM/HDMI datapath logic was changed by this compile fix.

## Static checks performed in the handoff environment

- bridge module ports: 27
- Slave-top named connections: 27/27, no missing/unknown ports
- bridge-TB named connections: 27/27, no missing/unknown ports
- `FPGA_Competition_HDMI_MASTER.al`: 21 source entries, no duplicates/missing files, CRLF OK
- `FPGA_Competition_HDMI_SLAVE.al`: 64 source entries, no duplicates/missing files, CRLF OK

QuestaSim and TD are not installed in the handoff environment, so synthesis/simulation PASS
must still be confirmed on the project machine.
