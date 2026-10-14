#!/usr/bin/env bash
set -euo pipefail
RADIO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACARS_OUTPUT="${1:-$RADIO_ROOT/.build/acars-helper}"
mkdir -p "$(dirname "$ACARS_OUTPUT")"
/usr/bin/clang -arch arm64 -O2 -std=gnu11 -mmacosx-version-min=14.0 \
  -include stddef.h -I "$RADIO_ROOT/Vendor/acarsdec" \
  "$RADIO_ROOT/script/acars-helper.c" "$RADIO_ROOT/Vendor/acarsdec/acars.c" \
  "$RADIO_ROOT/Vendor/acarsdec/msk.c" -o "$ACARS_OUTPUT" -lpthread -lm
