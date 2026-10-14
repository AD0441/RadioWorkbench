#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
APP_NAME="RadioWorkbench"
BUNDLE_ID="cl.sebastian.RadioWorkbench"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
BUILD_PATH="${RADIO_BUILD_PATH:-$ROOT_DIR/.build}"
BUILD_CONFIGURATION="${RADIO_BUILD_CONFIGURATION:-release}"
if [[ "$MODE" == "--debug" || "$MODE" == "debug" ]]; then BUILD_CONFIGURATION=debug; fi
export CLANG_MODULE_CACHE_PATH="$BUILD_PATH/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_PATH/ModuleCache"
mkdir -p "$BUILD_PATH/ModuleCache"
cd "$ROOT_DIR"
if [[ "$MODE" != "--build-only" ]]; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi
# Keep caches local to this project; no global toolchain/configuration edits.
swift build --build-system native --scratch-path "$BUILD_PATH" --cache-path "$BUILD_PATH/cache" --configuration "$BUILD_CONFIGURATION" --arch arm64 --disable-sandbox
BUILD_BINARY="$(swift build --build-system native --scratch-path "$BUILD_PATH" --cache-path "$BUILD_PATH/cache" --configuration "$BUILD_CONFIGURATION" --arch arm64 --disable-sandbox --show-bin-path)/$APP_NAME"
# Sign outside Desktop/File Provider: it can recreate FinderInfo during signing.
PACKAGE_STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/radioworkbench-stage.XXXXXX")"
trap 'rm -rf "$PACKAGE_STAGING_DIR"' EXIT
APP_BUNDLE="$PACKAGE_STAGING_DIR/$APP_NAME.app"
APP_MACOS="$APP_BUNDLE/Contents/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
mkdir -p "$APP_MACOS" "$APP_BUNDLE/Contents/Resources/Examples"
cp "$BUILD_BINARY" "$APP_BINARY"
bash "$ROOT_DIR/script/build_acars.sh" "$APP_MACOS/acars-helper"
codesign --force --sign - "$APP_MACOS/acars-helper"
bash "$ROOT_DIR/script/build_propagation.sh" "$APP_MACOS" "$APP_BUNDLE/Contents/Resources/Propagation"
bash "$ROOT_DIR/script/build_itm.sh" "$APP_MACOS"
for component in libp372.dylib libp533.dylib propagation-helper itm-helper; do
  codesign --force --sign - "$APP_MACOS/$component"
done
cp "$ROOT_DIR/Vendor/ITU-R-HF/NOTICE.md" "$APP_BUNDLE/Contents/Resources/Propagation-Notice.md"
cp "$ROOT_DIR/Vendor/ITU-R-HF/source-manifest.json" "$APP_BUNDLE/Contents/Resources/Propagation/source-manifest.json"
COPYFILE_DISABLE=1 tar -czf "$APP_BUNDLE/Contents/Resources/Propagation-Sources.tar.gz" -C "$ROOT_DIR" \
  Vendor/ITU-R-HF/P533/Src Vendor/ITU-R-HF/P372/Src Vendor/ITU-R-HF/ITURHFProp \
  Vendor/ITU-R-HF/NOTICE.md Vendor/ITU-R-HF/source-manifest.json script/propagation-helper.c script/build_propagation.sh
cp "$ROOT_DIR/Vendor/NTIA-ITM/LICENSE.md" "$APP_BUNDLE/Contents/Resources/NTIA-ITM-License.txt"
COPYFILE_DISABLE=1 tar -czf "$APP_BUNDLE/Contents/Resources/NTIA-ITM-Sources.tar.gz" -C "$ROOT_DIR" \
  Vendor/NTIA-ITM/include Vendor/NTIA-ITM/src Vendor/NTIA-ITM/LICENSE.md Vendor/NTIA-ITM/README.md \
  Vendor/NTIA-ITM/source-manifest.json script/itm-helper.cpp script/build_itm.sh
chmod +x "$APP_BINARY"
for mode in morse rtty bpsk31 dtmf navtex packet; do
  cp "$ROOT_DIR/Tests/RadioCoreTests/Fixtures/${mode}_8000_mono_clean.wav" "$APP_BUNDLE/Contents/Resources/Examples/"
done
cp "$ROOT_DIR/Tests/RadioCoreTests/Fixtures/ctcss_8000_mono_100hz.wav" "$APP_BUNDLE/Contents/Resources/Examples/"
cp "$ROOT_DIR/Tests/RadioCoreTests/Fixtures/acars_upstream_12000_mono.wav" "$APP_BUNDLE/Contents/Resources/Examples/"
cp "$ROOT_DIR/Vendor/acarsdec/LICENSE.md" "$APP_BUNDLE/Contents/Resources/ACARS-License.txt"
COPYFILE_DISABLE=1 tar -czf "$APP_BUNDLE/Contents/Resources/ACARS-Sources.tar.gz" -C "$ROOT_DIR" Vendor/acarsdec script/acars-helper.c script/build_acars.sh
mkdir -p "$APP_BUNDLE/Contents/Resources/EiBi"
cp "$ROOT_DIR"/docs/eibi-snapshot/* "$APP_BUNDLE/Contents/Resources/EiBi/"
cp "$ROOT_DIR/docs/sstv-modes.json" "$APP_BUNDLE/Contents/Resources/sstv-modes.json"
for example in wefax_hf120_ioc576_8000_mono_manual noaa_apt_2400am_48000_mono_24lines; do
  cp "$ROOT_DIR/Tests/RadioCoreTests/Fixtures/$example.wav" "$APP_BUNDLE/Contents/Resources/Examples/"
done
for example in "$ROOT_DIR"/Tests/RadioCoreTests/Fixtures/sstv_*_clean.wav; do
  cp "$example" "$APP_BUNDLE/Contents/Resources/Examples/"
done
cat >"$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$APP_NAME</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>$APP_NAME</string>
<key>CFBundleDisplayName</key><string>RadioWorkbench</string>
<key>CFBundleShortVersionString</key><string>0.8.8</string>
<key>CFBundleVersion</key><string>20</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSMicrophoneUsageDescription</key><string>Decodificar audio del receptor seleccionado al pulsar Escuchar.</string>
<key>NSAppTransportSecurity</key><dict><key>NSExceptionDomains</key><dict>
<key>eibispace.de</key><dict><key>NSIncludesSubdomains</key><true/><key>NSExceptionAllowsInsecureHTTPLoads</key><true/></dict>
</dict></dict>
</dict></plist>
PLIST
xattr -cr "$APP_BUNDLE"
codesign --force --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
mkdir -p "$ROOT_DIR/dist"
# Publish a fresh directory instead of overwriting an executable that an older
# process may still have mapped when using --build-only.
PUBLISH_STAGING_DIR="$(mktemp -d "$ROOT_DIR/dist/.publish.XXXXXX")"
/usr/bin/ditto --norsrc --noextattr "$APP_BUNDLE" "$PUBLISH_STAGING_DIR/$APP_NAME.app"
if [[ -d "$OUTPUT_APP_BUNDLE" ]]; then mv "$OUTPUT_APP_BUNDLE" "$PUBLISH_STAGING_DIR/previous.app"; fi
mv "$PUBLISH_STAGING_DIR/$APP_NAME.app" "$OUTPUT_APP_BUNDLE"
rm -rf "$PUBLISH_STAGING_DIR"
xattr -d com.apple.FinderInfo "$OUTPUT_APP_BUNDLE" 2>/dev/null || true
/usr/bin/ditto --norsrc --noextattr -c -k --keepParent "$APP_BUNDLE" "$ROOT_DIR/dist/$APP_NAME-arm64.zip"
open_app() { /usr/bin/open -n "$OUTPUT_APP_BUNDLE"; }
open_microphone_test() {
  MICROPHONE_TEST_ARGS=(--sstv-microphone-test --diagnostics-path "${RADIO_DIAGNOSTICS_PATH:-$ROOT_DIR/docs/validation/microphone-live.json}" --probe-seconds "${RADIO_PROBE_SECONDS:-15}")
  if [[ -n "${RADIO_DIAGNOSTIC_WAV_PATH:-}" ]]; then MICROPHONE_TEST_ARGS+=(--diagnostic-wav "$RADIO_DIAGNOSTIC_WAV_PATH"); fi
  /usr/bin/open -n "$OUTPUT_APP_BUNDLE" --args "${MICROPHONE_TEST_ARGS[@]}"
}
open_file_test() {
  if [[ -z "${RADIO_SSTV_FILE:-}" || ! -f "$RADIO_SSTV_FILE" ]]; then
    echo "Set RADIO_SSTV_FILE to an existing audio file." >&2; exit 2
  fi
  FILE_TEST_ARGS=(--sstv-file-test "$RADIO_SSTV_FILE" --file-diagnostics-path "${RADIO_FILE_DIAGNOSTICS_PATH:-$ROOT_DIR/docs/validation/sstv-file-live.json}")
  if [[ "${RADIO_ROBOT36C_COMPATIBILITY:-0}" == "1" ]]; then FILE_TEST_ARGS+=(--robot36c-compatibility); fi
  /usr/bin/open -n "$OUTPUT_APP_BUNDLE" --args "${FILE_TEST_ARGS[@]}"
}
case "$MODE" in
  run) open_app ;;
  --build-only) echo "$OUTPUT_APP_BUNDLE" ;;
  --debug|debug) lldb -- "$APP_BINARY" ;;
  --logs|logs) open_app; /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\"" ;;
  --telemetry|telemetry) open_app; /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\"" ;;
  --verify|verify) open_app; sleep 2; pgrep -x "$APP_NAME" >/dev/null ;;
  --microphone-test) open_microphone_test ;;
  --file-test) open_file_test ;;
  *) echo "usage: $0 [run|--build-only|--debug|--logs|--telemetry|--verify|--microphone-test]" >&2; exit 2 ;;
esac
