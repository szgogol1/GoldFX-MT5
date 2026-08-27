# GoldFX -> MT5 installer (PowerShell, UTF-8 safe)
param(
    [string]$Mql5Path = ""
)

$ErrorActionPreference = "Stop"

$Src = $PSScriptRoot
if (Test-Path (Join-Path $Src "00xauusd\Experts\GoldFX_Intraday\GoldFX_Intraday.mq5")) {
    $Src = Join-Path $Src "00xauusd"
}

$ea = Join-Path $Src "Experts\GoldFX_Intraday\GoldFX_Intraday.mq5"
if (-not (Test-Path $ea)) {
    Write-Host "[ERROR] Not found: $ea" -ForegroundColor Red
    Write-Host "Run this script from 00xauusd folder or repo root."
    exit 1
}

Write-Host "GoldFX MT5 Installer" -ForegroundColor Cyan
Write-Host "Source: $Src"

if ([string]::IsNullOrWhiteSpace($Mql5Path)) {
    $Mql5Path = Read-Host "MQL5 path (from MT5: File -> Open Data Folder -> MQL5)"
}

$Mql5Path = $Mql5Path.Trim().TrimEnd('\')
if (-not (Test-Path $Mql5Path)) {
    Write-Host "[ERROR] Path not found: $Mql5Path" -ForegroundColor Red
    exit 1
}

$destExperts = Join-Path $Mql5Path "Experts\GoldFX_Intraday"
$destInclude = Join-Path $Mql5Path "Include\GoldFX"
$destPresets = Join-Path $Mql5Path "Presets"

New-Item -ItemType Directory -Force -Path $destExperts, $destInclude, $destPresets | Out-Null

Copy-Item -Path (Join-Path $Src "Experts\GoldFX_Intraday\*") -Destination $destExperts -Recurse -Force
Copy-Item -Path (Join-Path $Src "Include\GoldFX\*") -Destination $destInclude -Recurse -Force
if (Test-Path (Join-Path $Src "Presets")) {
    Copy-Item -Path (Join-Path $Src "Presets\*") -Destination $destPresets -Force
}

Write-Host "[OK] Installed." -ForegroundColor Green
Write-Host "  $destExperts"
Write-Host "  $destInclude"
Write-Host "  $destPresets"
Write-Host "Next: MetaEditor F7 compile GoldFX_Intraday.mq5"
