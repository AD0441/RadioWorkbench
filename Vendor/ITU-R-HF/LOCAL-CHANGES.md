# RadioWorkbench corrections to the pinned HF model

The upstream revision remains `82017594a1c6cacfaa7e86954c4ae7b3a5825a3d`.
Three source files have narrowly scoped local corrections; all data maps,
coefficient files, equations and other source files retain their upstream
versions. `source-manifest.json` records both the original Git/SHA256 provenance
and the actual local file hashes. These corrections do not turn monthly
predictions into measurements or certify the whole implementation.

## 1. Southern polar winter latitude sign

`P533/Src/P533/CalculateCPParameters.c`, `FindfoE`: the southern condition was
`latitude < +72.5622°`, incorrectly including most ordinary night locations in
May–July. It now uses `latitude < -72.5622°`. The existing civil-polar latitude
and month approximation is otherwise retained.

[ITU-R P.1239-3, Annex 1 §4](https://www.itu.int/dms_pubrec/itu-r/rec/p/R-REC-P.1239-3-201202-S!!PDF-E.pdf)
distinguishes ordinary night, using the larger of its two night factors, from
polar winter without sunrise. [P.533-14 §3.2](https://www.itu.int/dms_pubrec/itu-r/rec/p/R-REC-P.533-14-201908-I!!PDF-E.pdf)
uses that reference for foE. Ordinary equatorial and midlatitude night must not
be classified as southern polar winter by a positive latitude cutoff.

Numerical check: at Santiago (-33.45°, -70.67°), June, 11 UTC, R12=75, foE was
0.90877624 MHz; the corrected ordinary-night branch yields 1.75548953 MHz.
Controlled equatorial/northern/southern midlatitude nights and both genuine
polar-winter branches are covered by the C regression.

## 2. Southern geomagnetic variability table

`P533/Src/P533/CircuitReliability.c`: all three existing control-point checks
now compare the magnitude of geomagnetic latitude with 60°. Previously signed
southern latitude could never select the high-latitude variability table.

[ITU-R P.842-5 Table 2 and footnote 1](https://www.itu.int/dms_pubrec/itu-r/rec/p/R-REC-P.842-5-201309-I!!PDF-E.pdf)
apply the high-latitude variability values to circuits reaching the polar
geomagnetic region. The underlying P.1239 latitude convention covers both
hemispheres. The regression independently evaluates the table and BCR formula
for each of the three control points, with northern/southern counterparts.

Example using the same signal/noise conditions: for the synthetic table test,
the corrected southern BCR is 21.26398679%, matching its northern counterpart;
the old southern result was 16.00535375%. For an actual 5008.45 km south-polar
path at 10.1 MHz, October, 12 UTC, the correction changes BCR from 66.41135262%
to 64.35261514%, with the median SNR unchanged at 14.35421229 dB. Greater
variability can increase or decrease reliability relative to a chosen threshold.

Limitation retained: upstream checks three control points rather than searching
every point on the interior great-circle segment. No claim of exhaustive polar
intersection handling is made by this sign correction.

## 3. Solar minimum R12=0

`P533/Src/P533/ValidatePath.c`: the lower guard is now 0 instead of 1; the
existing upper guard 311 is retained. [P.533-14 §3.4](https://www.itu.int/dms_pubrec/itu-r/rec/p/R-REC-P.533-14-201908-I!!PDF-E.pdf)
uses ionospheric maps at R12=0 and R12=100 and describes interpolation from
zero. The existing effective-activity cap in the ionosphere interpolation is
retained. RadioWorkbench's Swift/helper/feed-parser validation must also admit
zero so the value reaches this engine.

## Reproduction

```
bash script/build_propagation.sh /tmp/rwb-hf-audit
clang -arch arm64 -O2 -std=c99 -fcommon \
  -I Vendor/ITU-R-HF/P533/Src/P533 \
  Vendor/ITU-R-HF/tests/hemisphere-tests.c \
  -L /tmp/rwb-hf-audit -lp533 -Wl,-rpath,/tmp/rwb-hf-audit \
  -o /tmp/rwb-hf-hemisphere-tests
/tmp/rwb-hf-hemisphere-tests
```

The corrected library passes 21 checks; the pre-correction library fails 11.
`tests/validation-summary.json` retains original/corrected whole-path outputs.
The published Luxembourg reference retains the same received power, SNR,
noise components, MUF and BCR after the changes.

The audit also confirmed the wrapper's existing unit conversions: watts to
dB relative to 1 kW, received dBW to dBm, bandwidth in Hz, and the SNR bandwidth
term. The calculation remains analog/noise-based BCR, with constant isotropic
gains; it does not evaluate decoder-specific delay/Doppler spread, interference,
an actual two-way contact, or current storm measurements.
