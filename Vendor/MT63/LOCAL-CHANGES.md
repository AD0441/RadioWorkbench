# RadioWorkbench standalone MT63 source subset

Upstream: [w1hkj/fldigi](https://github.com/w1hkj/fldigi), revision
`61b97f4133c488063f3de1795c894d22d5032e8a`. This official GitHub mirror points
to fldigi's SourceForge repository. Copyright notices and GPL-3.0-or-later
terms are retained; `COPYING` is the upstream GPLv3 text.

Only `src/include/{dsp.h,mt63base.h}`, `src/mt63/{dsp.cxx,mt63base.cxx,
mt63intl.dat,symbol.dat,mt63.cxx}`, and the project notices are copied. The
complete upstream `mt63.cxx` is included as an API/receive-filter reference; it
is not compiled and has no FLTK dependency in the standalone helper.

Local source changes:

1. `include/config.h` is a minimal build header. These two DSP translation units
   include upstream `config.h` but do not depend on any configure-time macros.
2. `include/dsp.h` restores a consistent C allocation family for trivially
   copyable DSP buffers. Upstream mixed `new[]` with `free()`, multiplied element
   counts by `sizeof` twice in several allocation helpers, and discarded or
   leaked existing `dspSeq` data when growing a buffer. The adapter uses
   `malloc`/`calloc`/`realloc`/`free`, preserving old data on growth and retaining
   existing storage if allocation fails. DSP filtering and code tables are
   unchanged.
3. `src/mt63base.cxx`: `MT63tx::Preset` initializes the phase mask from
   `SymbolLen - 1`; upstream read `FFT.Size` before its first preset. This matters
   for the separate synthetic transmitter, which is not exposed in the app.
4. `src/mt63base.cxx`: `MT63rx::DataProcess` wraps its initial data-carrier FFT
   index with `WindowLenMask`, as it already does subsequent indices. Without
   this, MT63-500 centered at 1500 Hz reads beyond the FFT buffer; ASan reproduced
   the fault. This change also permits other valid audio centers whose band
   aliases around the internal decimated FFT.
5. `src/dsp.cxx`: the synthetic transmitter's overlap window uses `memmove`
   when sliding an overlapping range and clears the new tail for actual silence.
   ASan reproduced overlapping `memcpy` in upstream `ProcessSilence`.

RadioWorkbench additions outside upstream code:

- `script/mt63-helper.cpp`: receive-only PCM/JSON adapter, separate process,
  fixed 8000 Hz input, bounded reads, JSON escaping, incremental text and flushed
  stdout. The adapter exposes no transmission, rig, network, or device control.
- The adapter publishes text only while the upstream synchronizer is locked,
  after an initial deinterleaver/integration warmup, and while upstream's linear
  Walsh FEC metric is at least 5. This avoids displaying best-match garbage from
  an incomplete interleaver. The metric is not a calibrated SNR; no CRC or SNR
  is claimed. Warmup restarts after loss of lock and can discard the beginning
  of very short or weak transmissions.
- `fixture-generator.cpp` and `validate-helper.py` are test-only source tools,
  never packaged as executables in the app. Production linking uses dead-strip
  so unused upstream TX code is removed from the receive helper.

Hashes of the local and upstream versions are recorded in `source-manifest.json`.
