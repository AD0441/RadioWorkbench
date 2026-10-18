# RadioWorkbench ALE 2G port

Upstream: `jks-prv/Beagle_SDR_GPS`, revision `efb38e2b25137029cb37a96a94e03366f8d2871e`, `extensions/ALE_2G`.
The three decoder files retain their original GPL-3.0-or-later and author notices (Milen Rangelov; LinuxALE contributors Charles Brain and Ilkka Toivanen). KiwiSDR modifications remain in the pinned source. `COPYING` is the full GNU GPL version 3 text.

The helper is a receive-only standalone process. Input is normalized native little-endian float32 mono at exactly 8000 samples/s; output is line-delimited JSON. The app resamples audio before transport. It does not transmit, establish ALE links, scan/tune a receiver or implement ALE 3G.

Changes to the selected upstream files:

- Remove the unused FFTW plan/arrays and constructor allocation. The active upstream sliding DFT and its timing/frequency search, voting, Golay decoder and symbol tables are unchanged. The inactive upstream FFTW branch was already incomplete; it remains disabled.
- Exclude Kiwi/Dream resampler declarations from the standalone build. No alternate resampler or stub DSP is substituted. `radio_compat.h` supplies only fixed-width types, bit extraction and bounded text utilities; Kiwi RPC stubs are inline and inert.
- Replace terminal logging with a bounded JSON callback. Disable terminal colour strings. Preserve the decoder's elapsed audio timestamp. Every JSON record is flushed immediately while stdin can remain open.
- Bound command indices to the original 16-entry array and reset incomplete state when it fills. Bound appends to the original 256-byte buffers. Format/truncate quoted AMD/DTM messages safely. Initialize protocol strings and command state on reset. Widen the sample counter to avoid signed overflow in long sessions.
- Exclude the upstream file-list standalone main and AU file loader when building the app helper. The adapter owns its stream lifecycle, handles split float32 bytes, clips/sanitizes input values, and finalizes the decoder at EOF/SIGTERM.
- Debug character formatting uses a printable character/hex representation instead of Kiwi's shared ASCII description table.

New adapter/build/fixture/test sources are in `script/ale-helper.cpp`, `script/build_ale.sh`, `script/generate_ale_fixtures.py` and `Tests/RadioCoreTests/ALEEngineTests.swift`. The generator implements arithmetic extended Golay encoding and phase-continuous 8FSK independently; it imports no decoder tables or encoder source. The synthetic WAVs contain invented messages, not an RF capture.

Validation: synthetic AMD and sounding; synthetic AMD with 25 Hz offset and Gaussian noise; two public upstream real AU fixtures; no output from tested silence, seeded noise or non-finite floats; live publication before EOF; AddressSanitizer/UndefinedBehaviorSanitizer with long command and text sequences. See `docs/validation/ale2g-0.10.json` for the exact cases and external fixture hashes. The external AU recordings are not redistributed. The bundled synthetic files are declared CC0-1.0 in their fixture manifest.

Limits: the upstream label “His BER” is the decoder's vote disagreement/quality statistic, not a calibrated signal-to-noise measurement or promised bit-error probability. One tested +65 Hz synthetic case failed to recover the complete message, so this port makes no broad frequency-offset/noise sensitivity claim. No live RF, receiver-control or microphone test has been performed for this integration.
