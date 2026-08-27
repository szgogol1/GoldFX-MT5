@echo off
chcp 65001 >nul
setlocal
echo ========================================
echo  推送 GoldFX 到 GitHub: szgogol1/GoldFX-MT5
echo ========================================
echo.

REM 若当前目录不是仓库根，请先 cd 到含 Experts/Include 的目录
if not exist "Experts\GoldFX_Intraday\GoldFX_Intraday.mq5" (
  echo [提示] 未在当前目录找到 Experts\GoldFX_Intraday
  echo 请先进入工程根目录，例如：
  echo   cd /d D:\你的工程目录
  echo 然后再运行本脚本。
  echo.
)

where git >nul 2>&1
if errorlevel 1 (
  echo [错误] 未安装 Git。请先安装: https://git-scm.com/download/win
  pause
  exit /b 1
)

git rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
  echo 当前不是 git 仓库，正在初始化...
  git init
  git add -A
  git commit -m "feat: GoldFX MT5 framework"
  git branch -M main
)

git remote remove github 2>nul
git remote add github https://github.com/szgogol1/GoldFX-MT5.git
echo 远程已设置: https://github.com/szgogol1/GoldFX-MT5.git
echo.
echo 正在推送 main ...
git push -u github main
if errorlevel 1 (
  echo.
  echo 推送失败。请确认：
  echo  1) 已在 Cursor/浏览器登录 GitHub 账号 szgogol1
  echo  2) 仓库已创建: https://github.com/szgogol1/GoldFX-MT5
  echo  3) 弹出登录窗口时完成授权
  pause
  exit /b 1
)

echo.
echo [成功] 请打开: https://github.com/szgogol1/GoldFX-MT5
echo 本机下载到 D 盘:
echo   git clone https://github.com/szgogol1/GoldFX-MT5.git D:\00xauusd
echo.
pause
endlocal
