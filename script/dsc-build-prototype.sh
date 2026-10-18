#!/bin/zsh
set -euo pipefail
root="${0:A:h:h}"
output="${1:-/tmp/rw-dsc-audit/dsc-prototype}"
mkdir -p "${output:h}"
xcrun clang++ -std=c++17 -O2 -arch arm64 -mmacosx-version-min=14.0 \
  -I"$root/Vendor/DSC" "$root/script/dsc-helper.cpp" "$root/Vendor/DSC/decoder.cpp" -o "$output"
file "$output"
