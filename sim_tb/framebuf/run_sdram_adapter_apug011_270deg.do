transcript on
if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

# P1-02A standalone phase probe: 270deg (6000 ps).
# The bundled vendor IS42s32200 is a -7 model (tCK>=7ns, tRCD>=21ns), so use
# 125 MHz here.  This is a MODEL-COMPATIBLE SIMULATION setting, not the final
# HX4S20C timing claim.  Vendor RTL/model files remain untouched.
set APUG011 ../src/vendor/anlogic/apug011
set SIMINC ../sim_tb/framebuf/apug011_model_125m_include

vlog -mfcu -work work +incdir+$SIMINC \
    $SIMINC/global_def.v \
    $APUG011/enc_file/sdr_init_ref.enc.v \
    $APUG011/enc_file/sdr_wrrd.enc.v \
    $APUG011/enc_file/sdr_as_ram.enc.v \
    ../src/framebuf/sdram_adapter.v \
    ../src/top/apug011_core_wrapper.v \
    $APUG011/model/IS42s32200.v \
    ../sim_tb/framebuf/tb_sdram_adapter_apug011_official.v

# 125 MHz, 180-degree Sdr_clk_sft: same nominal phase relation as vendor PLL.
vsim -t ps -voptargs=+acc +notimingchecks \
    -gHALF_CLK_PS=4000 -gSFT_OFFSET_PS=6000 \
    work.tb_sdram_adapter_apug011_official
run -all
quit -f
