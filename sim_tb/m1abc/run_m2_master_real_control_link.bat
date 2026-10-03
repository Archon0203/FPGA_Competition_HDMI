@echo off
cd /d %~dp0
vsim -c -do run_m2_master_real_control_link.do
