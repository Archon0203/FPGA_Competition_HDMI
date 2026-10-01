# M1ABC-v5 implementation record · 2026-10-01

## Scope

This change intentionally advances **M1 only**. It does not claim real TF media, a physical wide data plane, or 1080p HDMI board closure.

## Prior evidence carried forward

- Correct UART RX sample timing was proven in simulation and then used in the real two-board 115200 control-link test.
- Real wiring proven on the supplied HX4S20C boards:
  - local TX = FPGA J13 = J1-8;
  - local RX = FPGA F13 = J1-4;
  - GND = J1-12.
- Stage-2 framed UART test: four command/ACK classes passed Questa (`masks=1111/1111`) and real-board bidirectional communication.

## New RTL

### A line

- `src/storage/m1a_uart_service_bridge.v`
  - adapts the board-proven UART control transport to the existing M1A media-service command/status contract;
  - PING is handled locally;
  - OPEN/SET_FORMAT/CREDIT/NEXT/PREV/PLAY/PAUSE/ABORT/STATUS are forwarded to `m1a_media_service_mock`;
  - response payload returns status, selected image, catalog count and error.

### B line

- `db_ctrl_frame_tx/parser`: payload-capable UART control frames, CRC8 poly 0x07.
- `m1b_line_packetizer/checker`: transport-independent line packet with frame/line/image/sequence and CRC16-CCITT.
- `m1b_prbs31` + `m1b_packet_selftest`: synthesizable packet contract self-test.
- `hdmi_1080p_raster`: 1920×1080 / 2200×1125 canonical raster contract with positive sync polarity. Clock generation is intentionally not included here.

### C line

- `m1c_coordinator_uart`: catalog discovery + OPEN/ACK/status/error/timeout.
- `m1c_frame_config_cdc`: stable mailbox committed only at frame boundary.
- `m1c_axis_pattern_mux`: four deterministic HDMI pages plus link/fault visual markers.

### Integration

- `m1abc_master_control_top`: KEY2 next, KEY3 previous, KEY4 play/pause automatic rotation.
- `m1abc_slave_hdmi_top`: A service + B packet self-test + C frame-boundary page selection on the P1-04C board-proven 640×480 HDMI_B boundary.
- `m1abc_slave_control_core`: simulation wrapper without protected HDMI vendor IP.

## Verification delivered

`sim_tb/m1abc/run_m1abc.bat` runs four tests:

1. packet/PRBS/sequence/CRC contract;
2. frame-boundary configuration CDC;
3. full 1080p canonical raster geometry/sync widths;
4. two independent-clock Master↔Slave control/A-service integration.

No local Questa/TD executable is available in the build environment used to prepare this patch. Therefore these tests are **delivered but not locally claimed PASS**; the team must run them with QuestaSim 10.7c and TD6.2.1.

## TD projects

- `td_m1abc/M1ABC_MASTER_TD621`
- `td_m1abc/M1ABC_SLAVE_HDMI_TD621`

The `.al` layout follows the native format already proven to open in TD6.2.1 (literal `UsedInP&R`, CRLF, no BOM, project Version 3/Minor 2). Each role is self-contained and references no parent directory.

## Architectural note

The M1 board demo intentionally uses **Master control -> Slave HDMI** because it makes the control-plane integration directly observable on the user's monitor. This does not silently rewrite the final ownership in `docs/01`: M2/M4 may still place final HDMI on the architecture-defined output board. If the team later decides to permanently invert final roles, that must be an explicit architecture change, not an accidental consequence of this bring-up harness.
