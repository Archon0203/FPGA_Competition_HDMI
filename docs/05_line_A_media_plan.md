# A 线计划：从板图片媒体

> 负责人：曾雨婷。A 线只负责从板上的 TF/FAT32/BMP 图片生产和图片事务状态，不做视频输出、不实现主板 UI，也不直接操作主板 framebuffer。最终目标是为主板 1920×1080 静态图片输出提供可靠、可重试、可度量的图片数据。

## 当前位置

`M2` 的 640×480 双板图片闭环已经真板通过：从板读取 TF 图片，经 14 线链路发送，主板接收并 HDMI 输出；NEXT/PREV 和自动轮播已通过。A 线下一步进入 `M3-A`：把同一事务模型扩展到 1920×1080 静态图片，并先测出加载时间、数据量和背压位置。

## 1. A 线责任边界

```text
TF/SPI -> FAT32/catalog -> BMP parser -> image descriptor
                                  -> decoded pixel/line payload -> B 线发送端
```

A 线提供：

- FAT32 扫描、图片目录和 `image_id`；
- 24-bit BI_RGB BMP 解析，BGR 到项目内部 RGB 表示的转换；
- 图片宽高、像素格式、字节数、目录版本 `catalog_epoch`；
- `media_ready / source_busy / source_done / source_error`；
- 对 B 线的 `valid/ready` 或等价 packet payload，未被接受时保持 payload 稳定；
- 取消、超时、复位后的事务清理，避免旧图片的 sector 或 packet 污染下一次加载。

A 线不负责：

- 主板 HDMI 时序、主板 framebuffer、frame swap；
- UI/OSD、字幕、转场、亮度/对比度和音频；
- 直接读取或写入主板 SDRAM 地址；
- 视频帧、`.vseq`、视频播放或持续视频吞吐。

## 2. 与 B/C 的接口

### A → C：目录和媒体事实

```text
catalog_valid
catalog_count
catalog_epoch
descriptor(image_id, width, height, pixel_format, byte_count)
source_busy / source_done / source_error
```

C 线只依据这些事实决定转轮范围、当前图片、加载提示和轮播计时。`OPEN/PAUSE/ABORT` 是 C/coordinator 发出的高层命令；A 不等待 C 的 UI 状态，也不产生主板 `swap`。

### A → B：图片数据事务

每次 `OPEN(image_id)` 只允许产生一个带 `transaction_id` 的图片事务：

```text
BEGIN(image_id, width, height, pixel_format, byte_count)
  -> line/segment payload + address/index + sequence + CRC
END(transaction_id, status)
```

B 线可以施加背压；A 在 `ready=0` 时不得推进地址或丢弃 payload。任何短读、坏 BMP、CRC/超时、取消或复位都只能报告失败，不能报告成功图片。

## 3. 图片规格和 1080P 策略

| 阶段 | A 线媒体规格 | 说明 |
|---|---|---|
| `M2` 回退基线 | 640×480、24-bit BMP | 已完成双板真板闭环，保留为回退和故障定位 profile |
| `M3` 主线 | 1920×1080 静态 BMP | 只需完成一次可靠加载和安全发布，不追求视频帧率 |
| `M4` 优化 | 1080P 多图目录、预读/缓存 | 以切换等待时间和 SDRAM 水位为指标 |

M3-0 先由 A/B/集成共同冻结 `pixel_format`。优先评估 RGB565 传输/缓存后在主板展开为 RGB888，以降低杜邦线传输量和主板存储压力；如果现有 32-bit RGB888 路径在 1080P 资源、时序和加载时间上可接受，可保留 RGB888。未完成容量、吞吐和板测前，不把任一种格式写成已通过结论。

## 4. 节点任务

| 节点 | A 线任务 | 完成条件 |
|---|---|---|
| `M0` | 保留 P0/P1-05A loader、BMP、FAT32 证据 | 既有 `[U]/[C]` 回归可复现 |
| `M1` | 提供 catalog/descriptor/status 契约和 provider shell | 与 C 的命令状态、与 B 的 payload 契约冻结 |
| `M2` | 真实 TF/FAT32/BMP、图片发送、NEXT/PREV、自动轮播 | 640×480 双板真板 `[B]`，当前已通过 |
| `M3` 下一节点 | 1920×1080 BMP 解析；测量 TF、解码、发送、背压各段耗时；支持取消/重试 | 4 张 1080P 图片可产生完整事务，无短帧/旧帧污染 |
| `M4` | 多图预读、缓存/目录刷新、加载延迟优化；为转场提供上一张/下一张描述 | 图片切换等待时间有记录，异常可回退 |
| `M5` | 为主板转场和字幕提供稳定的 `image_epoch`、`source_done`、`source_error` 边界 | 每次切换只提交目标图片，状态与图片一致 |
| `M6` | 长稳、坏卡/坏文件/断链/复位恢复，准备最终 TF 镜像 | 长时间轮播和异常恢复记录完整 |

## 5. 文件所有权

A 线可修改：

```text
src/storage/**
sim_tb/storage/**
sim_tb/integration/tb_p1_media_framebuffer_loader.v
tools/make_sd_card.py 以及 A 线媒体镜像工具
```

A 线不得直接修改：

```text
src/framebuf/** 的主板读出与提交部分
src/display/**  src/interact/**  src/audio/**  src/app/**
src/top/**  constraints/**  两个长期 .al 工程
```

公共字段或 packet 需要变化时，先提交接口说明，由集成负责人协调 B/C 同步修改；禁止通过隐式信号建立跨线依赖。

## 6. A 线验收门槛

1. 目录重扫会生成新的 `catalog_epoch`，旧 `image_id` 不得误指向新目录项。
2. `OPEN -> BEGIN -> payload -> END` 每个事务只完成一次；取消、超时和复位可重新开始。
3. 24-bit BMP 的 bottom-up、行 padding、fragmented FAT、坏文件和短读均有回归覆盖。
4. 1080P 图片的宽高、像素格式和字节数由 descriptor 传递，不在 C/B 线硬编码。
5. A 线 `[U]/[C-sub]` 不能替代双板 `[C]`、TD `[S]` 或真板 `[B]`；最终证据由集成负责人记录到 `docs/03_plan_and_status.md`。
