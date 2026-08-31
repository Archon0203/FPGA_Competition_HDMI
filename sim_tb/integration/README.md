# integration testbenches

## P0 full media chain

```text
vsim -c -do ../sim_tb/integration/run_p0_media_chain.do
```

范围：

`fat32_file_reader -> bmp_parser/bmp_pixel_stream -> framebuffer -> mock SDRAM -> line prefetch/buffer -> display RGB`

实测：CASE-GOLDEN+CASE0~CASE3 全部 PASS（checks=1698）。完整 P0 media chain 已标 `[C]`；本 TB 作为 P0 冻结回归保留。
