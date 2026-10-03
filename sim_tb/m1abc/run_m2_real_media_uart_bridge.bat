@echo off
setlocal
cd /d "%~dp0"
where vsim >nul 2>nul
if errorlevel 1 (
  echo [ERROR] vsim.exe was not found in PATH.
  echo Open a QuestaSim 10.7c command prompt or add its win64 directory to PATH.
  exit /b 2
)
vsim -c -do run_m2_real_media_uart_bridge.do -l transcript_m2_real_media_uart_bridge.txt
exit /b %ERRORLEVEL%
