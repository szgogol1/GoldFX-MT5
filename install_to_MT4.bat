@echo off
setlocal EnableExtensions

set "SRC=%~dp0"
if "%SRC:~-1%"=="\" set "SRC=%SRC:~0,-1%"

if not exist "%SRC%\Experts\GoldFX_BasisPro\GoldFX_BasisPro.mq4" (
  echo [ERROR] Cannot find Experts\GoldFX_BasisPro\GoldFX_BasisPro.mq4
  echo Tried: %SRC%
  pause
  exit /b 1
)

echo GoldFX MT4 BasisPro Installer
echo Source: %SRC%
echo.
set /p "MQL4=MQL4 path (e.g. C:\Program Files\MetaTrader 4\MQL4): "

if "%MQL4%"=="" (
  echo [ERROR] Empty path.
  pause
  exit /b 1
)

if "%MQL4:~-1%"=="\" set "MQL4=%MQL4:~0,-1%"

if not exist "%MQL4%" (
  echo [ERROR] Path not found: %MQL4%
  pause
  exit /b 1
)

if not exist "%MQL4%\Experts\GoldFX_BasisPro" mkdir "%MQL4%\Experts\GoldFX_BasisPro"
if not exist "%MQL4%\Indicators\GoldFX_BasisPro" mkdir "%MQL4%\Indicators\GoldFX_BasisPro"
if not exist "%MQL4%\Presets" mkdir "%MQL4%\Presets"

xcopy /E /I /Y "%SRC%\Experts\GoldFX_BasisPro\*" "%MQL4%\Experts\GoldFX_BasisPro\"
xcopy /E /I /Y "%SRC%\Indicators\GoldFX_BasisPro\*" "%MQL4%\Indicators\GoldFX_BasisPro\"
if exist "%SRC%\MT4\Presets" xcopy /Y "%SRC%\MT4\Presets\*" "%MQL4%\Presets\"

echo.
echo [OK] Copied. In MetaEditor compile:
echo   Experts\GoldFX_BasisPro\GoldFX_BasisPro.mq4
echo   Indicators\GoldFX_BasisPro\GoldFX_BasisPro_Overlay.mq4
echo   Indicators\GoldFX_BasisPro\GoldFX_BasisPro_Spread.mq4
echo.
echo Usage: Open spot chart (XAUUSD.s) M15
echo   1) Attach EA GoldFX_BasisPro (panel + auto/manual trade)
echo   2) Attach both indicators for K-line + spread chart
echo Set InpFutSymbol=GC on all three.
pause
endlocal
