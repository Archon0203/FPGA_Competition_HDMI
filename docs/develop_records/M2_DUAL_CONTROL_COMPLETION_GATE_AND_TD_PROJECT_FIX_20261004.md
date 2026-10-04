# M2 dual-board control completion gate + TD project-file repair (2026-10-04)

> **开发过程/候选记录：保留当时的现象、推断和修复方案，不作为当前 PASS 状态权威。当前状态以 `docs/03_plan_and_status.md` 为准。**


## 1. Board observation entering this revision

The real TF path is already board-proven after the CMD17 end-bit repair:

`TF -> FAT32 -> 640x480 BMP -> Slave SDRAM -> Slave HDMI` displays a real image.

The first dual-control candidate did **not** pass repeated switching:

- automatic playback caused a visible disturbance every few seconds but usually kept the same picture;
- NEXT/PREV key presses usually produced only a display disturbance instead of a completed image change;
- removing the TF card, waiting, reinserting it and then pressing a Master key could allow one image change;
- therefore the failure is above the already-proven first-image TF/CMD17 gate and must not be debugged by reverting that fix.

## 2. Control-plane root cause

The Slave intentionally ACKs `OPEN(image_id)` with `M1A_STATUS_ACCEPTED` as soon as the request is queued.  Loading a real ~900 KiB BMP from TF is much slower than a UART ACK.

The previous Master coordinator treated that `ACCEPTED` ACK as if the image transaction were finished.  It immediately reasserted `media_cmd_ready`, so:

1. the 2 s slideshow timer kept running while the Slave was still reading/writing the previous image;
2. manual keys could generate more OPEN commands during the same transaction;
3. the Slave's one-entry "latest request wins" queue could be overwritten;
4. the single framebuffer was repeatedly hidden/re-published, producing the observed periodic disturbance without a reliable selection change.

This revision changes the contract without changing the wire format:

- `OPEN -> ACK(0x81, ACCEPTED)` means **queued only**;
- Master then periodically sends `STATUS(0x09)`;
- Slave returns `ACK(0x89)` with status, selected image and catalog count;
- Master keeps `media_cmd_ready=0` until the requested image is reported `DONE` (or stable `READY`) with matching `remote_selected_image`;
- only after that completion may the next manual/automatic OPEN be accepted;
- the slideshow counter advances only while the coordinator is actually idle.

The Slave real-media bridge now reports persistent `source_valid` as `DONE`, so STATUS polling cannot miss the one-cycle `source_done` pulse.

## 3. Existing repeated-frame fixes retained

This revision retains both fixes from the previous dual-control candidate:

- `m2_open_dispatcher`: standalone `OPEN(0)` is one-shot; after bootstrap, Master owns selection;
- `m2_media_write_cdc`: every media transaction has its own done toggle and one-cycle SDRAM fence pulse; fence is not sticky after frame 0.

The board-proven TF/CMD17 fix (`CMD17` tail byte `8'h01`) is also retained unchanged.

## 4. TD6.2.1 Slave project-file failure found in Git main

The user-provided local repository was inspected with its Git metadata.  The working archive is on `feature/TF` at commit `8b3f3d8`; its local `FPGA_Competition_HDMI_SLAVE.al` contains no duplicate source paths.

The repository's recorded `origin/main` (`8876c94`) contains five duplicated `<File Path=...>` entries in `FPGA_Competition_HDMI_SLAVE.al`:

- `src/dual_board/m2_media_line_source.v`
- `src/dual_board/m2_line_packet_tx.v`
- `src/dual_board/m2_line_packet_rx.v`
- `src/dual_board/m2_frame_commit.v`
- `src/dual_board/m2_abc_loopback_diag.v`

The Master `.al` does not have the same duplicate-source problem.  This asymmetry matches the report that Master opens normally while Slave triggers TD's "Unable to write the project file / Save As" dialog.  A branch merge appears to have duplicated those five Slave project entries.

This package therefore ships a de-duplicated Slave `.al` and preserves CRLF line endings.  `tools/check_td_project.py` audits duplicate project source paths and CRLF formatting before a project file is committed/merged.

Do not fix `.al` merge conflicts by concatenating both source-file blocks.  There must be exactly one `<File Path=...>` entry per source file.

## 5. Regression added

New Questa test:

`sim_tb/app/run_m1c_coordinator_realmedia.do`

It verifies:

1. PING discovers a catalog;
2. OPEN receives `ACCEPTED`;
3. `media_cmd_ready` remains low;
4. STATUS while busy keeps it low;
5. STATUS `DONE` with the requested image releases the next command.

Existing tests that remain relevant:

- `sim_tb/m1abc/run_m2_open_dispatcher.do`
- `sim_tb/m1abc/run_m2_real_media_uart_bridge.do`
- `sim_tb/storage/run_m2_media_write_cdc.do`
- `sim_tb/storage/run_sd_reader.do`

The packaging environment does not contain QuestaSim/TD6.2.1, so the new RTL is a candidate until these regressions and both TD builds are rerun by the user.

## 6. Board acceptance sequence

First validate Slave alone: one boot load only, stable image, no periodic self-reload.

Then connect the proven three-wire control link:

- Master TX (J13 / J1-8) -> Slave RX (F13 / J1-4)
- Slave TX (J13 / J1-8) -> Master RX (F13 / J1-4)
- J1-12 GND <-> GND

Recommended dual-board test:

1. power/reset both boards with TF inserted;
2. wait for Slave image 0 and Master link indication;
3. press PLAY/PAUSE once to pause automatic playback;
4. press NEXT once and wait for the complete new image;
5. repeat NEXT for at least three image changes, then PREV;
6. resume PLAY and verify one completed image change approximately every 2 s **after the preceding load has completed**.

A command is not considered successful merely because the screen briefly leaves the framebuffer page; the selected image must actually change and remain stable.
