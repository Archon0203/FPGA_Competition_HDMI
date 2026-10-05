# M2 B 线检查执行记录 · 2026-10-05

基于用户提供的 B 线检查清单，对当前 `main@00c8fca` 逐项执行。本文区分：

- **静态可证明**：由当前 RTL / TD 工程 / 约束直接确认；
- **结构测试**：用与 RTL 相同的 5×7-bit 分片规则做确定性模型检查；
- **真板待测**：必须实际烧录、接线、ChipWatcher/示波器才能确认。

本轮不把 B1/B4/B10/B12 混成一个改动。唯一直接修复是清掉当前 Master `.al` 中被 #46 重新引入的两个 `AutoExcluded=true`，使仓库自带 `tools/check_td_project.py` 恢复 PASS。媒体协议本身未在无 RTL 模拟器/无真板的环境里贸然改版。

## 结论先行

1. **B-1 的 RTL 矛盾成立，而且优先级最高。** 当前 Master Top 中，物理 LED3 (`led[2]`) 就是 `display_published`；`display_published = use_framebuffer && media_succeeded`；APUG092 的 RGB 输入就是由 `use_framebuffer` 控制的同一个 `axis_data` mux。因此，同一个正确构建/正确烧录的 bitstream 内，如果 LED3 稳定为 1，HDMI 不应仍选择 `m2_loading_card`。
2. **当前仓库源码与 2026-10-05 集成记录里的旧 bitstream manifest 不是完全同一版本。** 当前 HEAD 为 `00c8fca Test/m2 (#46)`；集成证据中的 `master.bit/slave.bit` 是更早源码集生成的，之后又有 mailbox / TD 工程提交。ZIP 本身不含当前重新生成的 bitstream，无法确认板上实际烧入文件的 SHA256。
3. **B-3 当前 5-beat 打包规则通过。** 指定 9 个 pattern + 固定种子随机 10,000 words，重构 `RX == TX`，0 error。
4. **B-4 当前协议确实不支持单板复位重定界。** RX 在一个 word 的 beat0~beat3 后独立复位，后续 5-beat 分组永久错位；只有恰好在 beat4 字边界复位保持对齐。源码自己的注释也明确要求 `Reset both endpoints together`。因此需要 beat index / framing / epoch / retraining 之一，不能靠调延时解决。
5. **B-10 fence 链结构正确，但 Top 把 `mem_wr_ready` 当 `sdr_adapter_idle`。** 对当前 `p1_sdram_cached_adapter`，`mem_wr_ready` 只在 `ST_IDLE + provider_available + 无读请求` 时为 1，因此作为 fence 条件是保守的；不过它不是独立、语义明确的 `adapter_idle` 输出，后续建议显式化。
6. **B-12 的“假 remote_begin 让画面一直 Loading”机制在源码中真实存在。** 每个被 RX 当成 `B17E00xx` 的 header 都会触发 `dispatch_fire`，继而 `use_framebuffer <= 0`。当前 active RTL 没有文档建议的 begin/done/error 三个计数器。

## B-1｜publish 与 Loading 矛盾

### 静态结果：PASS（矛盾被确认）

当前链路：

```text
m2_master_tf_hdmi_top
  led[2] = display_published
  display_published <- u_display.remote_published

m2_frame_display_core
  remote_published = use_framebuffer && media_succeeded
  axis_data = use_framebuffer ? framebuffer_axis_data : loading/startup data
  apug092_tx_wrapper.axis_data = axis_data
```

当前 Master `.al` 的 Top 也是 `m2_master_tf_hdmi_top`。

因此真板上若同时观察到：

```text
display_published = 1
use_framebuffer   = 1
```

但显示器仍是 `m2_loading_card`，优先判定：烧录文件/Top/观察定义/实际 HDMI 路径与当前工程不一致，而不是先查 CRC 或 BMP。

### 本轮发现的工程问题

原始 ZIP 上直接执行：

```text
python tools/check_td_project.py
```

Master 工程失败，#46 重新给以下两个文件加了 `AutoExcluded=true`：

```text
src/dual_board/m2_line_packet_rx.v
src/dual_board/m2_frame_commit.v
```

它们不是当前 mailbox/remote-frame 主路径，因此不能直接解释 Loading，但这证明当前工程元数据不能跳过构建检查。本执行包已移除这两个 stale `AutoExcluded`；项目检查恢复 PASS。

## B-2｜LED1/LED2 不能证明 B 数据链

### 静态结果：PASS

`m2_master_media_control`：

```text
led[0] = ack_toggle
led[1] = link_ok
```

Master wrapper：

```text
led[2] = display_published
led[3] = display fault OR control fault
```

所以 LED1 高频闪 + LED2 常亮只能证明 115200 UART 控制面在工作，不能证明 `link_data[6:0] / REQ / ACK / remote frame` 正常。

## B-3｜7-bit mailbox 每个 32-bit word

### 结构测试：PASS

当前编码严格为：

```text
beat0 = word[6:0]
beat1 = word[13:7]
beat2 = word[20:14]
beat3 = word[27:21]
beat4 = {3'b000, word[31:28]}
```

解码：

```text
{beat4[3:0], beat3, beat2, beat1, beat0}
```

执行：

```text
00000000
FFFFFFFF
12345678
89ABCDEF
B17E0000
F17E0000
40000000
7FFFFFFF
80000000
+ deterministic random 10000 words
```

结果：`RX == TX`, `0 error`。

额外检查：当前所谓“preserve mailbox high nibble”改写与更早的 shift 写法，在上述 pattern + 10,000 random words 上生成相同 5 个 beat；不能仅凭那个提交名断定旧 bitstream 一定会损坏 header 高 nibble。

## B-4｜Master/RX 或 Slave/TX 单独复位

### 结构测试：KNOWN FAIL

用 header 后接 address/pixel 的连续 5-beat stream，在接收端独立复位后重新从 beat0 分组：

```text
reset after beat0 -> FAIL
reset after beat1 -> FAIL
reset after beat2 -> FAIL
reset after beat3 -> FAIL
reset after beat4 -> PASS（恰好字边界）
```

TX 单独在 word 中间复位并从新 header 重启时，同样只有字边界复位天然保持 5-beat 相位。

根因不是 CDC settling delay，而是**物理协议没有 beat index / word framing / link epoch**。当前源码也明确写着：

```text
Reset both endpoints together to establish word alignment.
```

本执行包没有在缺少 Questa/TD/真板验证时直接把 active PHY 改成新编码。建议下一独立 changeset 采用明确 beat index（例如每 beat 带 index）或独立 framing/epoch，并要求两端成对更新。

## B-5｜真实接线

### 约束静态结果：PASS；物理线：待真板

Master/Slave ADC 对以下 10 个媒体/反馈网使用完全相同的 FPGA 球位：

```text
link_data[0..6]
link_req
link_ack
display_published
```

与 14 线文档一致。软件无法证明杜邦线实际没有把 data[0]/data[1]、data[5]/data[6]、REQ/ACK 插反；这一步必须断电后逐针测。

## B-6｜第一个 frame header

### 静态结果：PASS；真板捕获：待测

TX 首字：

```text
{24'hB17E00, image_id}
```

bootstrap dispatcher 第一张固定 `image_id=0`，所以首次应为：

```text
B17E0000
```

若 ChipWatcher 在 `u_link_rx.out_valid/out_data` 完全看不到 `B17E00xx`，先停在 mailbox/接线/复位相位，不进入 SDRAM 排查。

## B-7｜一帧 word 数

### 静态结果：PASS

```text
1 HEADER
307200 ADDRESS
307200 PIXEL
1 END
1 CRC
----------------
614403 words
```

## B-8｜RX 四个关键事件

### 静态结果：PASS；真板计数：待测

`m2_remote_frame_rx` 的正常状态机满足：

```text
frame_begin: header 时 1 pulse
count: 每个 pixel +1，目标 307200
frame_error: 正常帧始终 0
frame_done: CRC exact match 后 1 pulse
```

值得注意：在 state 1 再遇到任意 `B17E00xx` 会重新产生 `frame_begin`、清 count，因此 mailbox 错位/重复 header 可以造成 begin 多、done 少。

## B-9｜CRC

### 静态结果：PASS；真板三值对照：待测

TX/RX 都使用 `0x04C11DB7`，初值 `0xFFFFFFFF`；CRC 覆盖 HEADER、ADDRESS、PIXEL，不覆盖 END。RX 只有：

```text
received_crc == calculated_crc
```

才拉 `frame_done`，否则 `frame_error`。

真板仍应同时抓：TX final CRC、RX calculated CRC、RX received CRC。

## B-10｜frame_done → SDRAM fence

### 静态结果：PASS with WARN

当前链：

```text
media_done
  -> done_toggle (media domain)
  -> done_sync1/done_sync2 (SDR domain)
  -> fence_pending
  -> FIFO empty && sdr_adapter_idle
  -> sdr_fenced pulse
  -> fenced_toggle_sdr
  -> fenced_sync1/fenced_sync2
  -> frame_fenced_media = 1
```

当前 Top 实际连接：

```text
.sdr_adapter_idle(mem_wr_ready)
```

`p1_sdram_cached_adapter.mem_wr_ready` 只在 `state == ST_IDLE`、provider 可用且当前没有读请求时为 1；所以它比“只看 FIFO 空”更安全，但建议后续增加语义明确的 `adapter_idle` 输出，不再借用 ready 名称。

## B-11｜framebuffer warm-up / publish

### 静态结果：PASS；真板里程碑：待测

发布条件实际包含：

```text
fb_frame_boundary
media_succeeded
frame_fenced_media
frame_ready_pix
fb_warm_ready
!pipeline_protocol_error
!frame_write_error
```

第一次安全 frame boundary 只置 `publish_wait_frame=1`，下一次满足条件的 frame boundary 才置 `use_framebuffer=1`。因此有意丢弃一整帧预取，避免旧行数据发布。

## B-12｜假 remote_begin

### 静态结果：机制确认；计数器缺失

当前：

```text
dispatch_fire = remote_begin     // REMOTE_INPUT=1
if (dispatch_fire)
    use_framebuffer <= 0;
```

所以如果链路持续误解析 header：

```text
remote_begin
remote_begin
remote_begin
...
```

外观确实会一直像 Loading。

active RTL 目前没有：

```text
remote_begin_counter
remote_done_counter
remote_error_counter
```

在改功能前，建议 ChipWatcher 先直接抓 pulse 并用采集端计数；若要加 RTL 计数器，应作为独立 debug changeset，重新跑时序，避免在 Master 极小 hold 余量上无意改变实现。

## B-13｜display_published 启动/复位语义

### 静态结果：PASS；单板复位仍受 B-4 限制

Slave：

```text
published1 <= display_published
published2 <= published1
use_framebuffer = published2 && observed_loading && !tx_busy
```

每次 `dispatch_fire`：

```text
observed_loading <= 0
```

之后必须实际观察到同步后的 `published2 == 0` 才重新置 `observed_loading=1`。因此逻辑上不会直接把旧的 published=1 当作本轮完成；Master reset 后输出应回 0，并在两个 Slave media clock 后被看到。

但 Master 单独复位会同时触发 **B-4 mailbox 相位问题**，所以反馈语义正确不代表媒体链能单板复位恢复。

## 建议真板执行顺序（不要跳层）

1. **重新从当前修正后的工程成对构建 Master/Slave，记录两个 bit SHA256，并确认 Top。** 不混用旧 delivery。
2. 上板先只看 B-1：LED3 与 ChipWatcher 的 `display_published/use_framebuffer/media_succeeded/axis_data` mux 是否一致。
3. 若 `display_published=0`：抓 mailbox `packet_valid/packet_data/REQ/ACK`，确认首个 `B17E0000` 和 614403 word 数。
4. header 正常后才进入 remote RX `begin/count/error/done` 与 CRC 三值。
5. `frame_done=1,error=0` 后才进入 `sdr_fenced -> frame_fenced_media -> frame_ready_pix -> fb_warm_ready -> frame boundary -> publish`。
6. 最后单独做 B-4 单板复位实验；它当前应视为“已知失败项”，不要和第一轮成对复位 bring-up 混测。

## 本执行包增加/修改

```text
FPGA_Competition_HDMI_MASTER.al
  - 移除 #46 重新引入的 2 个 stale AutoExcluded 标志

tools/check_m2_b_line.py
  - B-1~B-13 静态/结构检查
  - B-3 required patterns + random 10000
  - B-4 reset phase structural check
  - pin-map / remote-frame / fence / publish / feedback audit

docs/develop_records/M2_B_LINE_EXECUTION_20261005.md
  - 本记录
```

本环境没有 Questa `vlog/vsim`、TD6.2.1，也没有两块真板，因此没有声称完成新 RTL 仿真、synthesis/P&R/STA/BitGen 或 ChipWatcher 真板结果。
