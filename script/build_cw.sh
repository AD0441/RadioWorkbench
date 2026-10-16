#!/usr/bin/env bash
set -euo pipefail
RADIO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CW_BUILD="$RADIO_ROOT/.build/cw-engine"
export CLANG_MODULE_CACHE_PATH="$CW_BUILD/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CW_BUILD/ModuleCache"
mkdir -p "$CW_BUILD/ModuleCache"
swift build --build-system native --package-path "$RADIO_ROOT/Vendor/CWKit" --scratch-path "$CW_BUILD" --cache-path "$CW_BUILD/cache" --disable-sandbox -c release --arch arm64 --product cw-helper
CW_BIN="$(swift build --build-system native --package-path "$RADIO_ROOT/Vendor/CWKit" --scratch-path "$CW_BUILD" --cache-path "$CW_BUILD/cache" --disable-sandbox -c release --arch arm64 --show-bin-path)/cw-helper"
if [[ $# -gt 0 ]]; then cp "$CW_BIN" "$1"; fi
