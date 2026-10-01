# M1ABC board PASS and M2 entry — 2026-10-01

## Board result

The M1ABC visible integration was tested on two HX4S20C boards and behaved as designed. Master keys and automatic rotation changed the Slave HDMI pages; link indication was present; fault indication stayed clear. The proven wiring is J1-8/J13 TX -> peer J1-4/F13 RX in both directions plus J1-12 GND.

This closes the **board functional gate** for M1ABC. It does not claim 1080p HDMI or the future source-synchronous media data plane.

## Role transition after M1

M1 intentionally used Master-control -> Slave-HDMI to make the control/service/frame-commit path visible. M2 restores the final product ownership:

- Slave: TF/FAT32/BMP/vseq, media cache/prefetch, packet producer.
- Master: data RX/CDC/buffer, scaler/effects/OSD/audio, final HDMI and 1080p raster.

## Evidence caveat

The previous `run_all.bat` did not execute successfully in the user's environment. This release rewrites the Questa 10.7c runner and includes all seven intended tests, but does not pre-claim an aggregate PASS until the team reruns it. The user confirmed TD synthesis/bitstream generation and successful board operation; final per-role STA values should be archived separately before assigning full `[S]`.
