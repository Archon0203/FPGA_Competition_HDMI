@echo off
cd /d %~dp0
vsim -c -do run_m1c_coordinator_realmedia.do
