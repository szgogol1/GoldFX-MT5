@echo off
setlocal EnableExtensions

set "SRC=%~dp0"
if "%SRC:~-1%"=="\" set "SRC=%SRC:~0,-1%"

if not exist "%SRC%\Experts\GoldFX_Intraday\GoldFX_Intraday.mq5" (
  echo [ERROR] Cannot find Experts\GoldFX_Intraday\GoldFX_Intraday.mq5
  echo Tried: %SRC%
  pause
  exit /b 1
)

echo GoldFX MT5 Installer
echo Source: %SRC%
echo.
set /p "MQL5=MQL5 path: "

if "%MQL5%"=="" (
  echo [ERROR] Empty path.
  pause
  exit /b 1
)

if "%MQL5:~-1%"=="\" set "MQL5=%MQL5:~0,-1%"

if not exist "%MQL5%" (
  echo [ERROR] Path not found: %MQL5%
  pause
  exit /b 1
)

if not exist "%MQL5%\Experts\GoldFX_Intraday" mkdir "%MQL5%\Experts\GoldFX_Intraday"
if not exist "%MQL5%\Experts\GoldFX_BasisArb" mkdir "%MQL5%\Experts\GoldFX_BasisArb"
if not exist "%MQL5%\Experts\GoldFX_OrderFlow" mkdir "%MQL5%\Experts\GoldFX_OrderFlow"
if not exist "%MQL5%\Include\GoldFX" mkdir "%MQL5%\Include\GoldFX"
if not exist "%MQL5%\Presets" mkdir "%MQL5%\Presets"

xcopy /E /I /Y "%SRC%\Experts\GoldFX_Intraday\*" "%MQL5%\Experts\GoldFX_Intraday\"
xcopy /E /I /Y "%SRC%\Experts\GoldFX_BasisArb\*" "%MQL5%\Experts\GoldFX_BasisArb\"
xcopy /E /I /Y "%SRC%\Experts\GoldFX_OrderFlow\*" "%MQL5%\Experts\GoldFX_OrderFlow\"
xcopy /E /I /Y "%SRC%\Include\GoldFX\*" "%MQL5%\Include\GoldFX\"
if exist "%SRC%\Presets" xcopy /Y "%SRC%\Presets\*" "%MQL5%\Presets\"

echo.
echo [OK] Done. Compile in MetaEditor:
echo   GoldFX_Intraday.mq5
echo   GoldFX_BasisArb.mq5
echo   GoldFX_OrderFlow.mq5
pause
endlocal
