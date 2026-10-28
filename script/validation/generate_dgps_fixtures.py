#!/usr/bin/env python3
"""Own, deterministic RTCM2/MSK test transmitter. Never sends audio or RF.

Parity uses the bit equations in IS-GPS-200N Table20-XIV, separately from
the receiver's integer-mask implementation. Framing/MSK: ITU-R M.823-3.
No Swift source or commercial decoder is read. Run from any directory.
"""
import argparse
from array import array
import hashlib
import json
import math
from pathlib import Path
import random
import struct
import wave

PARITY_DATA = [
    [1, 2, 3, 5, 6, 10, 11, 12, 13, 14, 17, 18, 20, 23],
    [2, 3, 4, 6, 7, 11, 12, 13, 14, 15, 18, 19, 21, 24],
    [1, 3, 4, 5, 7, 8, 12, 13, 14, 15, 16, 19, 20, 22],
    [2, 4, 5, 6, 8, 9, 13, 14, 15, 16, 17, 20, 21, 23],
    [1, 3, 5, 6, 7, 9, 10, 14, 15, 16, 17, 18, 21, 22, 24],
    [3, 5, 6, 8, 9, 10, 11, 13, 15, 19, 22, 23, 24],
]


def word(data, previous):
    d = [(data >> (23 - i)) & 1 for i in range(24)]
    parity = []
    for p, indices in enumerate(PARITY_DATA):
        value = previous[0 if p in (0, 2, 5) else 1]
        for index in indices:
            value ^= d[index - 1]
        parity.append(value)
    return [bit ^ previous[1] for bit in d] + parity


def frame(kind, payload, z=2058, sequence=3):
    return [(0x66 << 16) | (kind << 10) | 777,
            (z << 11) | (sequence << 8) | (len(payload) << 3), *payload]


def stream():
    text = b"RWB DGPS TEST 014\0"
    text += b"\0" * ((-len(text)) % 3)
    payload = [int.from_bytes(text[i:i + 3], "big") for i in range(0, len(text), 3)]
    lat, lon, height = math.radians(-33.45), math.radians(-70.6667), 500.0
    a, e2 = 6378137.0, 6.6943799901413165e-3
    n = a / math.sqrt(1 - e2 * math.sin(lat) ** 2)
    xyz = [(n + height) * math.cos(lat) * math.cos(lon),
           (n + height) * math.cos(lat) * math.sin(lon),
           (n * (1 - e2) + height) * math.sin(lat)]
    packed = b"".join(struct.pack(">i", round(value * 100)) for value in xyz)
    position = [int.from_bytes(packed[i:i + 3], "big") for i in range(0, 12, 3)]
    messages = [frame(16, payload), frame(3, position, 2060, 4), frame(6, [], 2062, 5)]
    previous = [1, 1]
    # Alternating acquisition symbols, then the real two predecessor parity bits.
    bits = [0, 1] * 32 + previous
    for message in messages:
        for data in message:
            encoded = word(data, previous)
            bits.extend(encoded)
            previous = encoded[-2:]
    return bits, messages


def audio(bits, rate, bit_rate, offset=0, ppm=0, reversed_sideband=False, snr=None):
    baud = bit_rate * (1 + ppm / 1e6)
    phase, previous_symbol = 0.713, 0
    start, direction = 0.0, -1 if reversed_sideband else 1
    frequencies = [800 + offset + direction * (bit * 2 - 1) * baud / 4 for bit in bits]
    result = array("d", [0]) * round(0.237919 * rate)
    for index in range(math.ceil(len(bits) * rate / baud)):
        time = index / rate
        symbol = min(len(bits) - 1, int(time * baud))
        if symbol != previous_symbol:
            boundary = symbol / baud
            phase = (phase + 2 * math.pi * frequencies[previous_symbol] * (boundary - start)) % (2 * math.pi)
            start, previous_symbol = boundary, symbol
        result.append(0.58 * math.sin(phase + 2 * math.pi * frequencies[symbol] * (time - start)))
    result.extend(array("d", [0]) * round(0.2 * rate))
    if snr is not None:
        rng = random.Random(823200)
        sigma = 0.58 / math.sqrt(2) * 10 ** (-snr / 20)
        result = array("d", (value + rng.gauss(0, sigma) for value in result))
    return array("h", (round(max(-1, min(1, value)) * 32767) for value in result))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path,
                        default=Path(__file__).resolve().parents[2] / "Tests/RadioCoreTests/Fixtures")
    options = parser.parse_args()
    options.output.mkdir(parents=True, exist_ok=True)
    bits, messages = stream()
    cases = [
        ("dgps_100_8000_mono_clean", 8000, 100, 0, 0, False, None, bits, 3),
        ("dgps_200_8000_impaired", 8000, 200, 8, 1000, True, 10, bits, 3),
    ]
    bad = bits.copy()
    bad[66 + 60 + 15] ^= 1  # An actual data bit in the first payload word.
    cases.append(("dgps_200_8000_bad_parity", 8000, 200, 0, 0, False, None, bad, 2))
    entries = []
    for name, rate, baud, offset, ppm, reverse, snr, wire, accepted in cases:
        pcm = audio(wire, rate, baud, offset, ppm, reverse, snr)
        path = options.output / (name + ".wav")
        with wave.open(str(path), "wb") as output:
            output.setparams((1, 2, rate, 0, "NONE", "not compressed"))
            output.writeframes(pcm.tobytes())
        entries.append(dict(file=path.name, sample_rate=rate, bit_rate=baud, offset_hz=offset,
                            clock_ppm=ppm, reversed_sideband=reverse, full_band_snr_db=snr,
                            accepted=accepted, sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    manifest = dict(generator=Path(__file__).name,
                    sources=["https://www.itu.int/rec/R-REC-M.823-3-200603-I/en",
                             "https://www.navcen.uscg.gov/sites/default/files/pdf/gps/IS-GPS-200N.pdf"],
                    expected_message_types=[16, 3, 6], expected_station_id=777,
                    expected_text="RWB DGPS TEST 014", expected_latitude=-33.45,
                    expected_longitude=-70.6667, expected_ellipsoid_height_m=500,
                    recovered_words=messages, wire_bits="".join(map(str, bits)), fixtures=entries)
    (options.output / "dgps-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
