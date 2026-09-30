# A 线计划：从板媒体生产与双板媒体供给

> 本文件只描述 A 线任务。全项目使用统一节点 `M0～M6`；节点中的 A/B/C 任务并行完成，汇合后才进入下一节点。双板 + 1080P 从 `M1` 就是架构前提，640×480 只是第一种受控媒体规格，不再单独开一条“单板开发线”。实际证据等级以 `docs/03_plan_and_status.md` 为准。

## 1. 责任边界与当前状态

A 线由曾雨婷负责，部署在从板 S，负责：

```text
TF/SPI -> FAT32 mount/catalog -> BMP/vseq decoder
       -> descriptor + decoded line/tile payload
```

A 不负责 SDRAM 控制器、主板 HDMI 时序、主板 front/back、UI/OSD 或转场合成。A 提供应用层媒体 descriptor 和 ready/valid line/tile 数据；B 负责缓存、线上 packet 封装、CRC、物理链路和主板显示缓冲。主板只向从板发送 `image_id`、播放控制、格式和 credit；A 不读取主板 framebuffer 地址。

### A 对 C 的真实依赖边界

C 的选图和播放状态不能凭空假设媒体数量。A 必须向主板 coordinator 提供以下只读结果：

```text
catalog_valid / catalog_count / catalog_epoch
descriptor(image_id, type, width, height, frame_count, duration)
media_ready / source_busy / source_done / source_error
```

因此 C 的 `NEXT/PREV/转轮范围/图片或视频类型显示/播放完成后的自动推进` 在真实系统中依赖 A 的 descriptor 和 status。M1 允许 C 用固定 catalog mock 开发；从 M2 起，C 的真实命令验收必须接入 A 的 catalog/status。A 不依赖 C 的 UI 状态，只消费 coordinator 发出的高层 `OPEN/PLAY/PAUSE/ABORT`。

当前可复用证据：

- P0 full media chain：`[C] PASS(1698)`；
- `p1_media_framebuffer_loader`：`[U] PASS(225)`，覆盖 fragmented FAT、BGR/bottom-up/padding 和 mock APUG011；
- P1-05A 真板显示已完成，但 A 线尚未完成真实 TF、双板 packet、1080p 持续供给。

当前正在进入 `M1`：先冻结双板控制/数据协议、descriptor、credit、错误和 CDC，再把已有 loader 接入统一服务端。不得先做只适用于单板的私有接口。

## 2. 文件所有权

A 线可修改：

```text
src/storage/**
sim_tb/storage/**
sim_tb/integration/tb_p1_media_framebuffer_loader.v
tools/make_sd_card.py 以及 A 线媒体镜像/golden 工具
```

`p1_media_framebuffer_loader.v` 当前已有 P1-05B `[U]` 证据；如需修改须先由集成负责人协调 A/B，因为它连接媒体解析和 SDRAM 写口，不作为 A 的独占所有权文件。

A 线不得修改：

```text
src/framebuf/frame_buffer_manager.v
src/framebuf/framebuffer_writer.v（公共 writer 接口由集成负责人冻结）
src/framebuf/** 的主板读出/line buffer 部分
src/display/**  src/app/**  src/interact/**  src/audio/**
src/top/**  constraints/**  FPGA_Competition_HDMI.al
```

公共协议需要变化时，先提交契约变更，由集成负责人协调 B/C 一起更新；A 不通过隐式信号依赖主板内部状态。

## 3. 媒体与板间契约

### 3.1 第一规格：640×480 图片

| 项目 | 固定规则 |
|---|---|
| BMP | 24-bit BI_RGB，正高度 bottom-up，BGR 转 `0x00RRGGBB` |
| 目录 | FAT32、512B sector、8.3 名，至少 4 个合法图片项 |
| 数据 | A 负责 descriptor 和 decoded line/tile payload；B 负责 wire packet、CRC、cache 和显示提交 |
| 错误 | 非法 header、坏 cluster、短读、超时、CRC/overflow 不得产生成功帧 |
| 测试 | 删除项、LFN、非 BMP、坏文件和 fragmented FAT 必须覆盖 |

`catalog` 必须按 `image_id` 返回 `start_cluster/file_size/fat_lba_base/data_lba_base/sectors_per_cluster` 和 `epoch`。不能把 cluster/LBA 硬编码在 coordinator 或主板。

### 3.2 双板协议

控制面：

```text
M SPI master -> S SPI slave: OPEN/NEXT/PREV/PLAY/PAUSE/SET_FORMAT/CREDIT/ABORT
S SPI slave -> M SPI master: READY/DESCRIPTOR/STATUS/ERROR/COUNTERS
```

数据面首选 source-synchronous GPIO：

```text
S SDRAM/prefetch -> packetizer -> DATA[31:0] + LINK_CLK
                   + VALID/SOF/EOL/EOF + sequence + CRC
```

SPI 只承载命令和状态，不承载原始像素流。首版可用 RGB888 低分辨率验证协议，主线数据格式采用 packed YUV422 以降低 1080p 带宽；格式、payload 长度、`frame_id`、`image_id`、行/tile 索引、credit 和 CRC 都必须在 `M1` 冻结。A 定义应用 payload 字段，B 定义线上分帧、sequence/CRC 和 GPIO 时序。

### 3.3 启动、credit 与完成

```text
C media_cmd -> coordinator 发 OPEN(image_id)
            -> A 查询 catalog 并返回 descriptor
            -> B 分配目标 buffer/credit
            -> A 发送 line/tile packet
            -> B 在 frame boundary 提交
```

A 只报告 `source_done/source_error`；不得生成主板 `swap`。`mem_wr_valid/ready` 或 packet valid 未被接受时，payload 必须保持稳定。物理 TF 时钟与 150 MHz 处理域之间使用显式 FIFO/握手 CDC；不能把 SPI `data_valid` 直接采样进 loader。

## 4. 统一节点中的 A 线任务

| 统一节点 | A 线任务 | A 线完成证据 |
|---|---|---|
| `M0` | 继承 P0/P1-05A 证据；整理 loader、TF、BMP 的输入输出边界 | 既有 `[C] PASS(1698)`、`[U] PASS(225)` 可复现 |
| `M1`（当前） | 冻结 descriptor/packet 契约；实现 SPI 控制帧、credit、错误码和 provider CDC；建立从板 media-service shell；用 mock source 验证行数据 ready/valid | descriptor/线上 packet、sequence/CRC 和双板链路仍待与 B 集成冻结；M1A 模块级 Questa mock 回归通过，不能替代真实 TF 或双板证据 |
| `M2` | 完成真实 TF/SPI provider、FAT32 mount/catalog、至少 4 幅 BMP；将 loader 输出转换为统一 packet 或受控本地写入事务；冻结 C 可消费的 descriptor/status 实现 | fragmented FAT、非法文件、真实卡模型/受控镜像、四图 golden；C 的真实选图命令能收到 ready/busy/done/error |
| `M3` | 按 descriptor 生成持续 line/tile 数据并响应 credit；实现帧边界、重试和错误隔离；配合 720p bring-up | 在 credit 下持续输出，无丢包/重包/CRC 错误 |
| `M4` | 将媒体生产扩展到 1920×1080：packed YUV422、帧/行/tile descriptor、带宽预算和 underflow 预警 | 1080p 静态图连续 packet，带宽和 buffer 水位有记录 |
| `M5` | 接入 `vseq_reader`/视频帧调度；支持图片、视频、NEXT/PREV/PLAY/PAUSE 和双源切换所需的两路媒体描述 | 视频帧序号连续，切换不会提交坏帧 |
| `M6` | 长稳、异常恢复、双源/转场媒体准备和最终演示镜像 | 图片→视频→切换/转场长稳证据；故障可回退到上一帧 |

每个节点的合并顺序为：A 自测与提交 → 集成负责人接入 mock/子链 → 与 B/C 合并验证。A 未完成时，B/C 使用固定 descriptor、PRBS 或本地 test source；但 M2 真实媒体命令门禁必须等待 A 的 catalog/status 契约和 provider 实现，不能把 mock 结果记为双板完成。

### M1A 从板媒体服务骨架 — `[U]/[C-sub] Questa PASS`

`src/storage/m1a_service_shell.v` 将 SPI Mode 0 字节入口、`SOF/opcode/length/payload/CRC16-CCITT` 命令解码、异步 provider byte FIFO 和 deterministic media-service mock 组合起来。mock 提供 catalog/descriptor/status、PLAY/PAUSE、按行 credit 与 ready/valid 媒体字；它不读取 TF，也不实现线上 packet sequence/CRC 或 GPIO 数据链路。SPI 无字节级反压，shell 用 sticky `spi_rx_overflow` 报告 ingress FIFO 满时的丢字节；状态回读通过稳定数据 mailbox 跨域。

QuestaSim 10.7c：SPI slave、command decoder、provider CDC、media mock、service shell、catalog table、FAT32 catalog path 和原 `fat32_scan` 回归八个 testbench 全部 PASS。新增 `m1a_fat32_catalog` 将现有 scanner 接至 catalog table；受控 MBR/BPB/多扇区根目录簇仿真验证文件 cluster/size、FAT/data LBA base 和 sectors-per-cluster 均能进入 descriptor。`fat32_scan` 现在遍历根目录首簇内的各扇区，但尚不跟随 FAT 链读取后续目录簇，也尚未连接真实 TF/SPI provider。完整回归命令为 `sim_tb/storage/run_m1a.ps1`。该结果是模块/受控 sector-stream `[U]/[C-sub]` 仿真证据；真实卡接线、跨簇目录、A/B 冻结的线上 packet 契约、双板 top、TD 实现及真板验证仍未完成。

## 5. A 线验收门槛

1. 目录扫描不依赖手工 cluster；旧 `image_id` 在重扫后由 `epoch` 失效。
2. 一次 OPEN 只产生一次媒体事务；超时、取消、reset 后的旧 sector/packet 不得污染下一次事务。
3. valid/ready、credit、sequence 和 CRC 无丢重；错误只能产生错误状态或回退帧。
4. 640×480 是 `M2` 的第一验证规格；720p 仅用于 `M3` 链路 bring-up；A 线最终必须提供 1080p 连续媒体源。
5. A 线 `[U]/[C-sub]` 不等于双板 `[C]`、时序 `[S]` 或真板 `[B]`；三类证据由集成负责人分别记录。
