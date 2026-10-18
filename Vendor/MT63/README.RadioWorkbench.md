# MT63 reception in RadioWorkbench

This is a small standalone adapter to fldigi's original MT63 DSP, running as an
arm64 macOS 14+ helper. It requires no FLTK, GNU Radio, SDR driver, or global
package installation. It receives all six combinations of 500/1000/2000 Hz
bandwidth and short (32-symbol) or long (64-symbol) interleave.

## Audio contract

```
mt63-helper --bandwidth 1000 --interleave long --center-hz 1500
```

Input is raw little-endian float32 mono at exactly 8000 samples/second on stdin.
The default is 1000 Hz bandwidth, long interleave, center 1500 Hz. Audio center
must be 1000–2500 Hz and the complete occupied band must lie inside 0–4000 Hz.
Use USB on HF with an SDR passband that includes the entire selected signal;
in VHF FM systems use the demodulated audio with the complete passband intact.
The helper does not demodulate radio I/Q and does not tune SDR++.

Output is newline-delimited JSON, flushed immediately, with incremental `text`
and `decoder`, `locked`, `confidence`, `frequencyHz`, `offsetSeconds` fields.
`confidence` is upstream synchronization confidence in 0–1; it is not message
accuracy or SNR. `frequencyHz` is the audio center plus the detector's estimated
offset. `offsetSeconds` is elapsed processed input, not UTC or radio path delay.
MT63's FEC has no message CRC; the helper never labels text CRC-validated.
The UI must not treat empty periodic status records as contacts or messages.

The interleaver and receive integration add substantial latency. Depending on
bandwidth and interleave, first text can arrive several seconds after the
corresponding modulation; the synthetic tests measured about 3.3 seconds for
2000-short through 19.6 seconds for 500-long. Capture should begin before the transmission and
continue through its transmitted flush/tail. Loss of lock restarts the warmup;
very short or weak transmissions can lose their beginning. The adapter does not
invent an unlimited silence tail at EOF, and no RF reception is claimed from
the synthetic tests.

## Reproducibility

```
bash script/build_mt63.sh
python3 script/generate_mt63_fixtures.py
python3 Vendor/MT63/validate-helper.py --sanitize
```

The fixture generator compiles a separate upstream `MT63tx` executable into
`.build/mt63-audit`, generates public ASCII test text, and saves six mono 8 kHz
PCM16 WAVs. SHA256 and parameters are in `fixture-manifest.json`. These are
source-loopback tests using the upstream transmitter and receiver; they are
not an independent modem interoperability test or an over-the-air recording.

The focused validation covers all six modes, additive white noise at a global
12 dB signal/noise power ratio, 60-second silence/noise rejection, split float
samples, decoded text delivered before EOF, invalid options, non-finite input,
truncated input, and ASan/UBSan TX/RX checks. `validation-summary.json` records
the observed results. Full Swift integration tests live in
`Tests/RadioCoreTests/MT63EngineTests.swift`.

See `LOCAL-CHANGES.md` for the narrow upstream memory/index fixes and
`source-manifest.json` for exact source provenance.
