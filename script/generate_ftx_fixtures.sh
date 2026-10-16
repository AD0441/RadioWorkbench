#!/usr/bin/env bash
set -euo pipefail
RADIO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RADIO_ROOT"
clang -O2 -I Vendor/FT8 Vendor/FT8/demo/gen_ft8.c Vendor/FT8/ft8/*.c Vendor/FT8/common/wave.c -lm -o .build/gen-ftx
.build/gen-ftx 'CQ LU1ABC GF05' Tests/RadioCoreTests/Fixtures/ft8_12000_cq_clean.wav 1500
.build/gen-ftx 'CQ LU1ABC GF05' Tests/RadioCoreTests/Fixtures/ft4_12000_cq_clean.wav 1200 -ft4
