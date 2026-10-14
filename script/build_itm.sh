#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:?output directory required}"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/radio-itm-source.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
cp -R "$ROOT_DIR/Vendor/NTIA-ITM/include" "$STAGING_DIR/include"
cp "$ROOT_DIR"/Vendor/NTIA-ITM/src/*.cpp "$STAGING_DIR/"
perl -pi -e 's{\.\.\\include\\}{../include/}g' "$STAGING_DIR"/*.cpp
FLAGS=(-arch arm64 -O2 -std=c++17 -mmacosx-version-min=14.0 "-D__declspec(x)=" -I"$STAGING_DIR/include")
clang++ "${FLAGS[@]}" "$STAGING_DIR"/*.cpp "$ROOT_DIR/script/itm-helper.cpp" -o "$OUTPUT_DIR/itm-helper"
chmod +x "$OUTPUT_DIR/itm-helper"
