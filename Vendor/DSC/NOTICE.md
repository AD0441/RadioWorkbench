# DSC · standalone adaptation

Source: [SDRangel](https://github.com/f4exb/sdrangel), revision
`137c608fa908ac1e942e323357398c8e98399dde` (17 October 2026).
The six retained upstream files were fetched at that revision and compared
byte-for-byte with the investigation copies. See `source-manifest.json`.

Copyright (C) 2023 Jon Beniston, M7RCE. GNU GPL version 3 or, at your option,
any later version. Complete terms: `COPYING`. Original notices are retained.

`decoder.h` and `decoder.cpp` adapt the DSC symbol/framing decoder; the original
files remain under `upstream/`. RadioWorkbench's standalone PCM tone correlators,
clock recovery, CLI and JSON adapter are in `script/dsc-helper.cpp`, under the
same GPL-3.0-or-later terms. No commercial MultiMode binary or SDRangel plugin
binary is redistributed.

The source archive supplied with the application includes the helper, decoder,
original files, build/validation scripts, manifest and these notices. A C++17
Apple Clang compiler builds the arm64 helper; Qt and SDR hardware are unnecessary.
