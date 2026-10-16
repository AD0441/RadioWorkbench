# RadioWorkbench adapter

Upstream: https://github.com/f00b4r0/acarsdec
Revision: `cbaa28c4173fc1529a01ab50708e29d12d09a644`.
The original sources and GPL-2.0-only license are retained.

Changes in `acars.c`: the decoder thread exits during shutdown only after the
pending block queue is empty, preserving final WAV packets. The queue is bounded
at 256 blocks; dropped blocks are counted in the helper's final summary. No
modulation, CRC or correction algorithm was changed.

`script/acars-helper.c` supplies mono float32 PCM at 12000 Hz through stdin and
outputs locally validated blocks as JSON lines. It has no network destinations,
audio device access or filesystem input. StatsD functions are disabled stubs.
`script/build_acars.sh` compiles only that adapter, acars.c and msk.c for arm64.
The helper is GPL-2.0-only; it is a separate executable, not linked into Swift.
Complete corresponding sources and the build script are included with the app.

## 2026-10-16 · FIFO for libacars integration

The bounded output queue now appends at a tail and removes at its head. The previous LIFO behavior reversed blocks when the output thread fell behind; sorting the monitor by timestamp concealed it, but ACARS application reassembly rejected the reversed fragments. Both head and tail remain protected by blkq_mtx, including empty-queue transitions. The 256-block bound and drop counter are preserved. Regression: repeated concatenated ADS-C A/B blocks must produce a completed application under backlog.
