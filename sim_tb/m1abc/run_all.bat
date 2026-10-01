@echo off
setlocal
cd /d "%~dp0"

where vsim >nul 2>nul
if errorlevel 1 (
  echo [ERROR] vsim.exe was not found in PATH.
  echo Please open a QuestaSim command prompt or add D:\Questasim64_10.7c\win64 to PATH.
  pause
  exit /b 2
)

if exist transcript_m1abc.txt del /q transcript_m1abc.txt
vsim -c -do run_all.do -l transcript_m1abc.txt
set RC=%ERRORLEVEL%

echo.
if not "%RC%"=="0" (
  echo [FAIL] Questa returned code %RC%.
  echo See: %CD%\transcript_m1abc.txt
  pause
  exit /b %RC%
)

echo [DONE] M1ABC regression finished.
echo Check transcript_m1abc.txt for seven PASS lines and the final ALL marker.
pause
exit /b 0
