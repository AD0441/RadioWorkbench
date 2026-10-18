# ITU-R HF model included in RadioWorkbench

Repository: https://github.com/ITU-R-Study-Group-3/ITU-R-HF
Revision: 82017594a1c6cacfaa7e86954c4ae7b3a5825a3d
P.533 implementation version 14.2; P.372 implementation version 14.3.

The use notice in `P533/Src/P533/P533.c` applies to the collaboratively developed ITURHFProp, P533 and P372 software. It permits use by implementers of the Recommendations free from copyright assertions and provides the software as is, without warranties. Original notices remain in the source files, including the older ITU publication notice in Common.h. No replacement license is asserted by RadioWorkbench.

Every upstream file was originally checked against its Git blob SHA and recorded with SHA-256 in source-manifest.json. Three local source corrections now fix a southern polar-winter latitude sign, select geomagnetic variability by latitude magnitude in both hemispheres, and accept the documented R12=0 solar minimum. Original and local hashes remain traceable in the manifest; see LOCAL-CHANGES.md and the focused regression tests. The build additionally stages a copy and replaces the noise-library lookup with `@executable_path/libp372.dylib`, ensuring the helper loads the bundled library. It supplies errno.h via the compiler for MakeNoise.c and uses common symbols for the upstream C headers. No coefficient values, ionosphere maps or noise datasets were changed.

The app contains native arm64 helpers/libraries, all 12 monthly ionosphere maps, 12 atmospheric coefficient files and P.1239 decile factors in Contents/Resources/Propagation. Code, build wrapper and reference input/output are in Propagation-Sources.tar.gz. To rebuild, restore each Data file to the P533/Data or P372/Data path listed in source-manifest.json, then run script/build_propagation.sh. Sources and datasets are also present in the RadioWorkbench project.

This calculation models monthly conditions, not real-time measurements. NOAA observations and D-RAP outputs are obtained separately and are not injected into P.533.
