#!/usr/bin/env python3
"""Independent AX.25 UI / Bell 202 transmitter using only Python stdlib.

The CRC uses binascii's MSB-first CRC-CCITT plus explicit bit reflection;
the receiver uses a separate bitwise reflected implementation. No Swift code
or demodulator tables are read. This generates files only, never RF traffic.
"""
import argparse
from array import array
import binascii
import hashlib
import json
import math
from pathlib import Path
import random
import struct
import wave

FIRST = "TEST-1>APRS,WIDE1-1*,WIDE2-2:!3330.00S/07040.00W>RadioWorkbench TEST"
SECOND = "TEST-2>APRS:>SECOND TEST 0123456789"
SOURCES = ["https://files.tapr.org/tech_docs/AX25/AX25.2.2.1997.pdf",
           "https://www.aprs.org/doc/APRS101.PDF",
           "https://www.rfc-editor.org/rfc/rfc1662.html#appendix-C"]


def reverse_bits(value, count):
    return int(f"{value:0{count}b}"[::-1], 2)


def fcs(data):
    reflected = bytes(reverse_bits(byte, 8) for byte in data)
    return reverse_bits(binascii.crc_hqx(reflected, 0xffff) ^ 0xffff, 16)


def address(text, last=False):
    repeated = text.endswith("*")
    call, _, ssid = text.rstrip("*").partition("-")
    return bytes([ord(c) * 2 for c in call.ljust(6)] +
                 [0x60 | (int(ssid or "0") << 1) | last | (0x80 if repeated else 0)])


def frame(line):
    header, _, information = line.partition(":")
    source, _, destination_path = header.partition(">")
    parts = destination_path.split(",")
    ordered = [parts[0], source] + parts[1:]
    body = b"".join(address(call, i == len(ordered)-1) for i, call in enumerate(ordered))
    body += b"\x03\xf0" + information.encode("ascii")
    return body + struct.pack("<H", fcs(body))


def bits_of(data, stuffed):
    result, ones = [], 0
    for byte in data:
        for i in range(8):
            bit = (byte >> i) & 1
            result.append(bit)
            ones = ones + 1 if bit else 0
            if stuffed and ones == 5:
                result.append(0); ones = 0
    return result


def waveform(bits, sample_rate, baud=1200, offset=0, snr=None, phase=.714973):
    # NRZI zero changes tone; one retains tone. Continuous-phase tone mapping
    # is evaluated at fractional boundaries rather than rounding each symbol.
    tone = False
    frequencies = []
    for bit in bits:
        if bit == 0: tone = not tone
        frequencies.append((1200 if tone else 2200) + offset)
    output = array("d")
    for n in range(math.ceil(len(bits) * sample_rate / baud)):
        t = n / sample_rate
        symbol = min(len(bits)-1, int(t * baud))
        if n == 0:
            start = 0.0
            old_symbol = 0
        if symbol != old_symbol:
            boundary = symbol / baud
            phase = (phase + 2 * math.pi * frequencies[old_symbol] * (boundary - start)) % (2 * math.pi)
            start = boundary
            old_symbol = symbol
        output.append(.58 * math.sin(phase + 2 * math.pi * frequencies[symbol] * (t - start)))
    if snr is not None:
        rng = random.Random(12002200)
        sigma = .58 / math.sqrt(2) * 10 ** (-snr / 20)
        output = array("d", (x + rng.gauss(0, sigma) for x in output))
    return output


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path,
                        default=Path(__file__).resolve().parent.parent / "Tests/RadioCoreTests/Fixtures")
    options = parser.parse_args()
    options.output.mkdir(parents=True, exist_ok=True)
    first, second = frame(FIRST), frame(SECOND)
    assert fcs(b"123456789") == 0x906e
    flag = bits_of(b"\x7e", False)
    valid = flag * 48 + bits_of(first, True) + flag * 8
    bad = bytearray(first); bad[-3] ^= 1
    invalid = flag * 48 + bits_of(bad, True) + flag * 8
    trailing = flag * 48 + bits_of(second, True) + flag * 8
    variants = [
        (8000, 1, "clean", valid, 1200, 0, None, FIRST + "\n", 1, 0),
        (8000, 1, "noisy", valid, 1200, 0, 16, FIRST + "\n", 1, 0),
        (8000, 1, "offset", valid, 1200, 45, None, FIRST + "\n", 1, 0),
        (8000, 1, "drift", valid, 1206, 0, None, FIRST + "\n", 1, 0),
        (8000, 1, "crc_bad", invalid, 1200, 0, None, "", 0, 1),
        (44100, 2, "clean", valid, 1200, 0, None, FIRST + "\n", 1, 0),
        (48000, 2, "opposite", valid, 1200, 0, None, FIRST + "\n", 1, 0),
    ]
    entries = []
    for rate, channels, variant, bits, baud, offset, snr, expected, accepted, crc_bad in variants:
        name = f"packet_{rate}_{'mono' if channels == 1 else 'stereo'}_{variant}.wav"
        body = waveform(bits, rate, baud, offset, snr)
        audio = array("d", [0]) * round(.237919 * rate)
        audio.extend(body); audio.extend(array("d", [0]) * round(.15 * rate))
        pcm = array("h")
        for sample in audio:
            value = round(max(-1, min(1, sample)) * 32767)
            pcm.append(value)
            if channels == 2: pcm.append(-value if variant == "opposite" else value)
        path = options.output / name
        with wave.open(str(path), "wb") as handle:
            handle.setnchannels(channels); handle.setsampwidth(2); handle.setframerate(rate)
            handle.writeframes(pcm.tobytes())
        entries.append(dict(file=name, sample_rate=rate, channels=channels, baud=baud,
                            tone_offset_hz=offset, noise_snr_db=snr, expected_text=expected,
                            accepted=accepted, rejected_crc=crc_bad,
                            sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                            wire_bits="".join(map(str,bits))))
    # Acquisition after two independent bursts and after a corrupt frame.
    sequence = waveform(valid, 8000)
    sequence.extend(array("d", [0]) * 2000)
    sequence.extend(waveform(invalid, 8000, phase=1.72))
    sequence.extend(array("d", [0]) * 2000)
    sequence.extend(waveform(trailing, 8000, phase=2.37))
    sequence.extend(array("d", [0]) * 1200)
    name = "packet_8000_mono_resync.wav"
    path = options.output / name
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1); handle.setsampwidth(2); handle.setframerate(8000)
        handle.writeframes(array("h", (round(x*32767) for x in sequence)).tobytes())
    entries.append(dict(file=name, sample_rate=8000, channels=1, baud=1200,
                        tone_offset_hz=0, noise_snr_db=None, expected_text=FIRST+"\n"+SECOND+"\n",
                        accepted=2, rejected_crc=1, sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                        wire_bits="".join(map(str,valid+invalid+trailing))))
    manifest = dict(generator="stdlib independent AX.25 UI transmitter; no decoder dependency",
                    sources=SOURCES, valid_frame_hex=first.hex(), fixtures=entries)
    (options.output / "packet-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Generated {len(entries)} packet WAV fixtures in {options.output}")


if __name__ == "__main__":
    main()
