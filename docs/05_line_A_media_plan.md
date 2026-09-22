# A 线计划：TF/FAT32/BMP 媒体输入

> 2026-09-21 修订。公共契约、文件所有权及门禁以 `08_three_line_integration_flow.md` 为准；本文件是实施计划，实际证据等级以 `03_plan_and_status.md` 为准。

## 1. 目标及已实现边界

A 线承担康芯选题一基础①：从本地 TF 自动扫描、识别和装载**至少 4 幅 640×480、24-bit BMP**。交付范围从卡初始化、FAT32 挂载、目录表到向 back framebuffer 发出一帧写请求，不能仅交付“已知 cluster 的一个文件能解码”。

可复用的已有证据：

| 部分 | 已有记录 | 不能据此宣称 |
|---|---|---|
| P0 full media chain | `[C] PASS(1698)` | 真实卡与当前板级 top 已接通 |
| `p1_media_framebuffer_loader` | `[U] PASS(225)`，17×12、fragmented FAT、BGR/bottom-up/padding、mock APUG011 | 全尺寸、真实 TF、双缓冲或 TF→HDMI 已通过 |

当前 loader 内部已有 FAT file reader、BMP parser/pixel stream 和 `framebuffer_writer`，输入依赖外部提供 cluster/size/FAT/data LBA/SPC。当前 `fat32_scan` 仅扫描根目录第一簇的第一扇区，BPB 信息存于内部寄存器，没有完整对外导出 loader 所需的卷参数。当前 `sd_reader` 是命令/字节层 FSM，板级 SPI 控制、卡类型/地址单位、重复读和错误路径仍需 provider 集成验证。

## 2. 架构与文件所有权

```text
TF physical + sector provider CDC
   -> FAT32 mount/scan -> catalog/volume metadata
   -> 按 image_id 查表
   -> p1_media_framebuffer_loader（内部唯一 framebuffer_writer）
   -> mem_wr_* -> B SDRAM sink
```

A loader 是唯一 writer owner，即唯一控制它内部 writer.start 的模块。B manager 只预留 back、消费最终完成并管理 front/back；不能另建第二个 writer。writer 的公共 RTL 文件由 B 维护并默认冻结，A 不直接修改它。

A 可编辑：

- `src/storage/**`，包括新的 mount/catalog/provider/CDC wrapper；
- `src/framebuf/p1_media_framebuffer_loader.v`；
- `sim_tb/storage/**`；
- 实际已有的 `sim_tb/integration/tb_p1_media_framebuffer_loader.v` 与 `run_p1_media_framebuffer_loader.do`；
- `tools/make_sd_card.py` 及新增的 A 媒体 golden/镜像工具；`video_to_vseq.py` 留在 P3。

A 不编辑 manager、公共 writer、SDRAM/显示读出、C 模块、active top、约束或 TD 工程。公共 P0 全链 harness 由集成负责人维护，A 可以在独立 worktree 运行回归。

## 3. 首版媒体及目录契约

| 项目 | 固定规则 |
|---|---|
| BMP | 640×480、24-bit BI_RGB、正高度 bottom-up；文件 BGR 正确转 RGB |
| SDRAM pixel | 一个 32-bit word：`0x00RRGGBB`，输出按 display y 坐标落址 |
| stride/base | stride=640 words；base 4-word 对齐；地址为 word，不能把 BMP byte offset 当 SDRAM 地址 |
| buffer map | B 分配 A=0、B=307200 words，各 307200 words；A 不能自行改 front/back |
| BMP row | 文件 row padding 与 framebuffer stride 分开计算；640×480 行恰无 padding，小尺寸测试继续覆盖 padding |
| 目录首版 | MBR FAT32、512B sector、8.3 名；自动生成不少于 4 个合法图片表项 |
| 错误 | 非法 header/尺寸、短读、坏 cluster、超时、overflow 均不得使失败帧获得可显示资格 |

A 新增 catalog/volume wrapper，导出 `catalog_valid/count/epoch`，支持 `image_id[7:0]` 查询得到 `start_cluster/file_size/fat_lba_base/data_lba_base/sectors_per_cluster`。查表握手及 payload 在 I0 固定。coordinator 只负责路由，不解析 FAT，不从外部硬编码 cluster/LBA。

首版受控镜像将至少 4 个 8.3 BMP 条目放在当前 scanner 支持的根目录扇区；测试还应混合删除项、LFN、非 BMP 项及坏文件，证明不会把 4 个文件名直接当成 4 幅可播放图片。首次逐文件 header 识别后发布可播放表；BMP 全文装载仍要检查完整性。记录受支持卡布局，后续多扇区/多簇根目录扫描由 A 单独扩展，不能声称支持任意目录。

扫描、header 探测和 loader 共用同一 TF provider，由 A 仲裁，一次只允许一个 sector 请求 owner。catalog 建立不依赖 B framebuffer。重扫必须先停止/完成当前读取、更新 epoch，不能让旧 image_id 指向新表。

## 4. 启动与完成契约

文中的 `load_done/load_ok` 是当前 loader `done/ok` 的逻辑别名，错误由 `protocol_error/source_error/overflow` 等汇总；不能把这些规划名称当作现有端口。

唯一启动次序：

```text
coordinator 已取得合法 catalog metadata
 -> B manager.load_start + 固定 640/480/640
 -> manager.load_accept
 -> coordinator 锁存 write_base/metadata
 -> loader.start（loader.ready 时，恰一次）
 -> loader 自行在解析 header 后启动内部 writer
```

manager 的历史 `writer_start` 输出在本版不连接；不得同时和 coordinator 触发 loader。BMP header 检查位于已预留事务内部，不能要求 B 等 header 才允许 A 开始读文件，否则会形成启动互等。

loader 输出 `mem_wr_valid/ready/addr/data`，valid 未被接受前 payload 必须稳定。`done` 只保证 loader 及内部 writer 终态、抽象写已被接受；B 的 registered request slice/APUG011 还可能有在途写。集成桥必须锁存 loader 结果，等待 B write fence 再向 manager 发一次 `writer_done/writer_ok`。A 不生成 pending_swap/swap，也不把 done 当显示成功。

## 5. 真实 provider、节流及超时

首版 physical reader/SPI 位于板级 50 MHz 域，loader/catalog/manager 位于 150 MHz；若物理模块另有时钟，A 必须在 I0 登记并提供 CDC。默认在 A provider wrapper 中集中处理 CDC，`mem_wr_*` 在 150 MHz 与 B 同域，不再额外重复跨域。

provider 至少实现：请求 LBA 握手、完整 sector 数据缓存、响应归属、成功/失败及超时、reset/取消后旧响应隔离。physical `data_valid` 不能直接跨入 loader；多比特 LBA/结果用握手或 FIFO，不逐位双触发器采样。

当前 BMP 像素是 valid-only，没有逐像素 ready 回传。writer 内 FIFO 只能吸收有限暂停，`mem_wr_ready` 低并不能停止 BMP 解析。新增 sector 缓存后若在 150 MHz 连续重放 512B，仍可能压满 writer，因此 A 必须交付 provider 重放节流：

- 在 A loader wrapper 暴露/计算可靠的像素容量 credit，预留 BGR 拼装和在途字节余量；不要只观察某拍 mem_wr_ready；
- 以 credit 限制 `sector_din_valid`，允许受控字节间隙，physical 侧在开始块事务前保证整扇区存储容量；
- I0 先用有限 FIFO 和最大写阻塞 mock 冻结节流接口；若需修改公共 writer 的水位输出，由 B 的独立 PR 维护，不由双方同时编辑；
- 覆盖读优先仲裁、SDRAM refresh、read cache 被写失效等竞争；FIFO 超界必须报失败，不能静默丢字；
- loader 默认 `STALL_TIMEOUT_CYCLES=200000` 在 150 MHz 下约 1.33 ms，不能照搬成真实卡超时。按初始化、块等待、节流、写排空分别预算并测试有限退出；
- 某模块因故障不能自行 done 时，由集成恢复协议隔离并排空后复位该事务域，保证下次 load 不混入旧 sector/写请求。不能通过复位 HDMI 来清除媒体错误。

## 6. 分阶段交付

| 阶段 | 工作 | 独立验收 |
|---|---|---|
| A0 | 对齐 I0：格式、目录/metadata、provider/CDC、节流、load start/done | 用 fake catalog、mock sink 编译并测试，无 B/C 实现依赖 |
| A1 | 保持 P0 和 loader 回归，补 mount/catalog 导出 | fragmented FAT、padding、非法文件；至少四图自动识别；卷参数直达 loader |
| A2 | provider-realistic chain 与流量预算 | 保持 PASS(225) 覆盖，并测试 backpressure、最后一笔写、无界等待退出 |
| A3 | 真实 TF provider、SPI 初始化/寻址、sector 缓存、CDC 和重试 | 卡模型/候选 harness；记录卡类型、频率、超时及重扫规则 |
| A4 | 640×480 loader 与 mock/真实 B sink | 不少于四图逐字 RGB golden；显示读竞争下不溢出；错误保持 front |
| A5 | 集成 I3/I7 图片候选 | 集成负责人接 active top，A 提供卡镜像和真实 TF 调试证据 |

可以先用内存扇区 provider 做 A1/A2/A4 的 RTL 部分，同时开发 A3；真实卡未完成不阻塞 B/C 单元开发。

## 7. 回归及完成口径

既有入口包括：

```text
sim_tb/storage/run_sd_spi.do
sim_tb/storage/run_sd_reader.do
sim_tb/storage/run_fat32_scan.do
sim_tb/storage/run_fat32_file_reader.do
sim_tb/storage/run_bmp_parser.do
sim_tb/storage/run_bmp_pixel_stream.do
sim_tb/integration/run_p1_media_framebuffer_loader.do
sim_tb/integration/run_p0_media_chain.do
```

新增 catalog/provider/节流 TB 随对应模块交付。A 验收须证明启动和 done 唯一、写地址落在获授 back 区域、valid/ready 无丢重、目录无需手工 cluster、错误不会标为成功。

A 的独立 PASS 只说明媒体事务；P1-05B 的 `[C]/[S]/[B]` 分别需要集成 RTL、当前实现时序和实际真板证据，按 docs/03 独立记录。完成四图显示后仍需 C/集成的 HDMI 音频才能覆盖竞赛全部基础要求。
