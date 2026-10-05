@echo off
setlocal
cd /d "%~dp0"

if exist work rmdir /s /q work
vlib work || exit /b 1

vlog -work work +acc ..\..\src\display\m2_hdmi_lock_supervisor.v tb_m2_hdmi_lock_supervisor.v
if errorlevel 1 exit /b 1

if exist questa_hdmi_recovery.log del /q questa_hdmi_recovery.log
vsim -c -l questa_hdmi_recovery.log -voptargs="+acc" work.tb_m2_hdmi_lock_supervisor -do "run -all; quit -f"
if errorlevel 1 exit /b 1

findstr /c:"PASS: HDMI lock supervisor reset/acquire/recovery behavior" questa_hdmi_recovery.log >nul
if errorlevel 1 (
  echo FAIL: HDMI recovery regression did not report PASS.
  exit /b 1
)

echo PASS: M2 HDMI recovery QuestaSim regression completed.
exit /b 0
