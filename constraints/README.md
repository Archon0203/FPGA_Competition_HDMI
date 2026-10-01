# TD6.2.1 active constraints

本目录只保存当前两个长期主工程的角色约束。RTL 统一从仓库根目录 `src/` 共享，不在 TD 工程目录复制源码。

- `master/master.adc` + `master/master.sdc`：`FPGA_Competition_HDMI_MASTER.al`
- `slave/slave.adc` + `slave/slave.sdc`：`FPGA_Competition_HDMI_SLAVE.al`

当前 M1 真板已验证的板间接线保持不变：Master J1-8(TX/J13) → Slave J1-4(RX/F13)，Slave J1-8(TX/J13) → Master J1-4(RX/F13)，J1-12 GND ↔ GND。

后续 M2~M6 只演进这两个工程及各自约束；不得再新建第三个 active `.al`。历史 P1 约束可从 Git 历史或 `docs/develop_records/` 的记录中追溯，不作为当前构建入口。
