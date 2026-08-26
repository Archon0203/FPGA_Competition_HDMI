# sim — 仿真代码与脚本

存放 testbench（`tb_<module>.v`）与 ModelSim 运行脚本（`.do`）。

> 本目录是**仿真源码**，纳入版本控制。ModelSim 运行产生的中间产物放 `sim_tb/`（已 gitignore）。

## 结构约定
- `tb_<module>.v`：与被测模块一一对应。
- `run_<module>.do`：编译 + 运行 + 输出通过/失败，可一键 `do run_xxx.do`。
- `common/`：可复用的公共测试助手（时钟/复位/数据生成/校验）。

## 重点先写
`tb_clk_gen` → `tb_vga_timing` → `tb_sdram_ctrl` → `tb_bmp_parser` → `tb_vseq_reader` → `tb_key_filter` → `tb_menu_fsm`。

