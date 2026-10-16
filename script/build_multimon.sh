#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="${1:?Pass the helper output path}"
SOURCE="$ROOT_DIR/Vendor/MultimonNG"
mkdir -p "$(dirname "$OUTPUT")"
# Use upstream algorithms as a file/stdin-only helper. Do not compile its macOS
# ProcessTap backend or give this process access to capture/network/transmission.
SOURCES=(unixinput uart pocsag selcall hdlc demod_zvei1 demod_zvei2 demod_zvei3 demod_pzvei demod_dzvei
  demod_ccir demod_eia demod_eea demod_ufsk12 demod_poc24 demod_poc12 demod_poc5 demod_hapn48 demod_fsk96
  demod_dtmf demod_dualtone demod_clipfsk demod_fmsfsk demod_afsk24 demod_afsk24_3 demod_afsk24_2 demod_afsk12
  demod_flex demod_flex_next demod_gsc costabi costabf clip fms demod_eas demod_morse demod_dumpcsv demod_x10 cJSON bch)
FILES=()
for name in "${SOURCES[@]}"; do FILES+=("$SOURCE/$name.c"); done
xcrun clang -arch arm64 -mmacosx-version-min=14.0 -std=gnu11 -O2 \
  -DDUMMY_AUDIO -DONLY_RAW -DNO_X11 -DNO_SDL3 -DHAVE_TIMESPEC_GET -DUSE_BUILTIN_POPCOUNT -DCHARSET_UTF8 \
  -DMAX_VERBOSE_LEVEL=0 -I "$SOURCE" "${FILES[@]}" -lm -o "$OUTPUT"
