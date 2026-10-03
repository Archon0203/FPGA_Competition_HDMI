# M2 TF board PASS + Master control integration, 2026-10-03

## 1. Confirmed board milestone

The Slave real-media path has now produced a real TF-card image on the HX4S20C / EG4S20BG256 board:

```text
TF card
 -> SD SPI
 -> FAT32 catalog/file reader
 -> 640x480 24-bit BMP decode
 -> media write CDC
 -> APUG011/internal SDRAM
 -> line prefetch/buffer
 -> HDMI_B
 -> real image on monitor
```

Observed sequence with the card inserted was **yellow loading page -> real BMP image**. With the card absent, reset produced the red error page. Inserting the card and resetting again restored the image. This is M2-A Slave-alone `[B] PASS`; it is not yet the complete M2 dual-board media-data closure because HDMI is still owned locally by the Slave in this bring-up profile.

The DIAG5 CMD17 command-frame correction (`CRC/end byte 0x00 -> 0x01`) is therefore board-confirmed on the tested card.

## 2. Post-success LED observation and follow-up bug

After the first image appeared, the eight-LED row was observed as LED6+LED7+LED9+LED10+LED11 = `0x3B`, while the four-LED row still had the fault indicator asserted. The displayed image proved that at least one transaction had completed successfully.

Review of `m2_slave_tf_hdmi_top` found a deterministic control bug: `media_done` clears `media_load_requested`, and the old standalone fallback interpreted the next idle cycle as a reason to issue another automatic `OPEN(0)`. Therefore the top could repeatedly reload image 0 forever. A later redundant load could fault while the already-completed image remained visible, explaining the apparently contradictory “image displayed + fault code” state.

This package fixes the policy:

- standalone mode may automatically load image 0 **once** after reset/card recovery;
- `ctrl_link_seen` permanently disables standalone autoload until the next reset;
- remote `OPEN(image_id)` requests are queued while TF/BMP is busy and take ownership of subsequent selection;
- if the requested image is already a valid displayed frame, the Slave returns DONE without re-reading the same BMP; this prevents Master discovery from immediately reloading standalone image 0;
- a standalone failure may re-arm the one-shot load only when no Master has ever been seen.

## 3. Master control behavior

The active Master project remains:

```text
FPGA_Competition_HDMI_MASTER.al
TOP = m1abc_master_control_top
```

The active Slave project remains:

```text
FPGA_Competition_HDMI_SLAVE.al
TOP = m2_slave_tf_hdmi_top
```

Master commands are carried by the board-proven framed UART control plane. The response payload continues to expose status, selected image, catalog count and error byte. Pixels do **not** travel over UART.

Controls:

```text
KEY2 = NEXT
KEY3 = PREV
KEY4 = PLAY / PAUSE
automatic slideshow = 5 s
```

The old 2 s slideshow period was shorter than the comfortable budget for a ~921 KiB RGB24 BMP at the current SD SPI settings. Five seconds is used for this board-control gate so a normal load can finish before the next automatic intent.

## 4. Physical wiring

Power both boards normally through their own board power/USB connections. With both boards powered off while wiring:

```text
Master J1-8  / FPGA J13 / TX -> Slave  J1-4  / FPGA F13 / RX
Slave  J1-8  / FPGA J13 / TX -> Master J1-4  / FPGA F13 / RX
Master J1-12 / GND            <-> Slave J1-12 / GND
```

Do not connect the two boards' 5 V rails together. The TF card remains in the Slave.

## 5. Card content requirement for visible switching

The Master wraps selection modulo `catalog_count`. Therefore a card with only one recognized BMP will correctly accept NEXT/PREV/auto commands but always resolve back to image 0, making the monitor appear unchanged. For this gate prepare at least two, preferably four, supported files:

- FAT32 volume/profile already proven by the current scanner;
- files in the root catalog scope supported by the current implementation;
- short-name `.BMP` entries;
- 640×480;
- 24-bit `BI_RGB`;
- positive height/bottom-up.

## 6. Expected LEDs during dual-control

Slave four independent LEDs (active high):

```text
LED1 = catalog_valid
LED2 = media_busy
LED3 = successful media transaction AND frame_ready_sdr
LED4 = media/SDRAM fault
```

After a clean completed load and while idle, expected state is LED1+LED3 on, LED2+LED4 off. LED3 being somewhat dimmer than another physical LED is not by itself a protocol indication if the logical state remains steady; all four outputs use the same 8 mA drive setting.

Slave eight-LED row keeps the DIAG5 convention: no fault is `0x81` (LED6 + LED13); a fault displays the exact byte.

Master four LEDs:

```text
LED1 = ACK activity toggle
LED2 = link_ok
LED3 = accepted remote image-change toggle
LED4 = control fault
```

The key board gate is Master LED2 on and Master LED4 off after discovery.

## 7. Verification added in this package

- `tb_m2_real_media_service.v` now performs two consecutive good OPEN/load transactions before the intentional bad-BMP test. This protects repeated-load/slideshow re-entry.
- `tb_m2_real_media_uart_bridge.v` now checks that a valid OPEN is still ACKed/queued while the source is busy.
- `tb_m2_master_real_control_link.v` + `run_m2_master_real_control_link.do` exercise the actual Master coordinator over UART against `m2_real_media_uart_bridge`, with a 4-entry real-media-style catalog; preloaded image 0 is deduplicated, then automatic OPEN reaches 1→2→3.

This execution environment does not contain QuestaSim 10.7c or TD6.2.1, so the new regression and new routed reports are not claimed PASS here. Run them locally before/alongside board programming.

## 8. Timing/resource evidence carried forward

The most recently archived routed Slave result before this control-policy edit is DIAG4:

```text
SWNS +0.659 ns
STNS 0.000 ns
HWNS +0.014 ns
HTNS 0.000 ns
STA coverage 99.53%
```

The most recently archived routed area was about 13.1k LUT / 19.6k. Any new Master/Slave bitstream must still run full synthesis -> P&R -> final STA -> BitGen. The next resource cleanup target remains `line_buffer_pingpong`, which is being implemented as thousands of LUTs despite large unused BRAM capacity.

## 9. Status boundary

What is now proven:

```text
M2-A Slave real TF/BMP local HDMI [B] PASS
M1 UART control transport [B] PASS
```

What this package prepares but still needs board confirmation:

```text
Master real catalog discovery
Master KEY2/KEY3/KEY4 -> Slave OPEN(image_id)
5 s automatic slideshow across real BMPs
```

What remains outside this gate:

```text
source-synchronous high-speed media data plane
real frame transfer Slave -> Master
Master dynamic framebuffer/HDMI ownership
full M2 [C]/[S]/[B] closeout
```
