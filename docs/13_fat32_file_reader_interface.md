# 13 · `fat32_file_reader` 接口与时序契约（P0-01）

> 状态：**[U] UNIT PASS — 2026-08-31**  
> 架构依据：`docs/02_architecture.md` Architecture Freeze v1.0。  
> 本文描述当前 `src/storage/fat32_file_reader.v` v1.0 的真实接口与边界；如需改外部端口，必须先走 Architecture Change Request / 文档同步流程。

## 1. 模块职责

`fat32_file_reader` 接收已经定位好的 FAT32 文件元数据（首 cluster、文件大小、FAT/Data 区 LBA 等），遍历 FAT chain，并输出**按文件逻辑顺序排列的连续 byte stream**。

本模块**不负责**：

- MBR/BPB/根目录扫描与文件名匹配（由 `fat32_scan` 等上游完成）；
- LFN / exFAT / GPT；
- BMP/VSEQ 格式解析；
- SDRAM/framebuffer 写入。

## 2. Baseline

- FAT32；sector 固定 512 byte。
- SDHC/SDXC block-LBA 语义。
- 支持连续与 fragmented FAT chain。
- `file_size` 是最终输出边界；EOC 不能替代 `file_size`。
- 若 `file_size` 尚未耗尽却遇到 EOC、free/非法 cluster，则失败。
- `SECTOR_BYTES` 当前必须为 512；`sectors_per_cluster=0` 非法。

## 3. 端口

| 端口 | 方向 | 位宽 | 语义 |
|---|---|---:|---|
| `clk` | in | 1 | SD/读卡时钟域 `clk_sdo` |
| `rst_n` | in | 1 | 异步低有效复位 |
| `start` | in | 1 | 单拍启动 |
| `start_cluster` | in | 32 | 文件首 cluster；非空文件需为合法 data cluster |
| `file_size` | in | 32 | 文件总 byte 数，亦为最终输出边界 |
| `fat_lba_base` | in | 32 | FAT 区起始 LBA |
| `data_lba_base` | in | 32 | data 区起始 LBA（cluster 2 对应 sector） |
| `sectors_per_cluster` | in | 8 | 每 cluster sector 数 |
| `sector_req` | out | 1 | sector 事务请求；完整 block 服务期间保持 1 |
| `sector_lba` | out | 32 | 当前请求 LBA |
| `sector_ready` | in | 1 | 下层 block reader 正在服务当前请求 |
| `din_valid` | in | 1 | 当前周期 `din` 有效；sector 内允许 stall |
| `din` | in | 8 | block reader 返回的 byte |
| `byte_valid` | out | 1 | 文件输出 byte 有效 |
| `byte_data` | out | 8 | 文件输出 byte |
| `done` | out | 1 | 当前任务结束；成功/失败都会置位 |
| `ok` | out | 1 | `done=1` 时：1=成功，0=失败 |

参数：

- `SECTOR_BYTES=512`：当前实现只接受 512。
- `STALL_TIMEOUT_CYCLES=200000`：连续无有效 byte 的最大等待周期数。

## 4. Sector transaction 约定

```text
fat32_file_reader                    block reader
      |                                  |
      | sector_req=1 + sector_lba ------>|
      |<------------- sector_ready=1     |
      |<------ din_valid + din byte0     |
      |<------ ... stall allowed ...     |
      |<------ din_valid + din byte511   |
      | sector_req=0 ------------------->|
      |<------------- sector_ready=0     |
      |         next request may start   |
```

规则：

1. 只有 `sector_ready && din_valid` 时消费一个输入 byte。
2. `sector_req` 是**事务电平**，不是单周期 pulse。
3. 每个 sector 必须物理消费 512 个有效 byte；最后一个文件 sector 中超出 `file_size` 的 padding 只消费、不产生 `byte_valid`。
4. 当前事务结束后进入 release wait，等待 `sector_ready=0` 再发下一请求，防止请求粘连。
5. `S_DATA_STREAM` / `S_FAT_STREAM` 内连续无有效 byte 达 `STALL_TIMEOUT_CYCLES` 时失败。

## 5. FAT32 地址计算

FAT entry：

```text
fat_entry_byte_index = cur_cluster * 4
fat_sector_lba       = fat_lba_base + floor(fat_entry_byte_index / 512)
fat_byte_offset      = fat_entry_byte_index mod 512
```

`fat_byte_offset` 必须使用 9 bit（合法边界可到 508）；当前 RTL 已按 9 bit 实现。

FAT entry 按 little-endian 读取，随后屏蔽高 4 bit：

```text
fat_value = entry & 0x0FFFFFFF
```

数据 sector：

```text
data_lba = data_lba_base
         + (cur_cluster - 2) * sectors_per_cluster
         + sector_in_cluster
```

## 6. 成功/失败语义

成功：

- `file_size==0`；或
- 恰好输出 `file_size` 个 byte，并结束当前物理 sector transaction。

失败：

- `sectors_per_cluster==0`；
- 非空文件但首 cluster 非法；
- block reader 长时间 stall；
- 文件尚未结束却 premature EOC；
- FAT next cluster 为 free/非法/非 data cluster。

## 7. 成熟度说明

当前仅标记 **[U]**。这意味着 `fat32_file_reader` 单模块在 ModelSim adversarial TB 中通过；**不表示** `fat32_scan → fat32_file_reader → bmp_pixel_stream → framebuffer` 已达到 `[C]`。
