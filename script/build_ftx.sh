#!/usr/bin/env bash
set -euo pipefail
RADIO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FTX_OUTPUT="${1:-$RADIO_ROOT/.build/ftx-helper}"
mkdir -p "$(dirname "$FTX_OUTPUT")"
/usr/bin/clang -arch arm64 -O2 -std=gnu11 -mmacosx-version-min=14.0 -DHAVE_STPCPY -I "$RADIO_ROOT/Vendor/FT8" \
 "$RADIO_ROOT/script/ftx-helper.c" "$RADIO_ROOT"/Vendor/FT8/ft8/*.c "$RADIO_ROOT"/Vendor/FT8/common/*.c "$RADIO_ROOT"/Vendor/FT8/fft/*.c -lm -o "$FTX_OUTPUT"
