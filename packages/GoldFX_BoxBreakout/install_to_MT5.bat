@echo off
chcp 65001 >nul
setlocal
echo GoldFX BoxBreakout — 独立安装到 MT5
echo.
set /p MQL5=请粘贴 MT5 的 MQL5 路径: 
if "%MQL5%"=="" (
  echo 路径为空，已取消。
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_to_MT5.ps1" -Mql5Path "%MQL5%"
pause
