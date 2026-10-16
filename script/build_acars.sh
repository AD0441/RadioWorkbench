#!/usr/bin/env bash
set -euo pipefail
RADIO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACARS_OUTPUT="${1:-$RADIO_ROOT/.build/acars-helper}"
mkdir -p "$(dirname "$ACARS_OUTPUT")"
LIBACARS_BUILD="$RADIO_ROOT/.build/libacars"
cmake -S "$RADIO_ROOT/Vendor/LibACARS" -B "$LIBACARS_BUILD" -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 -DLIBXML2=OFF -DJANSSON=OFF >/dev/null
cmake --build "$LIBACARS_BUILD" --target acars_static -j 4 >/dev/null
/usr/bin/clang -arch arm64 -O2 -std=gnu11 -mmacosx-version-min=14.0 \
  -I "$RADIO_ROOT/Vendor/LibACARS" -I "$LIBACARS_BUILD" -include stddef.h -I "$RADIO_ROOT/Vendor/acarsdec" \
  "$RADIO_ROOT/script/acars-helper.c" "$RADIO_ROOT/Vendor/acarsdec/acars.c" \
  "$RADIO_ROOT/Vendor/acarsdec/msk.c" "$LIBACARS_BUILD/libacars/libacars-2.a" -o "$ACARS_OUTPUT" -lpthread -lm -lz
