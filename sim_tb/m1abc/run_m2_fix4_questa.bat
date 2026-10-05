@echo off
setlocal
pushd "%~dp0"

echo === M2 FIX4 regression: B-line ===
call run_m2_b_line_questa.bat
if errorlevel 1 goto :fail

echo.
echo === M2 FIX4 regression: HDMI lock recovery ===
call run_m2_hdmi_recovery_questa.bat
if errorlevel 1 goto :fail

echo.
echo PASS: M2 FIX4 B-line + HDMI recovery regressions completed.
popd
exit /b 0

:fail
echo.
echo FAIL: M2 FIX4 regression failed.
popd
exit /b 1
