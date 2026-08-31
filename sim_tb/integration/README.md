# integration testbenches

## P0 full media chain

```text
vsim -c -do ../sim_tb/integration/run_p0_media_chain.do
```

范围：

`fat32_file_reader -> bmp_parser/bmp_pixel_stream -> framebuffer -> mock SDRAM -> line prefetch/buffer -> display RGB`

本 TB PASS 后才允许标完整 P0 media chain `[C]`。
