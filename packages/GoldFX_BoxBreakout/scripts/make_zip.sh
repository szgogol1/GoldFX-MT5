#!/usr/bin/env bash
# 在独立包目录生成 ZIP（不混入日内/基差代码）
set -euo pipefail
PKG="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$(cd "$PKG/.." && pwd)"
STAMP="$(date +%Y%m%d)"
ZIP="$OUT_DIR/GoldFX_BoxBreakout_${STAMP}.zip"

if [[ ! -f "$PKG/Experts/GoldFX_BoxBreakout/GoldFX_BoxBreakout.mq5" ]]; then
  echo "找不到独立包源码: $PKG" >&2
  exit 1
fi

rm -f "$ZIP"
(
  cd "$PKG"
  zip -r "$ZIP" \
    Experts Include Presets \
    README.md install_to_MT5.bat install_to_MT5.ps1 \
    -x "*.ex5" "*.log" "*.mqproj" "scripts/*"
)

echo "已生成: $ZIP"
ls -lh "$ZIP"
