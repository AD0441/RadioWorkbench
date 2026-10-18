#!/usr/bin/env bash
set -euo pipefail
RADIO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALE_OUTPUT="${1:-$RADIO_ROOT/.build/ale-helper}"
mkdir -p "$(dirname "$ALE_OUTPUT")"
/usr/bin/clang++ -arch arm64 -O2 -std=c++17 -mmacosx-version-min=14.0 \
  -DSTANDALONE_TEST -DRADIOWORKBENCH_HELPER -I "$RADIO_ROOT/Vendor/ALE2G" \
  "$RADIO_ROOT/script/ale-helper.cpp" "$RADIO_ROOT/Vendor/ALE2G/decode_ff_impl.cpp" -o "$ALE_OUTPUT"
