#!/usr/bin/env python3
"""Own passive SITOR-A reference. ITU-R M.476-5 wire facts, no RF output.

Generates one short waveform with an explicitly requested retransmission. No
decoder code, CCIR receiver table, commercial binary or off-air audio is used.
"""
import argparse
from array import array
import hashlib
import json
import math
from pathlib import Path
import sys
import wave

WIRE = {
    'T': 'YYBYBBB', 'E': 'YBBYBYB', 'S': 'BBYBYYB', 'I': 'BYBBYYB',
    'O': 'BYYYBBB', 'R': 'BYBYBYB', 'A': 'BBBYYYB', ' ': 'YYBBBYB',
    'Q': 'YBBBYBY', 'W': 'BBBYYBY', '\n': 'YYBBYBB',
    '<FIGS>': 'YBBYBBY', '<LTRS>': 'YBYBBYB',
    '<CS1>': 'BYBYYBB', '<CS2>': 'YBYBYBB',
}
BLOCKS = [('T','E','S'), ('T',' ','S'), ('I','T','O'), ('R',' ','A'),
          ('<FIGS>','Q','W'), ('E','<LTRS>','\n')]
SOURCE = 'https://www.itu.int/dms_pubrec/itu-r/rec/m/R-REC-M.476-5-199510-I!!PDF-E.pdf'


def waveform(rate=8000, inverted=False, return_channel=True, repeat=True):
    bursts = [(0.2, ('<CS1>',))] if return_channel else []
    time = 0.5
    for index, block in enumerate(BLOCKS):
        request = '<CS1>' if index % 2 == 0 else '<CS2>'
        response = '<CS2>' if index % 2 == 0 else '<CS1>'
        if repeat and index == 2:
            bursts.append((time, block))
            if return_channel:
                bursts.append((time + 0.290, (request,)))
            time += 0.450
        bursts.append((time, block))
        if return_channel:
            bursts.append((time + 0.290, (response,)))
        time += 0.450
    samples = array('f', [0]) * round((time + 0.5) * rate)
    for time, names in bursts:
        bits = ''.join(WIRE[name] for name in names)
        phase = 0.731
        for index, bit in enumerate(bits):
            frequency = 1785 if ((bit == 'B') != inverted) else 1615
            start = round((time + index / 100) * rate)
            end = round((time + (index + 1) / 100) * rate)
            for sample in range(start, end):
                samples[sample] = 0.58 * math.sin(phase + 2 * math.pi * frequency * (sample - start) / rate)
            phase = (phase + 2 * math.pi * frequency * (end - start) / rate) % (2 * math.pi)
    return samples


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path('/private/tmp/rwb-sitora-fixtures'))
    parser.add_argument('--rate', type=int, default=8000)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    samples = waveform(args.rate)
    pcm = array('h', (round(max(-1, min(1, value)) * 32767) for value in samples))
    if sys.byteorder != 'little':
        pcm.byteswap()
    path = args.output / f'sitora_{args.rate}_arq.wav'
    with wave.open(str(path), 'wb') as output:
        output.setnchannels(1); output.setsampwidth(2); output.setframerate(args.rate)
        output.writeframes(pcm.tobytes())
    manifest = {
        'schema_version': 1, 'generator': 'script/generate_sitora_fixtures.py',
        'source': SOURCE, 'source_sections': 'Annex 1 Tables 1/2 and 3.1.1–3.1.6',
        'provenance': 'Own mathematical waveform from literal ITU B/Y strings, not receiver bytes',
        'file': path.name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
        'sample_rate_hz': args.rate, 'duration_seconds': len(samples) / args.rate,
        'expected_text': 'TEST SITOR A123\n', 'requested_retransmissions': 1,
        'baud': 100, 'shift_hz': 170, 'center_hz': 1700, 'cycle_ms': 450,
        'information_burst_ms': 210, 'control_burst_ms': 70,
        'limitations': ['Synthetic, not off-air', 'No ARQ transmission',
                        'A valid 4/7 word is not a CRC or proof of error-free reception'],
    }
    (args.output / 'sitora-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps({'output': str(path), 'duration': len(samples) / args.rate}))


if __name__ == '__main__':
    main()
