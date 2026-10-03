# M2 ABC real-media RTL candidate, 2026-10-03

## Scope and ownership

- Slave A: `m2_slave_tf_media_core` connects the SD SPI sector cache to the FAT32 catalog and BMP framebuffer loader. The loader writes `0x00RRGGBB` words to an abstract SDRAM write port; `source_done` follows the accepted final write. `m2_frame_packet_source` reads a fenced frame in display order, buffers one line, and sends one CRC16/sequence packet per credited line.
- Master B: `m2_master_line_core` checks complete 640-word packets before releasing a line. `m2_master_frame_store` writes only the back buffer and publishes the new front base/image/frame ID at a synchronized display frame boundary. An error or incomplete frame cannot publish the candidate.
- C contract: existing `media_command_controller` and UART coordinator remain the M1 control baseline. The new Master core exposes `front_valid`, `front_image_id`, `commit_pulse`, `commit_error`, and `link_ready` for later UI integration; no new UI feature is claimed here.

The Master TD6.2.1 project retains the M1 control top. The Slave project now names m2_slave_tf_hdmi_top as the M2 TF-to-local-HDMI candidate and enables the required media/SDRAM sources. The candidate still needs TD synthesis/P&R/STA/BitGen and a real-card board test; Master dynamic HDMI and the dual-board data plane remain open.

## QuestaSim 10.7c evidence

| Regression | Result | Scope |
|---|---|---|
| `tb_sd_reader` | PASS, 8 checks | one initialization, two CMD17 reads, delayed R1/token, two CRC bytes |
| `tb_m2_slave_tf_media_core` | PASS, 4 sectors / 4 pixels | SPI bit model through FAT32/BMP, Slave write, line packet, Master commit |
| `tb_m2_real_media_service` | PASS, 10 checks | real catalog/parser/loader and packet path, bad BMP rejection |
| `tb_m2_bmp_640` | PASS, 307200 writes | complete 640x480 24-bit BMP, every pixel address/data checked |
| `tb_m2_line_packet_rx_640` | PASS, 3 accepted lines / 2 errors | 640-word line, backpressure, CRC and bad-length recovery |
| `tb_m2_stream_640_frame` | PASS, 307200 writes / 925691 cycles | 480 credited packets, readback to Master back buffer, frame-boundary front commit |
| `tb_m2_frame_packet_source_timeout` | PASS | absent Master credit exits busy and reports error |
| `tb_m2_master_frame_store` | PASS, 2 commits / 40 writes | partial frame retains previous front; missing-line recovery |
| `tb_m2_master_line_core` | PASS, 12 writes | packet RX to back-buffer/front metadata |
| existing `tb_p1_media_framebuffer_loader` | PASS, 225 checks | fragmented FAT BMP to cached APUG011 model |
| existing `tb_bmp_parser` | PASS, 8 checks | parser regression after widening file byte count |
| existing `tb_m2_abc_loop` | PASS | M2 diagnostic rollback |

The full-size BMP test caught a real 16-bit `bmp_parser.byte_idx` wrap after 64 KiB; it is now 24 bits. These are `[U]`/`[C-sub]` RTL results. The complete 640x480 media test uses a deterministic sector model; the bit-level SD card model uses a 2x2 BMP. No real TF card, routed design, or monitor was exercised here.

## Card preparation for board validation

- SDHC card with a FAT32 MBR partition (type `0x0B` or `0x0C`), 512-byte sectors, and BMP files in the root directory's first cluster. The current scanner does not traverse additional root-directory clusters or subdirectories.
- At least four short-name (`8.3`) `.BMP` files, each 640x480, 24-bit `BI_RGB`, positive height (bottom-up). The file reader follows fragmented FAT chains. A conventional 54-byte header image has a 921654-byte file size.
- Official example TF pins on HX4S20C are now assigned in the Slave ADC: SCLK A14, MISO B14, MOSI A13, nCS A12. The active Slave top is the M2 TF-to-local-HDMI candidate.

## Open gates

1. Only the three M1 UART/GND wires are available. Per `docs/01_architecture.md`, UART is a control channel and must not carry raw pixels. The 40-pin source-synchronous data cable/pin map, PRBS/CRC/credit board bring-up and CDC timing gate are pending.
2. Slave physical SDRAM write arbitration/readback fence and Master external SDRAM write/read integration remain to be connected. The RTL tests use synchronous memory models.
3. Master active top has no HDMI output. It must regain the P1-05A APUG011/APUG092 scanout with dynamic `front_base` and fallback before real playback can be tested.
4. Master C control/status/UI must consume real catalog and commit status rather than the M1 mock service. Four BMP files on a real card and KEY2/KEY3/KEY4 image selection have not been verified.
5. Both roles need fresh TD6.2.1 synthesis, P&R, final STA and BitGen after active top/constraints are changed, followed by separate board and dual-board tests. This candidate is **not** M2 `[C]`, `[S]`, or `[B]` closeout.


