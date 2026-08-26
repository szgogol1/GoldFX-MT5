@echo off
chcp 65001 >nul
setlocal EnableExtensions

echo ========================================
echo  GoldFX -^> MT5 安装程序
echo  源目录固定为: D:\00xauusd
echo ========================================
echo.

set "SRC=D:\00xauusd"
if not exist "%SRC%\Experts\GoldFX_Intraday\GoldFX_Intraday.mq5" (
  echo [错误] 未找到 %SRC%\Experts\GoldFX_Intraday\GoldFX_Intraday.mq5
  echo 请先把整个程序包放到 D:\00xauusd\
  echo.
  pause
  exit /b 1
)

echo 请打开 MT5: 文件 -^> 打开数据文件夹 -^> 进入 MQL5 文件夹
echo 然后把该 MQL5 完整路径粘贴到下方（以 MQL5 结尾）
echo 示例: C:\Users\Demo\AppData\Roaming\MetaQuotes\Terminal\XXXXXXXX\MQL5
echo.
set /p "MQL5=MQL5路径: "

if "%MQL5%"=="" (
  echo [错误] 路径为空
  pause
  exit /b 1
)

rem 去掉末尾反斜杠
if "%MQL5:~-1%"=="\" set "MQL5=%MQL5:~0,-1%"

if not exist "%MQL5%" (
  echo [错误] 路径不存在: %MQL5%
  pause
  exit /b 1
)

echo.
echo 正在复制...
mkdir "%MQL5%\Experts\GoldFX_Intraday" 2>nul
mkdir "%MQL5%\Include\GoldFX" 2>nul
mkdir "%MQL5%\Presets" 2>nul

xcopy /E /I /Y "%SRC%\Experts\GoldFX_Intraday\*" "%MQL5%\Experts\GoldFX_Intraday\"
xcopy /E /I /Y "%SRC%\Include\GoldFX\*"           "%MQL5%\Include\GoldFX\"
xcopy /Y       "%SRC%\Presets\*"                  "%MQL5%\Presets\"

if errorlevel 1 (
  echo [警告] 复制过程可能有问题，请检查上方输出
) else (
  echo.
  echo [完成] 已安装到:
  echo   %MQL5%\Experts\GoldFX_Intraday
  echo   %MQL5%\Include\GoldFX
  echo   %MQL5%\Presets
  echo.
  echo 下一步: 打开 MetaEditor, 打开 GoldFX_Intraday.mq5, 按 F7 编译
)

echo.
pause
endlocal
