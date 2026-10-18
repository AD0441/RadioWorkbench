#!/usr/bin/env python3
"""Independent arithmetic ALE 2G modulator; produces files only, never RF/audio playback.

No decoder lookup tables or upstream encoder are imported. Extended binary Golay
is polynomial division (0xAE3) plus even parity. Two 24-bit codewords are bit
interleaved, the lower parity half inverted, one stuff bit added and repeated
three times; Gray-labelled phase-continuous 8FSK carries 3 bits/symbol at 125 baud.
"""
from pathlib import Path
import hashlib
import json
import math
import random
import struct
import wave

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / 'Tests/RadioCoreTests/Fixtures'
FREQUENCIES = {0: 750, 1: 1000, 3: 1250, 2: 1500, 6: 1750, 7: 2000, 5: 2250, 4: 2500}


def golay24(data):
    remainder = data << 11
    for bit in range(22, 10, -1):
        if remainder & (1 << bit):
            remainder ^= 0xAE3 << (bit - 11)
    code23 = (data << 11) | remainder
    return (code23 << 1) | (code23.bit_count() & 1)


def word_bits(preamble, text):
    assert len(text) == 3
    value = (preamble << 21) | (ord(text[0]) << 14) | (ord(text[1]) << 7) | ord(text[2])
    upper, lower = golay24(value >> 12), golay24(value & 0xFFF) ^ 0xFFF
    bits = []
    for bit in range(23, -1, -1):
        bits.extend([(upper >> bit) & 1, (lower >> bit) & 1])
    return (bits + [0]) * 3


def synthesize(words, offset=0.0, noise=0.0):
    bits = [bit for preamble, text in words for bit in word_bits(preamble, text)]
    samples = [0.0] * 400
    phase = 0.0
    rng = random.Random(220141)
    for i in range(0, len(bits), 3):
        frequency = FREQUENCIES[bits[i] * 4 + bits[i + 1] * 2 + bits[i + 2]] + offset
        step = 2 * math.pi * frequency / 8000
        for _ in range(64):
            samples.append(0.5 * math.sin(phase) + rng.gauss(0, noise))
            phase = (phase + step) % (2 * math.pi)
    return samples + [0.0] * 24000


def main():
    FIXTURES.mkdir(parents=True, exist_ok=True)
    words = [(5, 'LAB')] * 12 + [(6, 'RAD'), (0, 'IOW'), (7, 'ORK'), (0, 'BEN'), (7, 'CH '), (0, 'TES'), (7, 'T  ')]
    rows = []
    for name, offset, noise in [('ale2g_8000_synthetic', 0, 0), ('ale2g_8000_noisy_offset', 25, 0.025), ('ale2g_sounding_8000_synthetic', 0, 0)]:
        samples = synthesize([(5, 'LAB')] * 12 if 'sounding' in name else words, offset, noise)
        path = FIXTURES / (name + '.wav')
        with wave.open(str(path), 'wb') as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(8000)
            wav.writeframes(b''.join(struct.pack('<h', round(max(-1, min(1, x)) * 32767)) for x in samples))
        rows.append({'file': path.name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'sampleRate': 8000,
                     'offsetHz': offset, 'noiseStandardDeviation': noise, 'expected': ['LAB'] if 'sounding' in name else ['RADIOWORKBENCH TEST'], 'durationSeconds': len(samples) / 8000})
    (FIXTURES / 'ale2g-manifest.json').write_text(json.dumps({'generatedLocally': True, 'noRFTransmission': True,
        'license': 'CC0-1.0 synthetic signals and messages', 'encoder': 'independent Python polynomial Golay/FEC/8FSK arithmetic; no decoder lookup tables imported',
        'fixtures': rows}, indent=2) + '\n')


if __name__ == '__main__':
    main()
