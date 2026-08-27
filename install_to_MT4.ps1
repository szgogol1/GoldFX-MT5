# GoldFX -> MT4 installer (PowerShell)
param(
    [string]$Mql4Path = ""
)

$ErrorActionPreference = "Stop"

$SrcRoot = $PSScriptRoot
$Src = Join-Path $SrcRoot "MT4"
$ea = Join-Path $Src "Experts\GoldFX_BasisArb.mq4"
if (-not (Test-Path $ea)) {
    Write-Host "[ERROR] Not found: $ea" -ForegroundColor Red
    Write-Host "Run this script from the GoldFX-MT5 repo root."
    exit 1
}

Write-Host "GoldFX MT4 Installer" -ForegroundColor Cyan
Write-Host "Source: $Src"

if ([string]::IsNullOrWhiteSpace($Mql4Path)) {
    $Mql4Path = Read-Host "MQL4 path (MT4: File -> Open Data Folder -> MQL4)"
}

$Mql4Path = $Mql4Path.Trim().TrimEnd('\')
if (-not (Test-Path $Mql4Path)) {
    Write-Host "[ERROR] Path not found: $Mql4Path" -ForegroundColor Red
    exit 1
}

$destExperts = Join-Path $Mql4Path "Experts"
$destIndi    = Join-Path $Mql4Path "Indicators"
$destInclude = Join-Path $Mql4Path "Include\GoldFX"
$destPresets = Join-Path $Mql4Path "Presets"

New-Item -ItemType Directory -Force -Path $destExperts, $destIndi, $destInclude, $destPresets | Out-Null

Copy-Item -Path (Join-Path $Src "Experts\GoldFX_BasisArb.mq4") -Destination $destExperts -Force
Copy-Item -Path (Join-Path $Src "Indicators\GoldFX_BasisCompare.mq4") -Destination $destIndi -Force
Copy-Item -Path (Join-Path $Src "Include\GoldFX\*") -Destination $destInclude -Recurse -Force
if (Test-Path (Join-Path $Src "Presets")) {
    Copy-Item -Path (Join-Path $Src "Presets\*") -Destination $destPresets -Force
}

Write-Host "[OK] Installed." -ForegroundColor Green
Write-Host "  $destExperts\GoldFX_BasisArb.mq4"
Write-Host "  $destIndi\GoldFX_BasisCompare.mq4"
Write-Host "  $destInclude"
Write-Host "Next: MetaEditor F7 compile both files; set InpFutSymbol on chart."
