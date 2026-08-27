# 将当前仓库推送到 https://github.com/szgogol1/GoldFX-MT5
# 用法：在仓库根目录执行
#   powershell -ExecutionPolicy Bypass -File .\scripts\push_to_github.ps1

$ErrorActionPreference = "Stop"
$RepoUrl = "https://github.com/szgogol1/GoldFX-MT5.git"
$Branch  = "main"

Write-Host "=== GoldFX -> GitHub (szgogol1/GoldFX-MT5) ===" -ForegroundColor Cyan

# 定位到仓库根（脚本在 scripts/ 下）
$Root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $Root ".git"))) {
  $Root = Get-Location
}
Set-Location $Root
Write-Host "工作目录: $Root"

# 检查 git
git --version | Out-Null

# 添加/更新 remote
$existing = git remote 2>$null
if ($existing -match "(?m)^github$") {
  git remote set-url github $RepoUrl
  Write-Host "已更新 remote: github -> $RepoUrl"
} else {
  git remote add github $RepoUrl
  Write-Host "已添加 remote: github -> $RepoUrl"
}

git remote -v

Write-Host ""
Write-Host "正在推送 $Branch ..." -ForegroundColor Yellow
git push -u github $Branch

if ($LASTEXITCODE -eq 0) {
  Write-Host ""
  Write-Host "成功！请打开: https://github.com/szgogol1/GoldFX-MT5" -ForegroundColor Green
  Write-Host "本机下载:" -ForegroundColor Green
  Write-Host "  git clone https://github.com/szgogol1/GoldFX-MT5.git D:\GoldFX-MT5"
} else {
  Write-Host ""
  Write-Host "推送失败。常见原因：" -ForegroundColor Red
  Write-Host "  1) 尚未在 GitHub 创建空仓库 GoldFX-MT5"
  Write-Host "  2) Cursor 未完成 GitHub Connect / 未授权"
  Write-Host "  3) 仓库非空且历史冲突"
  Write-Host "请先打开 https://github.com/new 创建空仓库后再运行本脚本。"
  exit 1
}
