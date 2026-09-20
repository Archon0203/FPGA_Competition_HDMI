# P1-05B `p1_media_framebuffer_loader` 测试向量

> 状态：`[U] PASS`（checks=225）。Testbench：`sim_tb/integration/tb_p1_media_framebuffer_loader.v`。

## CASE0：fragmented FAT32 BMP → cached APUG011 provider

- BMP：17×12、24-bit BI_RGB、bottom-up、`data_offset=54`；
- 行字节 `17×3=51`，因此每行 padding=1；
- FAT cluster chain：`3 -> 7 -> EOC`；
- sector provider 在每个 sector start 与固定 byte index 注入 bubbles；
- loader 侧以 150 MHz 写入域运行；
- backend：`sdram_arbiter -> p1_sdram_cached_adapter -> mock_apug011_app_port`。

检查：

1. FAT、BMP、writer 三项均成功；
2. loader 无 protocol/source/FIFO overflow 错误；
3. arbiter、cached adapter 和 APUG011 model protocol health 均正常；
4. APUG011 model memory 中每个 `y*17+x` word 精确等于独立 golden `0x00RRGGBB`；
5. provider 接受至少 `17×12` 个 application write word。

## CASE1：无复位非法 BMP signature

在 CASE0 成功后，将新文件的第一个 byte 改为非 `B`，保持同一 FAT cluster chain 后重新 `start`。

检查：

1. loader 必须 `done=1, ok=0`，并报告 source error；
2. 不触发 FIFO overflow；
3. APUG011 provider 的 application write count 不增加；
4. 已成功加载的 framebuffer 首、中、末 word 保持原 RGB golden，证明非法文件不会覆盖前一帧。

实际通过记录：

```text
PASS: p1_media_framebuffer_loader fragmented BMP -> cached APUG011 chain (checks=225, app_writes=816)
```

该 `[U]` 不等价于真实 TF card、TD timing 或真板 HDMI 图片播放通过。
