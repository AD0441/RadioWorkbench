# Local changes

The Qt vector/map types used by DSCDecoder are replaced by bounded standard C++
containers. The standalone adaptation retains soft symbol decisions, phasing,
time diversity and ECC validation. Message length is bounded to less than 40
symbols, formats/category/origin/EOS are checked and invalid ECC is suppressed
by default. The application never enables the diagnostic `--emit-invalid` flag.

The adapter demodulates mono PCM16 little-endian, normally 48 kHz, using two
sliding tone correlators and a transition-corrected clock. MF/HF uses 100 baud,
170 Hz shift around an explicit adjustable center; VHF uses 1200 baud and
1300/2100 Hz. VHF flat-discriminator audio preserves pre-emphasis; the default
weights those tones accordingly. `--deemphasized` selects already compensated
audio. This differs from SDRangel's IQ/FM receiver graph and does not establish
equal sensitivity or tolerance.

The JSON interpretation is deliberately partial: format, source/destination
identity and a narrow recognized working-channel layout are exposed, alongside
all decoded symbols and ECC status. A nonzero tenth identity digit is retained
as a suffix, rather than silently discarded. Coordinates, geographic areas,
distress nature, telecommands and all other layouts are not inferred. ECC is
an error check, not authentication. `symbol_errors` is a discrepancy counter;
it is not BER or a count of corrected symbols. No rescue notification or RF
transmission is performed.

Regression evidence: `docs/validation/dsc-prototype-0.10.json`. It covers a
public VHF recording with author-supplied identity/channel oracle, independent
MF/HF recorded audio and synthetic negatives. The public recordings are not
redistributed: their licenses were not established. Synthetic recordings made
by the local validation script can be reproduced independently of the helper.
