@echo off
cd /d %~dp0
vsim -c -do run_m2_open_dispatcher.do
