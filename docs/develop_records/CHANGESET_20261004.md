# 2026-10-04 candidate changes

1. Master `m1c_coordinator_uart` now treats OPEN/ACCEPTED as queued-only and polls STATUS until the requested image is actually complete before accepting another media command.
2. Master slideshow counter advances only while the coordinator is idle, so TF load time does not consume the 2 s dwell interval.
3. Slave `m2_real_media_uart_bridge` maps persistent `source_valid` to DONE for reliable STATUS polling.
4. Retains the one-shot `m2_open_dispatcher`, per-frame `m2_media_write_cdc` fence, CMD17 end-bit fix and closed Slave SDC.
5. `FPGA_Competition_HDMI_SLAVE.al` contains each source exactly once and is stored CRLF. `tools/check_td_project.py` detects the duplicate-source merge defect found in recorded `origin/main`.
6. Added `sim_tb/app/run_m1c_coordinator_realmedia.do`.

This is a verification candidate: the packaging environment has no QuestaSim 10.7c or TD6.2.1 executable, so new regression/STA/board PASS must be produced on the team's Windows toolchain.
