@echo off
setlocal EnableExtensions

set "SRC=%~dp0"
if "%SRC:~-1%"=="\" set "SRC=%SRC:~0,-1%"

if not exist "%SRC%\MT4\Experts\GoldFX_BasisArb.mq4" (
  echo [ERROR] Cannot find MT4\Experts\GoldFX_BasisArb.mq4
  echo Tried: %SRC%
  pause
  exit /b 1
)

echo GoldFX MT4 Installer
echo Source: %SRC%\MT4
echo.
echo Paste your MT4 MQL4 folder path
echo   Example: C:\Users\You\AppData\Roaming\MetaQuotes\Terminal\XXXX\MQL4
echo   Tip: In MT4 open File -^> Open Data Folder, then enter the MQL4 folder
echo.
set /p "MQL4=MQL4 path: "

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

if not exist "%MQL4%\Experts" mkdir "%MQL4%\Experts"
if not exist "%MQL4%\Indicators" mkdir "%MQL4%\Indicators"
if not exist "%MQL4%\Include\GoldFX" mkdir "%MQL4%\Include\GoldFX"
if not exist "%MQL4%\Presets" mkdir "%MQL4%\Presets"

copy /Y "%SRC%\MT4\Experts\GoldFX_BasisArb.mq4" "%MQL4%\Experts\"
copy /Y "%SRC%\MT4\Indicators\GoldFX_BasisCompare.mq4" "%MQL4%\Indicators\"
xcopy /E /I /Y "%SRC%\MT4\Include\GoldFX\*" "%MQL4%\Include\GoldFX\"
if exist "%SRC%\MT4\Presets" xcopy /Y "%SRC%\MT4\Presets\*" "%MQL4%\Presets\"

echo.
echo [OK] Installed to:
echo   %MQL4%\Experts\GoldFX_BasisArb.mq4
echo   %MQL4%\Indicators\GoldFX_BasisCompare.mq4
echo   %MQL4%\Include\GoldFX\
echo.
echo Next steps:
echo   1. Open MetaEditor (F4 in MT4)
echo   2. Compile Experts\GoldFX_BasisArb.mq4  (F7)
echo   3. Compile Indicators\GoldFX_BasisCompare.mq4  (F7)
echo   4. Attach indicator + EA on XAUUSD chart, set InpFutSymbol
echo   5. Tools - Options - Expert Advisors: allow WebRequest https://api.telegram.org
pause
endlocal
