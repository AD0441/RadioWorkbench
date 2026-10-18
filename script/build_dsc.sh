#!/usr/bin/env bash
set -euo pipefail
RADIO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DSC_OUTPUT="${1:-$RADIO_ROOT/.build/dsc-helper}"
mkdir -p "$(dirname "$DSC_OUTPUT")"
/usr/bin/clang++ -arch arm64 -O2 -std=c++17 -mmacosx-version-min=14.0 \
  -I "$RADIO_ROOT/Vendor/DSC" "$RADIO_ROOT/script/dsc-helper.cpp" \
  "$RADIO_ROOT/Vendor/DSC/decoder.cpp" -o "$DSC_OUTPUT"
