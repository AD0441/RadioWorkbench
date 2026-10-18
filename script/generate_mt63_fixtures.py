#!/usr/bin/env python3
"""Build the separate upstream MT63 test transmitter and regenerate public WAVs.

Only synthetic text is used. This generator is never shipped as an executable
inside the application and does not access microphones or radio hardware.
"""
from array import array
from pathlib import Path
import hashlib
import json
import subprocess
import sys
import wave

ROOT = Path(__file__).resolve().parent.parent
VENDOR = ROOT / "Vendor/MT63"
BUILD = ROOT / ".build/mt63-audit"
FIXTURES = ROOT / "Tests/RadioCoreTests/Fixtures"
MESSAGE = "CQ TEST MT63 123"


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    generator = BUILD / "mt63-fixture-generator"
    subprocess.run([
        "/usr/bin/clang++", "-arch", "arm64", "-O2", "-std=c++17",
        "-mmacosx-version-min=14.0", "-I", str(VENDOR / "include"),
        str(VENDOR / "fixture-generator.cpp"), str(VENDOR / "src/mt63base.cxx"),
        str(VENDOR / "src/dsp.cxx"), "-o", str(generator),
    ], check=True)
    entries = []
    for bandwidth in (500, 1000, 2000):
        for interleave in ("short", "long"):
            raw = subprocess.check_output([
                str(generator), str(bandwidth), interleave, "1500", MESSAGE,
            ])
            samples = array("f")
            samples.frombytes(raw)
            pcm16 = array("h", (round(max(-1, min(1, value)) * 32767) for value in samples))
            if sys.byteorder != "little":
                pcm16.byteswap()
            name = f"mt63_{bandwidth}_{interleave}_8000_clean.wav"
            output = FIXTURES / name
            with wave.open(str(output), "wb") as writer:
                writer.setnchannels(1)
                writer.setsampwidth(2)
                writer.setframerate(8000)
                writer.writeframes(pcm16.tobytes())
            entries.append({
                "file": name, "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
                "samples": len(samples), "seconds": len(samples) / 8000,
                "sampleRate": 8000, "bandwidth": bandwidth, "interleave": interleave,
                "centerHz": 1500, "expectedText": MESSAGE,
            })
            print(name, len(samples), "samples")
    (VENDOR / "fixture-manifest.json").write_text(json.dumps({
        "provenance": "Synthetic fldigi MT63tx waveform, received by standalone MT63rx adapter; source loopback, not an independent over-the-air recording.",
        "upstream": "https://github.com/w1hkj/fldigi",
        "revision": "61b97f4133c488063f3de1795c894d22d5032e8a",
        "generator": "script/generate_mt63_fixtures.py + Vendor/MT63/fixture-generator.cpp",
        "files": entries,
    }, indent=2) + "\n")


if __name__ == "__main__":
    main()
