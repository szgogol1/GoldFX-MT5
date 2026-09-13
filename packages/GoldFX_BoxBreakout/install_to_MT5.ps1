param(
    [string]$Mql5Path = ""
)

$ErrorActionPreference = "Stop"
$Src = $PSScriptRoot

$ea = Join-Path $Src "Experts\GoldFX_BoxBreakout\GoldFX_BoxBreakout.mq5"
if (-not (Test-Path $ea)) {
    Write-Host "[ERROR] 找不到 $ea" -ForegroundColor Red
    Write-Host "请在 GoldFX_BoxBreakout 包根目录运行本脚本。"
    exit 1
}

Write-Host "GoldFX BoxBreakout 独立安装器" -ForegroundColor Cyan
Write-Host "源目录: $Src"

if ([string]::IsNullOrWhiteSpace($Mql5Path)) {
    $Mql5Path = Read-Host "请输入 MT5 的 MQL5 路径（文件→打开数据文件夹→MQL5）"
}

$Mql5Path = $Mql5Path.Trim().TrimEnd('\')
if (-not (Test-Path $Mql5Path)) {
    Write-Host "[ERROR] 路径不存在: $Mql5Path" -ForegroundColor Red
    exit 1
}

$destExpert = Join-Path $Mql5Path "Experts\GoldFX_BoxBreakout"
$destInclude = Join-Path $Mql5Path "Include\GoldFX_Box"
$destPresets = Join-Path $Mql5Path "Presets"

New-Item -ItemType Directory -Force -Path $destExpert, $destInclude, $destPresets | Out-Null

Copy-Item -Path (Join-Path $Src "Experts\GoldFX_BoxBreakout\*") -Destination $destExpert -Recurse -Force
Copy-Item -Path (Join-Path $Src "Include\GoldFX_Box\*") -Destination $destInclude -Recurse -Force
Copy-Item -Path (Join-Path $Src "Presets\*") -Destination $destPresets -Force

Write-Host "[OK] 已安装独立箱体包（EA 同目录含 .mqh，可直接 F7）" -ForegroundColor Green
Write-Host "  $destExpert"
Write-Host "  $destInclude"
Write-Host "  $destPresets"
Write-Host "下一步: MetaEditor 打开 GoldFX_BoxBreakout.mq5，按 F7 编译"
