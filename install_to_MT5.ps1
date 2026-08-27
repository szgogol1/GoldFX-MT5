# GoldFX -> MT5 installer (PowerShell, UTF-8 safe)
param(
    [string]$Mql5Path = ""
)

$ErrorActionPreference = "Stop"

$Src = $PSScriptRoot
$ea = Join-Path $Src "Experts\GoldFX_Intraday\GoldFX_Intraday.mq5"
if (-not (Test-Path $ea)) {
    Write-Host "[ERROR] Not found: $ea" -ForegroundColor Red
    Write-Host "Run this script from the GoldFX-MT5 repo root."
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

$destIntraday = Join-Path $Mql5Path "Experts\GoldFX_Intraday"
$destBasis    = Join-Path $Mql5Path "Experts\GoldFX_BasisArb"
$destInclude  = Join-Path $Mql5Path "Include\GoldFX"
$destIndi     = Join-Path $Mql5Path "Indicators\GoldFX"
$destPresets  = Join-Path $Mql5Path "Presets"

New-Item -ItemType Directory -Force -Path $destIntraday, $destBasis, $destInclude, $destIndi, $destPresets | Out-Null

Copy-Item -Path (Join-Path $Src "Experts\GoldFX_Intraday\*") -Destination $destIntraday -Recurse -Force
if (Test-Path (Join-Path $Src "Experts\GoldFX_BasisArb")) {
    Copy-Item -Path (Join-Path $Src "Experts\GoldFX_BasisArb\*") -Destination $destBasis -Recurse -Force
}
Copy-Item -Path (Join-Path $Src "Include\GoldFX\*") -Destination $destInclude -Recurse -Force
if (Test-Path (Join-Path $Src "Indicators\GoldFX")) {
    Copy-Item -Path (Join-Path $Src "Indicators\GoldFX\*") -Destination $destIndi -Recurse -Force
}
if (Test-Path (Join-Path $Src "Presets")) {
    Copy-Item -Path (Join-Path $Src "Presets\*") -Destination $destPresets -Force
}

Write-Host "[OK] Installed." -ForegroundColor Green
Write-Host "  $destIntraday"
Write-Host "  $destBasis"
Write-Host "  $destInclude"
Write-Host "  $destIndi"
Write-Host "  $destPresets"
Write-Host "Next: MetaEditor F7 compile:"
Write-Host "  GoldFX_Intraday.mq5"
Write-Host "  GoldFX_BasisArb.mq5"
Write-Host "  Indicators\GoldFX\GoldFX_BasisCompare.mq5"
