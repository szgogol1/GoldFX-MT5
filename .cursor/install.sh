#!/usr/bin/env bash
#
# Cloud Agent install step for the GoldFX-MT5 (MQL5) project.
#
# The base environment snapshot already contains Wine (Staging) and a
# MetaTrader 5 installation (MetaEditor64.exe + the standard MQL5 library).
# This script wires the checked-out repository into that MT5 tree and compiles
# both Expert Advisors, so every fresh agent gets verified .ex5 build artifacts.
#
# It is idempotent: it only (re)creates symlinks and recompiles.
set -euo pipefail

export WINEPREFIX="${WINEPREFIX:-$HOME/.mt5}"
export WINEARCH=win64
export WINEDEBUG=-all
# The .NET / Gecko runtimes are not needed for compilation; silence the prompts.
export WINEDLLOVERRIDES="mscoree,mshtml="

MT5_DIR="$WINEPREFIX/drive_c/Program Files/MetaTrader 5"
MQL5_DIR="$MT5_DIR/MQL5"
METAEDITOR="$MT5_DIR/MetaEditor64.exe"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -f "$METAEDITOR" ]]; then
  echo "ERROR: MetaEditor not found at:" >&2
  echo "  $METAEDITOR" >&2
  echo "The base environment snapshot is expected to provide the MT5 install." >&2
  exit 1
fi
if [[ ! -f "$MQL5_DIR/Include/Trade/Trade.mqh" ]]; then
  echo "ERROR: MT5 standard library (Include/Trade/Trade.mqh) is missing." >&2
  exit 1
fi

echo "==> Linking repository sources into the MQL5 tree"
ln -sfn "$REPO_DIR/Experts/GoldFX_Intraday" "$MQL5_DIR/Experts/GoldFX_Intraday"
ln -sfn "$REPO_DIR/Experts/GoldFX_BasisArb" "$MQL5_DIR/Experts/GoldFX_BasisArb"
ln -sfn "$REPO_DIR/Include/GoldFX"          "$MQL5_DIR/Include/GoldFX"
mkdir -p "$MQL5_DIR/Presets"
for f in "$REPO_DIR"/Presets/*.set; do
  [ -e "$f" ] && ln -sfn "$f" "$MQL5_DIR/Presets/$(basename "$f")"
done

# MetaEditor's command-line compiler fails *silently* when the source or include
# path contains spaces (e.g. "C:\Program Files\..."). Map a space-free DOS drive
# (X:) to the MQL5 folder and compile through it.
echo "==> Mapping X: -> MQL5 (space-free path for the compiler)"
ln -sfn "$MQL5_DIR" "$WINEPREFIX/dosdevices/x:"

# MetaEditor is a GUI binary and needs an X display even for CLI compiles.
# `xvfb-run` spins up a fresh display per invocation, which makes repeated
# MetaEditor runs against the same Wine prefix hang; instead start ONE Xvfb and
# reuse it for every compile, then tear it down on exit.
XVFB_PID=""
cleanup() { [[ -n "$XVFB_PID" ]] && kill "$XVFB_PID" 2>/dev/null || true; }
trap cleanup EXIT

for dnum in 99 100 101 102 103; do
  if [[ ! -e "/tmp/.X${dnum}-lock" ]]; then
    Xvfb ":${dnum}" -screen 0 1280x1024x24 -nolisten tcp >/tmp/goldfx_xvfb.log 2>&1 &
    XVFB_PID=$!
    export DISPLAY=":${dnum}"
    break
  fi
done
if [[ -z "${DISPLAY:-}" ]]; then
  echo "ERROR: could not allocate an Xvfb display for MetaEditor." >&2
  exit 1
fi
# Wait for the display to accept connections.
for _ in $(seq 1 30); do
  [[ -e "/tmp/.X${DISPLAY#:}-lock" ]] && wine cmd /c "echo ok" >/dev/null 2>&1 && break
  sleep 0.5
done
echo "==> Using display ${DISPLAY} for MetaEditor"

compile_ea() {
  local title="$1" win_src="$2"
  local log="/tmp/goldfx_${title}.log"
  rm -f "$log"
  echo "==> Compiling ${title}"
  # MetaEditor's process exit code is not a reliable success signal, so the
  # authoritative result comes from parsing the compile log below.
  wine "$METAEDITOR" \
    /compile:"$win_src" \
    /include:'X:\' \
    /log:"Z:\\tmp\\goldfx_${title}.log" >/dev/null 2>&1 || true

  local result
  result="$(iconv -f UTF-16LE -t UTF-8 "$log" 2>/dev/null | tr -d '\r' | grep -a 'Result:' | tail -1 || true)"
  if [[ -z "$result" ]]; then
    echo "ERROR: ${title} produced no compiler result (check Wine/display)." >&2
    return 1
  fi
  echo "    ${result}"
  if ! grep -qE '(^| )0 errors' <<<"$result"; then
    echo "ERROR: ${title} failed to compile:" >&2
    iconv -f UTF-16LE -t UTF-8 "$log" 2>/dev/null | tr -d '\r' | grep -aiE 'error' >&2 || true
    return 1
  fi
}

compile_ea intraday 'X:\Experts\GoldFX_Intraday\GoldFX_Intraday.mq5'
compile_ea basisarb 'X:\Experts\GoldFX_BasisArb\GoldFX_BasisArb.mq5'

echo "==> Build artifacts:"
ls -l "$REPO_DIR/Experts/GoldFX_Intraday/GoldFX_Intraday.ex5" \
      "$REPO_DIR/Experts/GoldFX_BasisArb/GoldFX_BasisArb.ex5"

echo "==> GoldFX-MT5 install complete: both Expert Advisors compiled."
