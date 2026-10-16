# RadioWorkbench integration changes

No upstream source edits. Built as acars_static with zlib ON, libxml2 OFF and jansson OFF. RadioWorkbench adapter in script/acars-helper.c restores odd parity, preserves BCS, validates link blocks, uses native reassembly and checks ARINC CRC before mapping ADS-C coordinates.

Upstream license and individual copyright notices are retained. See source-manifest.json for pinned provenance and upstream/current SHA-256.
