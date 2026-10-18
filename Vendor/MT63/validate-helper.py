#!/usr/bin/env python3
"""Focused PCM contract checks; run after bash script/build_mt63.sh.

Test-only, stdlib-only, no microphone/network/radio access. Pass --sanitize to
compile an additional AddressSanitizer/UndefinedBehaviorSanitizer RX/TX pair.
"""
from array import array
from pathlib import Path
import json
import math
import os
import random
import subprocess
import sys
import threading
import time
import wave

ROOT = Path(__file__).resolve().parents[2]
VENDOR = ROOT / "Vendor/MT63"
BUILD = ROOT / ".build/mt63-audit"
HELPER = ROOT / ".build/mt63-helper"
EXPECTED = "CQ TEST MT63 123"
RNG = random.Random(7163)


def decode(raw, bandwidth=1000, interleave="long", helper=HELPER):
    result = subprocess.run([str(helper), "--bandwidth", str(bandwidth), "--interleave", interleave],
                            input=raw, capture_output=True, check=True,
                            env={**os.environ, "ASAN_OPTIONS": "alloc_dealloc_mismatch=1"})
    assert not result.stderr, result.stderr.decode(errors="replace")
    rows = [json.loads(line) for line in result.stdout.splitlines()]
    for row in rows:
        assert 0 <= row["confidence"] <= 1
        assert math.isfinite(row["frequencyHz"])
        assert len(row["text"]) <= 256
        assert "crcValid" not in row and "snrDB" not in row
    return "".join(row["text"] for row in rows), rows


def fixture(bandwidth, interleave):
    with wave.open(str(ROOT / f"Tests/RadioCoreTests/Fixtures/mt63_{bandwidth}_{interleave}_8000_clean.wav")) as reader:
        pcm = array("h")
        pcm.frombytes(reader.readframes(reader.getnframes()))
        if sys.byteorder != "little":
            pcm.byteswap()
        return array("f", (sample / 32768 for sample in pcm))


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    report = {"provenance": "fldigi MT63tx synthetic source-loopback; no real RF/audio-device reception is claimed", "checks": []}
    for bandwidth in (500, 1000, 2000):
        for interleave in ("short", "long"):
            samples = fixture(bandwidth, interleave)
            raw = samples.tobytes()
            text, rows = decode(raw, bandwidth, interleave)
            assert text == EXPECTED, (bandwidth, interleave, text)
            rms = math.sqrt(sum(value * value for value in samples) / len(samples))
            noisy = array("f", (value + RNG.gauss(0, rms * 0.25) for value in samples))
            noisy_text, _ = decode(noisy.tobytes(), bandwidth, interleave)
            assert noisy_text == EXPECTED, (bandwidth, interleave, noisy_text)
            silence = array("f", [0]) * (8000 * 60)
            assert decode(silence.tobytes(), bandwidth, interleave)[0] == ""
            noise = array("f", (RNG.gauss(0, .15) for _ in range(8000 * 60)))
            assert decode(noise.tobytes(), bandwidth, interleave)[0] == ""
            first_character = next(row["offsetSeconds"] for row in rows if row["text"])
            preamble_seconds = 10000 / bandwidth
            report["checks"].append({"bandwidth": bandwidth, "interleave": interleave,
                "cleanExact": True, "noisy12dBExact": True, "silence60sNoText": True,
                "whiteNoise60sNoText": True, "firstCharacterSeconds": first_character,
                "transmitterPreambleSeconds": preamble_seconds,
                "measuredReceiverLatencySeconds": round(first_character - preamble_seconds, 3)})

    # Keep stdin open and consume stdout concurrently. Tiny writes deliberately
    # split samples across read boundaries and test immediate delivery to a Pipe.
    raw = fixture(2000, "short").tobytes()
    process = subprocess.Popen([str(HELPER), "--bandwidth", "2000", "--interleave", "short"],
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    live_text = []
    received = threading.Event()
    def collect():
        for line in process.stdout:
            live_text.append(json.loads(line)["text"])
            if EXPECTED in "".join(live_text):
                received.set()
    collector = threading.Thread(target=collect, daemon=True)
    collector.start()
    sizes = (1, 3, 7, 39, 101, 257, 1023, 4093)
    position = 0
    while position < len(raw):
        size = sizes[position % len(sizes)]
        process.stdin.write(raw[position:position + size])
        process.stdin.flush()
        position += size
    assert received.wait(3), "Decoded text was not delivered while stdin remained open"
    assert process.poll() is None, "Helper exited before EOF"
    process.stdin.close()
    assert process.wait(timeout=5) == 0
    collector.join(timeout=3)
    assert "".join(live_text) == EXPECTED
    assert not process.stderr.read()
    report["fragmentedWritesTextBeforeEOF"] = True

    nonfinite = array("f", [float("nan"), float("inf"), -float("inf"), 0]) * (8000 * 4)
    assert decode(nonfinite.tobytes())[0] == ""
    report["nonFiniteInputSanitized"] = True
    truncated = subprocess.run([str(HELPER)], input=b"\0", capture_output=True)
    assert truncated.returncode == 3
    report["truncatedSampleRejected"] = True
    for args in (["--bandwidth", "750"], ["--center-hz", "nan"], ["--interleave", "invalid"], ["--center-hz", "500"]):
        assert subprocess.run([str(HELPER), *args], input=b"", capture_output=True).returncode == 2
    report["invalidOptionsRejected"] = True

    if "--sanitize" in sys.argv:
        flags = ["/usr/bin/clang++", "-arch", "arm64", "-O1", "-g", "-std=c++17", "-fsanitize=address,undefined", "-fno-omit-frame-pointer", "-mmacosx-version-min=14.0", "-I", str(VENDOR / "include")]
        common = [str(VENDOR / "src/mt63base.cxx"), str(VENDOR / "src/dsp.cxx")]
        sanitized = BUILD / "mt63-sanitized"
        transmitter = BUILD / "mt63-generator-sanitized"
        subprocess.run(flags + [str(ROOT / "script/mt63-helper.cpp")] + common + ["-o", str(sanitized)], check=True)
        subprocess.run(flags + [str(VENDOR / "fixture-generator.cpp")] + common + ["-o", str(transmitter)], check=True)
        for bandwidth in (500, 1000, 2000):
            for interleave in ("short", "long"):
                generated = subprocess.run([str(transmitter), str(bandwidth), interleave, "1500", EXPECTED],
                    capture_output=True, check=True, env={**os.environ, "ASAN_OPTIONS": "alloc_dealloc_mismatch=1"})
                assert not generated.stderr, generated.stderr.decode(errors="replace")
                assert decode(generated.stdout, bandwidth, interleave, helper=sanitized)[0] == EXPECTED
        report["ASanUBSanAllSixTXAndRX"] = True
        center_cases = 0
        for bandwidth in (500, 1000, 2000):
            for interleave in ("short", "long"):
                for center in ((1000, 2500) if bandwidth < 2000 else (1250, 2500)):
                    generated = subprocess.run([str(transmitter), str(bandwidth), interleave, str(center), EXPECTED],
                        capture_output=True, check=True, env={**os.environ, "ASAN_OPTIONS": "alloc_dealloc_mismatch=1"})
                    result = subprocess.run([str(sanitized), "--bandwidth", str(bandwidth), "--interleave", interleave,
                        "--center-hz", str(center)], input=generated.stdout, capture_output=True, check=True,
                        env={**os.environ, "ASAN_OPTIONS": "alloc_dealloc_mismatch=1"})
                    assert not generated.stderr and not result.stderr
                    assert "".join(json.loads(line)["text"] for line in result.stdout.splitlines()) == EXPECTED
                    center_cases += 1
        report["ASanUBSanCenterBoundaryCases"] = center_cases
        message = 'Q" \\\n\tZ ' + chr(127) + 'A'
        generated = subprocess.run([str(transmitter), "1000", "long", "1500", message],
            capture_output=True, check=True, env={**os.environ, "ASAN_OPTIONS": "alloc_dealloc_mismatch=1"})
        assert decode(generated.stdout, helper=sanitized)[0] == 'Q" \\\n\tZ Á'
        report["JSONEscapingAndLatin1EscapeRecovered"] = True
    (VENDOR / "validation-summary.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
