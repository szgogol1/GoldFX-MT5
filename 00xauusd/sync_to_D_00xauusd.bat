@echo off
chcp 65001 >nul
echo 将当前目录同步到 D:\00xauusd\ （覆盖）
echo 若你已经在 D:\00xauusd 运行本脚本，可跳过。
echo.
set "DEST=D:\00xauusd"
set "HERE=%~dp0"
if /I "%HERE%"=="%DEST%\" (
  echo 当前已在 D:\00xauusd\ ，无需再同步。
  pause
  exit /b 0
)
mkdir "%DEST%" 2>nul
xcopy /E /I /Y "%HERE%*" "%DEST%\"
echo.
echo 已同步到 %DEST%
echo 请到该目录运行 install_to_MT5.bat
pause
