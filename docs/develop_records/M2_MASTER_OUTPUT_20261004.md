# M2 · 14 根杜邦线主板出图候选（2026-10-04）

当前状态以 `../03_plan_and_status.md` 为准。用户已确认上一候选轮播和切换完全正常；本记录的新候选把 HDMI 移到主板，尚待新接线真板验证。不要把上一候选的板级 PASS 继承给它。

## 今晚先做什么

1. 两板断电，按下表接 14 根线；TF 卡留在从板，HDMI 改接主板 HDMI_B（原来从板使用的同一个物理接口）。各板分别供电。
2. 同时更新两份 bitstream：`sim_work/m2_master_output/delivery/master.bit`、`slave.bit`。分别来自两个长期 `.al`，不用第三份工程。
3. 按住两板 KEY1，再先松主板、后松从板，保证请求/确认 toggle 从相同初态启动。主板应先出现“加载中”，随后显示 TF 第一张图片。
4. 主板 KEY4 暂停；KEY2 下一张、KEY3 上一张。至少 4 张现有合规 640×480 BMP 正反遍历，再恢复轮播 3 轮。
5. 主板 LED2 为 UART link，LED3 为实际图像已发布，LED4 为控制或显示故障；从板 LED1 catalog、LED2 读卡/传输 busy、LED3 主板完成显示、LED4 媒体错误。卡住时记录两板 LED 和主板画面，再一起复位。

两板都需更新，不能与旧 bit 混用。该候选依然是 640×480、加载页掩蔽的单缓冲；没有宣称无闪屏、任意单板热复位恢复或 1080p 已通过。

## 14 根线：逐针连接

> **FIX6 electrical correction (2026-10-05):** the earlier ball column for `data[3:5]` was wrong even though the literal J1 wire numbers were correct.  Schematic cross-reference `2_FPGA.pdf` + `4_GPIO.pdf` gives J1-5=`GPIOA_4`→GPIOA0/H13, J1-6=`GPIOA_5`→GPIOA16/H14, J1-7=`GPIOA_6`→GPIOA15/J14.  The old constraint put `data[3]` on L12/GPIOA20, which is routed through RN36 to connector net GPIOB_29 (J2-34), so a J1-only cable silently lost logical payload bit 3 while REQ/ACK still completed.  The table below and role ADC files are corrected in FIX6.


方向 M=主板、S=从板。除 UART 两根交叉，其余都同编号连接。**表中的 J1 是连接器物理针号，不是 GPIOA 数字。** 方焊盘/丝印 pin 1 定位后按原理图奇偶排数，不按照片上下猜。导线尽量短（本候选建议不超过约 20 cm），两个 GND 都接；不连接两板 5V/3V3。

| 根数 | 用途 / 方向 | 从板 J1 | 主板 J1 | FPGA 球位 / 片内网名 |
|---|---|---|---|---|
| 1 | UART M → S | 4 RX | 8 TX | M J13/GPIOA10 → S F13/GPIOA7 |
| 2 | UART S → M | 8 TX | 4 RX | S J13/GPIOA10 → M F13/GPIOA7 |
| 3 | GND | 12 | 12 | GND |
| 4 | GND | 30 | 30 | GND |
| 5 | data[0] S → M | 1 | 1 | D14 / GPIOA9 |
| 6 | data[1] S → M | 2 | 2 | G11 / GPIOA6 |
| 7 | data[2] S → M | 3 | 3 | G12 / GPIOA8 |
| 8 | data[3] S → M | 5 | 5 | H13 / GPIOA0 |
| 9 | data[4] S → M | 6 | 6 | H14 / GPIOA16 |
| 10 | data[5] S → M | 7 | 7 | J14 / GPIOA15 |
| 11 | data[6] S → M | 9 | 9 | K12 / GPIOA12 |
| 12 | REQ S → M | 10 | 10 | L14 / GPIOA24 |
| 13 | ACK M → S | 13 | 13 | M14 / GPIOA25 |
| 14 | DISPLAY_PUBLISHED M → S | 32 | 32 | L16 / GPIOA14 |

依据本地 `3_原理图/开发板原理图/4_GPIO.pdf` 与 `2_FPGA.pdf` 的交叉核对：例如 J1-32 为连接器 GPIOA_27，经 RN26 的 47Ω 电阻到片内 GPIOA14，再到 L16；不能把 GPIOA_27 误认成 GPIOA27。两板均为 LVCMOS33，复用的球位与 TF、HDMI_B、按键、LED 无冲突。引脚约束已写入 `constraints/master/master.adc`、`constraints/slave/slave.adc`。

## 通信与完成语义

今晚使用 7-bit bundled-data + REQ/ACK toggle 的可靠低速握手，UART 115200 保持原控制协议。此实现不使用 GPIO 作为外部时钟：发送端先寄存数据，再改变 REQ；接收端经过两级同步和额外一周期稳定等待后采样，ACK 前数据一直保持。最后一个分片只有被下游接收后才确认，因此 SDRAM 背压会传回 TF loader。

32-bit word 分为 5 个 7-bit 分片。帧流为 `BEGIN(image_id) → {地址, 像素}×307200 → END(image_id) → CRC32`。显式地址兼容 bottom-up BMP；CRC 覆盖 BEGIN、地址和像素，地址范围与总像素数检查通过后才允许 fence/发布。此版本没有完整 sequence/retry/transaction-id，不代替后续高速 line/tile packet 契约；一致但重复的地址流不做位图去重。

Master 收完整帧并通过 CRC → 等待 SDRAM 最后一笔写完成 → 排空旧行预取 → 帧边界显示 → DISPLAY_PUBLISHED 返回 Slave。Slave 本次发送期间必须先观察该反馈拉低，之后再拉高才算当前图完成；UART DONE 此时才允许释放 Master 轮播计时。媒体数据没有绕回 PC，也没有通过 UART 传像素。

单缓冲写入期间只显示加载卡；CRC 失败不显示部分新图，但也没有保留旧完整帧。断线、漏 REQ 或某板独立复位可能停在加载状态，需要双板一起复位。尚无端到端超时自动重传，不能宣称 M2 故障恢复门禁关闭。

## 分工、资源与加载耗时

| 角色 | 今晚真实部署 | 后续 1080p 职责 | 人员 |
|---|---|---|---|
| Slave | TF/SPI、FAT32/catalog、BMP、地址/像素发送、UART 状态 | SD 连续读/预取、视频解包、颜色格式转换、从板缓存 | A 曾雨婷；链路发送由 B 杨文轩维护 |
| Master | 按键/轮播、UART coordinator、收帧/CRC、SDRAM、行缓存、“加载中”、官方 HDMI_B | 1080p timing、packed framebuffer/line buffer、UI/转轮/字幕、缩放/调节、转场、音频合成 | B 杨文轩负责缓存/接收；C 张宗负责交互/表现与集成 |

从板不再为正式链路重复综合 HDMI 和 SDRAM scanout。`m2_slave_tf_hdmi_top` 保留为旧本地可视化回退源码；旧成对 bitstream 在 `sim_work/m2_control_fix_20261004/delivery/`，该旧二进制已由用户确认轮播/切换正常。源码回退需切 Top 与 `constraints/rollback_m2_local/` 对应约束，不能把新 `.adc` 用于旧 Top。

资源问题有实现证据：旧从板的两块行 RAM 被 TD 推断为 1024×24 Logic DRAM；将数据 RAM 的同步读写独立于异步复位控制后，推断为 BRAM，2,204 项行缓存回归及 258 项显示子链回归不改变像素延迟。保留本地 HDMI 的中间实现由 13,080 降到 8,998 LUT（约 -31%）；最终分工后资源如下。官方四千 LUT 例程未包含当前完整 FAT32/catalog/BMP/控制链，不能直接视为同功能比较。

| 最终候选 Top | LUT | REG | BRAM9K | SWNS | HWNS | STA coverage |
|---|---:|---:|---:|---:|---:|---:|
| m2_master_tf_hdmi_top | 4514 | 见 area 报告 | 16 | +0.236 ns | +0.003 ns | 98.30% |
| m2_slave_media_tx_top | 6114 | 见 area 报告 | 0 | +10.085 ns | +0.075 ns | 99.85% |

两者现有约束下 STNS/HTNS=0，已 BitGen。GPIO 数据路径限制为 40 ns，REQ/ACK/发布反馈通过显式同步器；板外传播、串扰不在 STA 内，仍必须实测。Master hold 余量较小，后续 RTL 变化必须重新实现。

当前读卡 SPI 保持已通过的 3.125 MHz（25 MHz / 2 / 4），初始化约 390.6 kHz。640×480 RGB888 BMP 仅像素串行读出就至少约 2.36 秒，另有单扇区命令、FAT、缓存服务及 GPIO 传输等待。**此次没有凭空承诺缩短读卡时间，跨板候选甚至可能增加加载耗时。** 下一轮 A 先测 run divider 4→2（6.25 MHz，初始化 divider 保持 32），再做双扇区缓冲和连续读；每步测实际秒数及坏卡恢复，不与首次跨板板测同时修改。加载卡不是进度条，不显示伪造百分比。

## 14 根线与 1080p 的关系

14 根线够本次图片搬运验证，不等于够最终 1080p60 原始视频。1920×1080 图片可以慢慢传到主板，再由主板本地以 60 Hz 刷新；持续换 60 帧/秒才要求链路一直供应像素。

| 数据类型 | 1080p60 active payload（不含协议开销） |
|---|---:|
| RGB888 | 373.248 MB/s（2.986 Gbit/s） |
| packed YUV422 / RGB565 | 248.832 MB/s（1.991 Gbit/s） |

当前握手 PHY 不满足上述视频吞吐。下一物理门禁使用短排线/转接板和更多交错地线；候选为 16-bit DDR @100 MHz（400 MB/s raw），或原 32-bit SDR @74.25 MHz（297 MB/s raw），均须扣协议/credit 开销并实测 PRBS/CRC/持续吞吐/眼图或时序余量。IO 手册支持 DDR 寄存器不等于任意杜邦线能跑该速率；也不能把带电源脚的 40-pin 接口直接整排短接两块独立供电板。

芯片手册确认每片 2M×32bit SDRAM（8 MiB）、19,600 LUT。32-bit 存一个 1080p 图约 7.91 MiB；若两像素打包一个 32-bit word，RGB565/YUV422 一帧约 3.96 MiB，两帧约 7.91 MiB，仅剩约 92 KiB，还要评估读写仲裁实际带宽。不能继续沿用“32-bit/pixel 双缓冲”的容量假设。

现有结果也说明“一个板子的逻辑一定不够”尚无证据；双板分工的价值是隔离存储解码与显示/交互，并扩充缓存，而不是可以绕过 TF 和板间带宽。最终仍按团队选择完成双板 + 1080p；1080p60 HDMI 刷新与视频素材帧率分别验收。

已阅读：赛题一 1.3（允许同型板主从、自定义链路、无额外处理器）、1.4、EG4S20 数据手册、IO 用户指南、内部块 RAM 用户指南及上述原理图。官方 1.4 属扩展项，但**按团队目标全部作为必做**，不因官方写“非强制”降低项目要求。

## 可复现验证与交付

- `python tools/run_m2_control_regression.py`：12 项全通过，包括原 7 项、新 mailbox 异步时钟/背压/CRC 故障恢复、真实 FAT32/BMP 多图串联新传输链、UI 整帧像素、行缓存与显示子链。该级别为 `[U/C-sub]`，不替代 vendor HDMI 全链仿真或 `[B]`。
- `python tools/build_m2_roles.py`：从两份 active `.al` 生成隔离 `.prj`，顺序 synthesis/P&R/STA/BitGen，并检查错误文本、时序及构建前后源码 SHA256；不覆盖 GUI `_Runs`。可用 `--role master` / `--role slave` 分别构建。
- [证据目录](evidence/M2_MASTER_OUTPUT_20261004/)：最终两角色 timing/area/实现日志/manifest、12 项仿真日志，以及由 RTL 仿真实际像素生成的加载页图片。
- Master SHA256：`fc329eb5f89c6cdd453b2937094f6ff12bf76e0e9ce58119b9cc97a999471d8d`。
- Slave SHA256：`3f8d78d76c8a93f75c8c1bd88f7e2117867b99141ddad25af5bb4b458c54f6e0`。

![RTL 仿真得到的加载卡](evidence/M2_MASTER_OUTPUT_20261004/loading_card.png)
