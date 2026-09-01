# P0-07 `sdram_arbiter` 接口与时序说明

> Architecture Contract v1.0  
> 状态：**candidate，待 ModelSim**

## 1. 职责

`sdram_arbiter` 是 P0 framebuffer 抽象内存层的唯一命令仲裁点：

```text
framebuffer_writer (write) ----\
                                sdram_arbiter -> mock SDRAM / sdram_adapter
line_prefetcher    (read)  -----/
```

它不解析像素、不写 line buffer、不直接例化 APUG011。

## 2. 仲裁策略

当前冻结策略是 **display read strict priority**：

```text
rd_valid = 1  -> 选择 line_prefetcher read
否则         -> 允许 framebuffer_writer write
```

因此当 read/write 同时请求时：

- read 可以获得 `rd_ready`；
- write 必须看到 `wr_ready=0`；
- 同周期绝不能有 read/write 两个 command 都被下游接受。

这是有意的工程取舍：图片后台加载可以变慢，但 HDMI active line 的预取不能因写流量被饿死。

## 3. 读 response

下游 read response 只返回 `line_prefetcher`：

```text
mem_rvalid/mem_rdata
      ↓
sdram_arbiter
      ↓
rd_rvalid/rd_rdata
      ↓
line_prefetcher
```

arbiter 维护 accepted read 的 outstanding 数量。

- 有 outstanding，response 合法；
- 第一笔 read accepted 的同周期出现 zero-latency response 也合法；
- 无任何对应 request 的 unsolicited response 被丢弃，并置 sticky `protocol_error`。

当前只有一个 read source，因此不需要 owner tag。未来若增加第二个独立 read source，必须先做 Architecture Change Request，并增加 owner/tag 路由，不能直接把 response 广播给多个源。

## 4. 下游接口

P0 使用抽象 memory interface：

```text
write: mem_wr_valid / mem_wr_addr[20:0] / mem_wr_data[31:0] / mem_wr_ready
read : mem_rd_valid / mem_rd_addr[20:0] / mem_rd_ready
resp : mem_rvalid / mem_rdata[31:0]
```

P1 的 `sdram_adapter` 负责把这组接口适配到 APUG011；`sdram_arbiter` 本身不包含 vendor primitive。

## 5. 数据格式

地址单位是 **32-bit word**，不是 byte。

framebuffer 数据格式固定：

```text
0x00RRGGBB
```

arbiter 不修改地址和数据。
