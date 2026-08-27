@echo off
echo Run install_to_MT5.bat first, then compile in MetaEditor.
echo.
echo Starting MetaEditor...
start "" "metaeditor64.exe" 2>nul
if errorlevel 1 start "" "metaeditor.exe" 2>nul
echo If MetaEditor did not open, press F4 in MT5.
pause
