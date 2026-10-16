#!/usr/bin/env python3
"""Independent synthetic pager/selcall/ASCII/Feld-Hell audio, without recorded traffic."""
import argparse
import hashlib
import json
import math
import struct
import wave
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--output", default="Tests/RadioCoreTests/Fixtures")
args = parser.parse_args()
folder = Path(args.output)
folder.mkdir(parents=True, exist_ok=True)
manifest = {}

def save(name, rate, samples, metadata):
    path = folder / (name + ".wav")
    with wave.open(str(path), "wb") as audio:
        audio.setnchannels(1); audio.setsampwidth(2); audio.setframerate(rate)
        audio.writeframes(b"".join(struct.pack("<h", max(-32768, min(32767, round(value * 32767)))) for value in samples))
    manifest[path.name] = {"sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "sampleRate": rate, **metadata}

def bch_word(data):
    remainder = data << 10
    for bit in range(30, 9, -1):
        if remainder & (1 << bit): remainder ^= 0x769 << (bit - 10)
    value = (data << 10) | (remainder & 0x3ff)
    return (value << 1) | (value.bit_count() & 1)

for baud in [512, 1200, 2400]:
    rate, capcode = 22050, 123456
    message = f"CQ RADIOWORKBENCH {baud}"
    payload = [(ord(char) >> bit) & 1 for char in message + "\x03" for bit in range(7)]
    words = [bch_word(((capcode >> 3) << 2) | 3)]
    for offset in range(0, len(payload), 20):
        chunk = payload[offset:offset + 20]; chunk += [0] * (20 - len(chunk))
        words.append(bch_word((1 << 20) | sum(bit << (19 - i) for i, bit in enumerate(chunk))))
    words += [0x7a89c197] * (16 - len(words))
    wire = [i % 2 for i in range(576)]
    for batch in [[0x7cd215d8] + words, [0x7cd215d8] + [0x7a89c197] * 16]:
        wire += [(word >> bit) & 1 for word in batch for bit in range(31, -1, -1)]
    samples = [.55 if wire[min(len(wire) - 1, int(i * baud / rate))] else -.55 for i in range(int(len(wire) * rate / baud))]
    samples += [0] * int(.5 * rate)
    save(f"pocsag_{baud}_22050_discriminator_clean", rate, samples,
         {"protocol": "POCSAG", "baud": baud, "capcode": capcode, "function": 3, "expected": message, "input": "FM discriminator NRZ"})

tone_tables = {
    "zvei1": [1060, 2800, 810, 970, 885], "zvei2": [1060, 885, 825, 740, 680],
    "zvei3": [1060, 885, 810, 2800, 680], "pzvei": [1060, 970, 810, 2800, 885],
    "dzvei": [970, 825, 740, 2600, 885], "eea": [1124, 1055, 930, 2400, 991],
    "eia": [741, 2151, 2433, 2010, 2292], "ccir": [1124, 2400, 930, 2247, 991]
}
for standard, frequencies in tone_tables.items():
    rate = 22050
    tone_samples = [0] * round(.15 * rate)
    for frequency in frequencies:
        tone_samples += [.5 * math.sin(2 * math.pi * frequency * i / rate) for i in range(round(.08 * rate))]
    tone_samples += [0] * round(.3 * rate)
    save(f"selcall_{standard}_22050_1abcd", rate, tone_samples, {"standard": standard.upper(), "expected": "1ABCD", "toneMilliseconds": 80})
# Simple numeric sequence shipped for the first UI example.
rate = 22050
samples = [0] * round(.15 * rate)
for frequency in [1060, 1160, 1270, 1400, 1530]:
    samples += [.5 * math.sin(2 * math.pi * frequency * i / rate) for i in range(round(.08 * rate))]
samples += [0] * round(.3 * rate)
save("selcall_zvei1_22050_12345", rate, samples, {"standard": "ZVEI1", "expected": "12345", "toneMilliseconds": 80})

for bits, baud in [(7, 75), (8, 110)]:
    rate, center, shift = 8000, 1500, 170
    message = f"CQ ASCII{bits} RADIOWORKBENCH\n"
    symbols = [1] * 12
    for char in message:
        symbols += [0] + [(ord(char) >> bit) & 1 for bit in range(bits)] + [1, 1]
    symbols += [1] * 12
    phase, samples = 0, []
    for i in range(math.ceil(len(symbols) * rate / baud)):
        mark = symbols[min(len(symbols) - 1, int(i * baud / rate))]
        frequency = center + shift / 2 if mark else center - shift / 2
        samples.append(.6 * math.sin(phase)); phase = (phase + 2 * math.pi * frequency / rate) % (2 * math.pi)
    save(f"rtty_ascii{bits}_8000_{baud}baud", rate, samples, {"encoding": f"ASCII {bits}", "baud": baud, "parity": "none", "stopBits": 2, "center": center, "shift": shift, "expected": message})

# Original tiny glyph patterns for the visual test, not copied fldigi fonts.
glyphs = {"C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
          "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"]}
columns = [[0] * 14]
for char in "CQ":
    for col in range(5):
        # Scanned bottom-to-top. Each of the seven font dots spans two transmitted pixels.
        columns.append([int(glyphs[char][6 - row][col]) for row in range(7) for _ in range(2)])
    columns += [[0] * 14, [0] * 14]
wire = [pixel for column in columns for pixel in column]
for name, column_rate, center in [("feld", 17.5, 1500), ("slow14", 2, 1500), ("slow_fldigi", 2.1875, 1500), ("x5", 87.5, 1500), ("x9", 157.5, 2000)]:
    rate, start = 8000, .2
    samples = [0] * round(start * rate)
    for i in range(round(len(wire) * rate / (14 * column_rate))):
        pixel = wire[min(len(wire) - 1, int(i * 14 * column_rate / rate))]
        samples.append(.6 * math.sin(2 * math.pi * center * i / rate) if pixel else 0)
    samples += [0] * round(.2 * rate)
    save(f"hell_{name}_8000_cq_clean", rate, samples, {"variant": name, "columnRate": column_rate, "pixelRate": 14 * column_rate, "center": center, "startSeconds": start, "columns": columns, "expected": "CQ as visual glyphs; no OCR"})

(folder / "additional-modes-manifest.json").write_text(json.dumps({"generator": "script/generate_additional_fixtures.py", "type": "synthetic, receive-only", "sources": ["https://github.com/EliasOenal/multimon-ng", "https://github.com/w1hkj/fldigi/blob/master/src/feld/feld.cxx"], "files": manifest}, indent=2) + "\n")
print(f"Generated {len(manifest)} synthetic WAV files in {folder}")
