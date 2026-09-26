# src/app

- `app_scenario.v`：历史应用场景状态机单元。
- `media_command_controller.v`：主板 C 线 I0 命令控制器。将已消抖按键、拨码和 catalog metadata 转为 `media_cmd_valid/ready/image_id/mode`；只表达高层媒体意图，不产生 loader、SDRAM、framebuffer 或 GPIO 操作。忙碌期间保持 command payload 稳定，并合并后续选图请求。
