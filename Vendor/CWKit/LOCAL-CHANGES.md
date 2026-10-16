# RadioWorkbench integration changes

2026-10-16: Package.swift adds the cw-helper executable. CWNetModel.init accepts an optional explicit modelURL so a signed app can load its bundled model without relying on a SwiftPM build path. RadioWorkbenchHelper/main.swift implements bounded Float32 stdin, synchronous pipeline backpressure and JSON output. CWKit minimum remains macOS 15. Original CPU-only inference remains unchanged.

Upstream license and individual copyright notices are retained. See source-manifest.json for pinned provenance and upstream/current SHA-256.
