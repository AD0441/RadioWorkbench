#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:?output directory required}"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/radio-p533-source.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
cp "$ROOT_DIR"/Vendor/ITU-R-HF/P533/Src/P533/*.[ch] "$STAGING_DIR/"
# Load only the bundled noise library. Equations and datasets remain upstream.
sed -i '' 's/"libp372.so"/"@executable_path\/libp372.dylib"/g' "$STAGING_DIR/P533.c" "$STAGING_DIR/PathMemory.c"
COMMON_FLAGS=(-arch arm64 -O2 -std=c99 -fcommon -include errno.h -mmacosx-version-min=14.0)
NOISE_DIR="$ROOT_DIR/Vendor/ITU-R-HF/P372/Src/P372"
clang "${COMMON_FLAGS[@]}" -dynamiclib -install_name @rpath/libp372.dylib -I"$NOISE_DIR" \
  "$NOISE_DIR/Noise.c" "$NOISE_DIR/NoiseMemory.c" "$NOISE_DIR/InitializeNoise.c" "$NOISE_DIR/MakeNoise.c" -o "$OUTPUT_DIR/libp372.dylib"
clang "${COMMON_FLAGS[@]}" -dynamiclib -install_name @rpath/libp533.dylib -I"$STAGING_DIR" "$STAGING_DIR"/*.c -o "$OUTPUT_DIR/libp533.dylib"
clang "${COMMON_FLAGS[@]}" -I"$STAGING_DIR" "$ROOT_DIR/script/propagation-helper.c" -L"$OUTPUT_DIR" -lp533 -lp372 \
  -Wl,-rpath,@executable_path -o "$OUTPUT_DIR/propagation-helper"
DATA_DIR="${2:-$OUTPUT_DIR/PropagationData}"
mkdir -p "$DATA_DIR"
cp "$ROOT_DIR"/Vendor/ITU-R-HF/P533/Data/* "$DATA_DIR/"
cp "$ROOT_DIR"/Vendor/ITU-R-HF/P372/Data/COEFF*.txt "$DATA_DIR/"
