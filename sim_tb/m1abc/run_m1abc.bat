@echo off
setlocal
cd /d "%~dp0"
vsim -c -do run_m1abc.do
if errorlevel 1 (
  echo.
  echo Questa returned an error. See transcript_m1abc.txt
  pause
  exit /b 1
)
echo.
echo Finished. Check transcript_m1abc.txt for four PASS lines.
pause
