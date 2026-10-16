# RadioWorkbench integration changes

2026-10-16: ft8/decode.c extends the FT4 candidate start range to cover a complete 7.5-second waterfall, allowing the upstream centered waveform to decode. FT8 search bounds are unchanged. RadioWorkbench stdin/JSON adapter and build recipe live in script/ftx-helper.c and script/build_ftx.sh; output never labels sync score as SNR.

Upstream license and individual copyright notices are retained. See source-manifest.json for pinned provenance and upstream/current SHA-256.
