# Local changes for RadioWorkbench

Upstream: multimon-ng 1.6.2, commit `3d8e925782b389ec16e3d48dd8b6d94fbb132197`.
All upstream copyright and GPL notices are retained. These changes were made on
2026-10-16; this is a locally patched build, not an unmodified upstream release.

`pocsag.c` changes:

- Require a valid sync codeword after every sixteen data codewords. A BCH-valid
  zero or idle word cannot substitute for this marker. Missing sync discards
  incomplete message state and returns immediately to bitwise sync acquisition.
- Reset bit/word counters on sync acquisition and realign the word counter when
  receiving sync. Data words remain numbered 0–15 for correct capcode frame bits.
- Respect the configured BCH correction limit when accepting sync, including
  acquisition; the repair function may mutate its candidate before reporting
  that the required correction exceeds that limit.
- Flush stdout after emitting a tone-only JSON event, as the text branches do.

Framing reference: [ITU-R M.584-2, Annex 1, sections 1.2 and 1.3.3](https://www.itu.int/dms_pubrec/itu-r/rec/m/R-REC-M.584-2-199711-I!!PDF-E.pdf).

`source-manifest.json` records SHA-256 of the distributed files, plus the original
upstream hash of the modified C file. The source archive bundled with the app
contains this notice, the modified sources, their manifest and the build script.
Regression tests are in `Tests/RadioCoreTests/POCSAGRegressionTests.swift`.

Changes on 2026-10-25 for the FLEX reception adapter:

- `unixinput.c`: flush every complete JSON event in `printJson()`. A live stdin
  pipe remains open between transmissions; numeric and alpha FLEX events must
  reach the monitor immediately rather than waiting for stdio buffer capacity
  or process exit. This also applies to other JSON decoders using this function.
- `demod_flex.c`: include the existing `K`/`C`/`F` alpha fragment flag as
  `fragment_flag` in JSON. Consumers can distinguish a complete single-frame
  message from a fragment; this does not assemble multipart messages.
- `demod_flex.c`: check the transmitted overall even-parity bit after a two-bit
  BCH repair. If that would require a third correction, reject the frame instead
  of publishing a possible miscorrection. One damaged overall parity bit remains
  within the two-bit repair allowance. BCH/checksums are not authentication and
  do not guarantee detection of every higher-weight error pattern.

The app accepts only unencrypted ALPHA, numeric and tone records with supported
short capcodes 1–1,933,312 and consistent symbol-rate/level/phase/frame metadata.
Long addressing, group recipient expansion, secure/binary messages, ReFLEX and
fragment reassembly are not exposed as validated message decoding.

Regression data and generator are in `Tests/RadioCoreTests/FLEXTests.swift`,
`MultimonProcessTests.swift` and `script/validation/flex_fixture.py`. The small
included WAVs are locally synthesized MIT test data, not real pager traffic or
an independent interoperability corpus. Laboratory tests cover 1600/3200 baud,
2-/4-FSK and the corresponding A/B/C/D phase combinations with both polarities,
zero/two correctable errors, a three-bit rejection case, silence/noise, live
publication before EOF and reacquisition. See `flex-manifest.json` for expected
contents and hashes. No RF transmission or hardware capture is performed.
