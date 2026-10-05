# TD6.2.1 active constraints

本目录只保存两个长期工程的角色约束：

- `master/master.adc` + `master/master.sdc` → `FPGA_Competition_HDMI_MASTER.al`
- `slave/slave.adc` + `slave/slave.sdc` → `FPGA_Competition_HDMI_SLAVE.al`

RTL 统一从仓库根目录 `src/` 共享。

## FIX6 双板连接关键映射

当前 14 线图片链使用 J1。FIX6 已按原理图重新核对 J1 物理针号、板上电阻网络和 FPGA 球位：

| 信号 | J1 | FPGA ball |
|---|---:|---|
| `link_data[0]` | 1 | D14 |
| `link_data[1]` | 2 | G11 |
| `link_data[2]` | 3 | G12 |
| `uart_rx` | 4 | F13 |
| `link_data[3]` | 5 | H13 |
| `link_data[4]` | 6 | H14 |
| `link_data[5]` | 7 | J14 |
| `uart_tx` | 8 | J13 |
| `link_data[6]` | 9 | K12 |
| `link_req` | 10 | L14 |
| GND | 12 | GND |
| `link_ack` | 13 | M14 |
| `display_published` | 32 | L16 |

两板按相同 J1 编号连接对应媒体信号，并另接第二根 GND；不要互连两板 5 V。

修改任何 `.adc` 后必须重新执行完整 synthesis → P&R → STA → BitGen。`tools/run_full_project_audit_questa.py` 会检查上述关键映射，避免再次出现“两边约束一致但都映射到错误物理针”的问题。
