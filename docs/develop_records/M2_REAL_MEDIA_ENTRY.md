# M2 真实媒体双板第一闭环入口

> **记录性质：M2 入口/执行记录，不是当前状态权威。当前状态只看 `docs/03_plan_and_status.md`。**
> 2026-10-04 更新：Slave 本地真实 TF/BMP 首图已经真板通过；真实媒体双板 NEXT/PREV/轮播仍未通过，DUALCTRL2 FIX1 尚待重新综合、仿真和上板。


## 1. M2 的唯一目标

M2 不再继续扩展 M1 的 Slave-HDMI pattern demo。M2 要完成第一次真正的多媒体双板闭环：

```text
Slave TF
 -> SPI SD
 -> FAT32/catalog
 -> BMP parser/pixel stream
 -> Slave cache/prefetch
 -> packet/CRC/sequence/credit
 -> inter-board data plane
 -> Master RX/CDC/FIFO/line-or-tile buffer
 -> Master HDMI rollback pipeline
 -> 显示器出现真实 BMP
```

第一规格允许 640×480，目的是把“真实媒体事务 + 板间数据 + Master display owner”一次做通；所有接口必须直接可扩展到 M3/M4 的 1080p，不做一次性 640×480 私有协议。

## 2. 最终职责冻结

### Slave（媒体生产板）

负责：

- TF/SPI；
- FAT32 mount / root catalog；
- BMP 与后续 vseq/video reader；
- source SDRAM/cache/prefetch；
- descriptor/status/epoch；
- line/tile packetization；
- CRC/sequence/credit；
- 数据面 TX；
- 对 Master 命令作 READY/BUSY/DONE/ERROR 响应。

Slave 不拥有最终 HDMI raster，不直接提交 Master front/back，也不做最终 OSD/字幕/转场。

### Master（最终显示板）

负责：

- 用户输入与播放状态；
- 控制面 coordinator；
- 数据面 RX、CDC、CRC/sequence 检查；
- FIFO/line/tile buffer；
- frame-boundary commit / fallback；
- scaler、亮度/对比度、OSD/Logo/字幕、transition；
- HDMI audio / audio visualization；
- 最终 1920×1080 raster、APUG092/PHY 和 HDMI 输出。

## 3. M2-A / M2-B / M2-C

### M2-A：真实媒体源

1. 把 `sd_spi/sd_reader/fat32_scan/fat32_file_reader/bmp_parser/bmp_pixel_stream` 接回 M1A service contract；
2. 至少识别 4 张合法 BMP；
3. 正确处理 fragmented FAT、24-bit BI_RGB、bottom-up/padding；
4. 错 header、短读、卡超时返回 ERROR，不输出“半个合法 frame”；
5. 输出 descriptor + line/tile payload，不让 C 线读 FAT 内部状态。

### M2-B：先物理数据面，再真实媒体

顺序不能倒：

```text
B0 pin map/cable freeze
 -> B1 low-speed PRBS + CRC + sequence
 -> B2 sustained PRBS + backpressure/credit
 -> B3 line/tile packet
 -> B4 one real BMP frame
 -> B5 continuous slideshow
```

控制面可继续保留已通过的 UART 作为 debug/bring-up；正式控制 SPI 可并行开发。原始像素不能走 115200 UART。

### M2-C：Master display owner 回归

1. 先保持 P1-05A 640×480 HDMI rollback 完全可用；
2. 新链路断开时显示 fallback，不黑屏；
3. 收到完整合法 frame 后，只在 frame boundary 切换；
4. KEY2/KEY3/KEY4 的高层语义保持与 M1 相同，但画面输出改到 Master HDMI；
5. link/CRC/underflow 状态用 LED/OSD 可视化。

## 4. 每块板独立验证顺序

### Slave-alone

- 50 MHz/reset/TF init 正常；
- catalog count/descriptor 可通过 LED、UART status 或 test register 观察；
- 读取 4 张 BMP 的尺寸/CRC/行数正确；
- 数据面在无 Master 时不得死锁，credit timeout 有明确状态。

### Master-alone

- P1-05A rollback HDMI 正常；
- link 未建立时 fallback 画面正常；
- RX/FIFO reset 后为空；
- KEY 操作不会阻塞 HDMI。

### Dual-control

- UART/SPI 控制命令与 M1 相同；
- OPEN/NEXT/PREV/PLAY/PAUSE/STATUS 正常；
- 双板异步 reset 后能重新 discovery。

### Dual-data

- 先 PRBS、再 line packet、最后真实 BMP；
- CRC 错/sequence 错/丢包不得提交半帧；
- credit/backpressure 不能造成 silent overwrite。

## 5. M2 完成判据

M2 只有同时满足以下条件才关闭：

```text
[C] 真实 TF/FAT32/BMP -> packet -> Master display chain 可复现
[S] Master/Slave 两角色 TD6.2.1 final STA setup/hold 0 violation
[B] 显示器接 Master HDMI，真实 TF 图片能稳定显示/切换
[B] 错包/断链时保持上一帧或 fallback，不出现半帧污染
```

M2 不要求最终 1080p PHY；但 M2 的 packet/credit/CDC/line-tile 结构必须直接进入 M3 的 1080p 等效吞吐压力。

## 6. M2 后续到最终 1080P

```text
M2  640×480 real-media dual-board first loop
 -> M3 1080p packed-YUV422 equivalent data-plane + 148.5/742.5 feasibility
 -> M4 real 1920×1080 still image + scaler/OSD/parameter overlay
 -> M5 1080p video + transition + HDMI audio + audio visualization
 -> M6 long-run / fault recovery / final demonstration
```

720p 只用于诊断，不作为最终或必经节点。


## 7. 2026-10-04 执行状态更正

M2 入口目标没有改变，但执行过程中先取得了一个必要的 Slave-alone 子门禁：

```text
TF -> SPI SD -> FAT32/catalog -> BMP -> Slave SDRAM -> Slave 640×480 HDMI
```

CMD17 command 尾字节固定 end bit 由 `8'h00` 修正为 `8'h01` 后，插卡复位可以从黄色加载页进入真实 BMP；无卡复位进入 fault。该现象只记为 **local `[B] PASS`**，不能把 M2 整体关闭。

随后将 M1 控制面接入真实媒体时，真板出现“约每几秒画面扰动但图片不变、NEXT/PREV 多数不能稳定切换”的反例。由此确认：

- `OPEN/ACCEPTED` 只能表示命令已排队，不能表示整张图片完成；
- real-media NEXT/PREV/PLAY/PAUSE/carousel 当前不得写 PASS；
- DUALCTRL2 的 STATUS/DONE 完成门控属于修复候选；
- FIX1 补齐 `source_valid` 接口后仍需重新取得编译、Questa、final STA 和真板证据。

M2 只有在真实 TF 图片经双板媒体数据面到 Master，并在 Master HDMI 上稳定切换/轮播后才能关闭。
