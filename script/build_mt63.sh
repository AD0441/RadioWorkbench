#!/usr/bin/env bash
set -euo pipefail
RADIO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MT63_OUTPUT="${1:-$RADIO_ROOT/.build/mt63-helper}"
mkdir -p "$(dirname "$MT63_OUTPUT")"
/usr/bin/clang++ -arch arm64 -O2 -std=c++17 -mmacosx-version-min=14.0 \
  -I "$RADIO_ROOT/Vendor/MT63/include" \
  "$RADIO_ROOT/script/mt63-helper.cpp" "$RADIO_ROOT/Vendor/MT63/src/mt63base.cxx" \
  "$RADIO_ROOT/Vendor/MT63/src/dsp.cxx" -Wl,-dead_strip -o "$MT63_OUTPUT"
