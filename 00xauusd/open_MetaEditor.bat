@echo off
chcp 65001 >nul
echo 请先运行 install_to_MT5.bat 完成复制，再在 MetaEditor 中打开并编译。
echo.
echo 正在尝试启动 MetaEditor...
start "" "metaeditor64.exe" 2>nul
if errorlevel 1 start "" "metaeditor.exe" 2>nul
echo 若未自动打开，请在 MT5 中按 F4。
pause
