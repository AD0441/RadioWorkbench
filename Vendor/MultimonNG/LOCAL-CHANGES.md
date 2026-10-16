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
