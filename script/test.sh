#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_PATH="${RADIO_BUILD_PATH:-$ROOT_DIR/.build}"
export CLANG_MODULE_CACHE_PATH="$BUILD_PATH/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_PATH/ModuleCache"
mkdir -p "$BUILD_PATH/ModuleCache"
SWIFT_DEVELOPER_ROOT="$(xcode-select -p)"
TESTING_FRAMEWORKS="$SWIFT_DEVELOPER_ROOT/Library/Developer/Frameworks"
TESTING_PLUGIN="$SWIFT_DEVELOPER_ROOT/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
TESTING_FLAGS=()
# CLT ships Testing, but its native backend does not add the framework/plugin paths.
if [[ -f "$TESTING_PLUGIN" && -d "$TESTING_FRAMEWORKS/Testing.framework" ]]; then
  TESTING_FLAGS=(-Xswiftc -F -Xswiftc "$TESTING_FRAMEWORKS" -Xswiftc -load-plugin-library -Xswiftc "$TESTING_PLUGIN" -Xlinker -rpath -Xlinker "$TESTING_FRAMEWORKS")
fi
cd "$ROOT_DIR"
bash "$ROOT_DIR/script/build_dsc.sh" "$BUILD_PATH/dsc-helper"
export DSC_HELPER_PATH="$BUILD_PATH/dsc-helper"
bash "$ROOT_DIR/script/build_mt63.sh" "$BUILD_PATH/mt63-helper"
export MT63_HELPER_PATH="$BUILD_PATH/mt63-helper"
bash "$ROOT_DIR/script/build_ale.sh" "$BUILD_PATH/ale-helper"
export ALE_HELPER_PATH="$BUILD_PATH/ale-helper"
bash "$ROOT_DIR/script/build_ftx.sh" "$BUILD_PATH/ftx-helper"
export FTX_HELPER_PATH="$BUILD_PATH/ftx-helper"
bash "$ROOT_DIR/script/build_cw.sh" "$BUILD_PATH/cw-helper"
export CW_HELPER_PATH="$BUILD_PATH/cw-helper"
export CW_MODEL_PATH="$ROOT_DIR/Vendor/CWKit/Sources/CWKit/Resources/CWNet.mlmodelc"
bash "$ROOT_DIR/script/build_acars.sh" "$BUILD_PATH/acars-helper"
export ACARS_HELPER_PATH="$BUILD_PATH/acars-helper"
bash "$ROOT_DIR/script/build_multimon.sh" "$BUILD_PATH/multimon-helper"
export MULTIMON_HELPER_PATH="$BUILD_PATH/multimon-helper"
bash "$ROOT_DIR/script/build_propagation.sh" "$BUILD_PATH/propagation"
export PROPAGATION_HELPER_PATH="$BUILD_PATH/propagation/propagation-helper"
export PROPAGATION_DATA_PATH="$BUILD_PATH/propagation/PropagationData"
/usr/bin/clang -arch arm64 -O2 -std=c99 -fcommon -I "$ROOT_DIR/Vendor/ITU-R-HF/P533/Src/P533" \
  "$ROOT_DIR/Vendor/ITU-R-HF/tests/hemisphere-tests.c" -L "$BUILD_PATH/propagation" -lp533 \
  -Wl,-rpath,"$BUILD_PATH/propagation" -o "$BUILD_PATH/propagation/hemisphere-tests"
"$BUILD_PATH/propagation/hemisphere-tests"
bash "$ROOT_DIR/script/build_itm.sh" "$BUILD_PATH/itm"
export ITM_LIBRARY_PATH="$BUILD_PATH/itm/libitm.dylib"
export ITM_HELPER_PATH="$BUILD_PATH/itm/itm-helper"
swift test --build-system native --scratch-path "$BUILD_PATH" --cache-path "$BUILD_PATH/cache" --disable-sandbox --disable-xctest "${TESTING_FLAGS[@]}" "$@"
