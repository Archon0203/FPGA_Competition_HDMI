@echo off
setlocal
pushd "%~dp0"

if exist work rmdir /s /q work
if exist questa_mailbox_reset.log del /q questa_mailbox_reset.log
if exist questa_remote_frame.log del /q questa_remote_frame.log
if exist questa_remote_idle_resync.log del /q questa_remote_idle_resync.log

vlib work
if errorlevel 1 goto :fail

vlog -work work +acc ^
  ..\..\src\dual_board\m2_gpio_mailbox.v ^
  ..\..\src\dual_board\m2_remote_frame.v ^
  tb_m2_mailbox_reset_recovery.v ^
  tb_m2_remote_frame_link.v ^
  tb_m2_remote_frame_idle_resync.v
if errorlevel 1 goto :fail

echo.
echo [1/3] Running mailbox independent-reset recovery test...
vsim -c -l questa_mailbox_reset.log -voptargs=+acc work.tb_m2_mailbox_reset_recovery -do "run -all; quit -f"
if errorlevel 1 goto :fail
findstr /L /C:"PASS: mailbox survives independent TX/RX reset and backpressure" questa_mailbox_reset.log >nul
if errorlevel 1 goto :fail_mailbox

echo.
echo [2/3] Running remote-frame mailbox regression...
vsim -c -l questa_remote_frame.log -voptargs=+acc work.tb_m2_remote_frame_link -do "run -all; quit -f"
if errorlevel 1 goto :fail
findstr /L /C:"PASS: remote frame mailbox, async clocks, backpressure, CRC rejection, recovery" questa_remote_frame.log >nul
if errorlevel 1 goto :fail_remote

echo.
echo [3/3] Running remote-frame idle/resync regression...
vsim -c -l questa_remote_idle_resync.log -voptargs=+acc work.tb_m2_remote_frame_idle_resync -do "run -all; quit -f"
if errorlevel 1 goto :fail
findstr /L /C:"PASS: remote-frame idle garbage is discarded and next header resynchronizes" questa_remote_idle_resync.log >nul
if errorlevel 1 goto :fail_idle

echo.
echo PASS: M2 B-line QuestaSim regressions completed.
popd
exit /b 0

:fail_mailbox
echo.
echo FAIL: mailbox reset-recovery test did not report PASS.
echo See: %CD%\questa_mailbox_reset.log
popd
exit /b 1

:fail_remote
echo.
echo FAIL: remote-frame regression did not report PASS.
echo See: %CD%\questa_remote_frame.log
popd
exit /b 1

:fail_idle
echo.
echo FAIL: remote-frame idle/resync test did not report PASS.
echo See: %CD%\questa_remote_idle_resync.log
popd
exit /b 1

:fail
echo.
echo FAIL: M2 B-line QuestaSim regression failed.
popd
exit /b 1
