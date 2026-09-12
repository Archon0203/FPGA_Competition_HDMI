if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

set APUG011 ../src/vendor/anlogic/apug011
set SIMINC ../sim_tb/framebuf/apug011_model_125m_include

vlog -mfcu -work work +incdir+$SIMINC \
    $SIMINC/global_def.v \
    $APUG011/enc_file/sdr_init_ref.enc.v \
    $APUG011/enc_file/sdr_wrrd.enc.v \
    $APUG011/enc_file/sdr_as_ram.enc.v \
    ../src/framebuf/p1_sdram_cached_adapter.v \
    ../src/top/apug011_core_wrapper.v \
    $APUG011/model/IS42s32200.v \
    ../sim_tb/framebuf/tb_p1_sdram_cached_adapter_apug011_official.v

# Model-safe 125 MHz, 180-degree shifted clock.  This validates protected-core
# protocol compatibility; final hardware timing remains the TD 150 MHz build.
vsim -t ps -voptargs=+acc +notimingchecks \
    -gHALF_CLK_PS=4000 -gSFT_OFFSET_PS=4000 \
    work.tb_p1_sdram_cached_adapter_apug011_official
run -all
quit -f
