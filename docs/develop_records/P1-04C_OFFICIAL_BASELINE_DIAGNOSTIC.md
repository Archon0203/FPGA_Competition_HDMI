# P1-04C official-baseline diagnostic

P1-04B implemented cleanly at 25/125 MHz but produced no monitor signal on board.
Inspection of the physically working `lab_ex4_tf` source found three material behavioral differences:

1. Working design holds HDMI reset for ~20 ms after PLL lock; P1-04B released vendor reset immediately on PLL lock.
2. Working design issues a one-shot EDID read trigger after reset and uses `IIC_SCL_DIV=250`; P1-04B tied EDID trigger low and used 125.
3. Working design feeds APUG092 a free-running raster AXIS stream and does not gate source start on `O_axis_s_ready`; P1-04B's adapter waited for ready before beginning a line. This can deadlock if APUG092 does not pre-assert ready before video begins.

P1-04C therefore changes only the board smoke-test source/startup behavior while retaining the already proven official 50->25/125 MHz PLL parameters, APUG092 protected core, EG PHY and HDMI_B ADC pins.

Expected board image: 640x480 vertical bars white/yellow/cyan/green/magenta/red/blue/black.
