#!/usr/bin/env python3
"""Mathematical SITOR-B transmitter from ITU-R M.476/M.625.

No decoder code is imported or used. Emitted B/Y strings are transcribed from
M.476 Table 1, rather than using RadioWorkbench's byte table. No RF transmission.
"""
import argparse
from array import array
import hashlib
import json
import math
from pathlib import Path
import random
import sys
import wave

SIGNALS = dict(zip('ABCDEFGHIJKLMNOPQRSTUVWXYZ', [
    'BBBYYYB','YBYYBBB','BYBBBYY','BBYYBYB','YBBYBYB','BBYBBYY',
    'BYBYBBY','BYYBYBB','BYBBYYB','BBBYBYY','YBBBBYY','BYBYYBB',
    'BYYBBBY','BYYBBYB','BYYYBBB','BYBBYBY','YBBBYBY','BYBYBYB',
    'BBYBYYB','YYBYBBB','YBBBYYB','YYBBBBY','BBBYYBY','YBYBBBY',
    'BBYBYBY','BBYYYBB'
]))
SIGNALS.update({'\r':'YYYBBBB', '\n':'YYBBYBB', '<LTRS>':'YBYBBYB',
                '<FIGS>':'YBBYBBY', ' ':'YYBBBYB', '<ALPHA>':'BBBBYYY', '<REP>':'YBBYYBB'})
FIGURES = dict(zip('-?:38\a().,9014\'57=2/6+', 'ABCEIJKLMNOPQRSTUVWXYZ'))
MESSAGE = "ZCZC SA01\r\nTEST MESSAGE ONLY\r\nWIND 12 KT. SEA 2 M.\r\nTEST NUMBERS 0123456789 -?:'/+=().,\a\r\nNNNN\r\n"
SOURCES = [
    'https://www.itu.int/dms_pubrec/itu-r/rec/m/R-REC-M.476-5-199510-I!!PDF-E.pdf',
    'https://www.itu.int/dms_pubrec/itu-r/rec/m/R-REC-M.625-4-201203-I!!PDF-E.pdf',
]


def encode_text(text):
    symbols = ['<LTRS>', '\r', '\n']
    figures = False
    for c in text:
        if c not in ' \r\n':
            desired = c not in SIGNALS
            if figures != desired:
                symbols.append('<FIGS>' if desired else '<LTRS>')
                figures = desired
        symbols.append(FIGURES[c] if figures and c not in ' \r\n' else c)
    symbols.append('<LTRS>')
    return symbols


def interleave(symbols):
    # One first copy in even slots, its second copy five slots later.
    # Three flush slots deliver the last outstanding repeated characters.
    result = ['<REP>', '<ALPHA>'] * 16
    for i in range(len(symbols) + 3):
        result.append(symbols[i] if i < len(symbols) else '<ALPHA>')
        result.append(symbols[i-2] if 0 <= i-2 < len(symbols) else '<ALPHA>')
    result += ['<REP>', '<ALPHA>'] * 4
    return result


def make_wave(sample_rate, variant):
    symbols = interleave(encode_text(MESSAGE))
    wire = [[1 if c == 'B' else 0 for c in SIGNALS[s]] for s in symbols]
    expected = MESSAGE.replace('\r', '').replace('\a', '')
    expected_corrected = expected_erased = expected_disagreement = 0
    # First Z begins at text-symbol index3, hence interleaved slot38.
    first, second = 32 + 2*3, 32 + 2*3 + 5
    if variant in {'repaired','lost'}:
        wire[first][0] ^= 1
        expected_corrected = 1
    if variant == 'lost':
        wire[second][0] ^= 1
        expected = '�' + expected[1:]; expected_corrected = 0; expected_erased = 1
    if variant == 'disagree':
        wire[second] = [1 if c == 'B' else 0 for c in SIGNALS['A']]
        expected = '�' + expected[1:]; expected_erased = expected_disagreement = 1
    bits = [b for word in wire for b in word]
    inverted = variant == 'inverted'
    baud = 100.1 if variant == 'drift' else 100.0
    noise_snr = 18.0 if variant == 'noisy' else None
    duration = len(bits)/baud
    body = array('f')
    phase = .731234
    for symbol, bit in enumerate(bits):
        logical = bool(bit) != inverted
        frequency = 1785.0 if logical else 1615.0
        start, end = symbol/baud, (symbol+1)/baud
        for i in range(round(start*sample_rate), round(end*sample_rate)):
            body.append(.58*math.sin(phase+2*math.pi*frequency*(i/sample_rate-start)))
        phase = (phase + 2*math.pi*frequency/baud) % (2*math.pi)
    if noise_snr is not None:
        rng = random.Random(476625)
        sigma = .58/math.sqrt(2)*10**(-noise_snr/20)
        body = array('f', (v+rng.gauss(0,sigma) for v in body))
    silence = .37319 if variant in {'offset','drift'} else .5
    samples = array('f', [0])*round(silence*sample_rate)
    samples.extend(body); samples.extend(array('f', [0])*sample_rate)
    if variant == 'resync':
        samples.extend(array('f', [0])*sample_rate)
        samples.extend(body); samples.extend(array('f', [0])*sample_rate)
        expected = ('\n' + expected) * 2
    else:
        expected = '\n' + expected
    return samples, {
        'expected_text':expected,'baud':baud,'nominal_baud':100,'center_hz':1700,'shift_hz':170,
        'mark_hz':1615 if inverted else 1785,'space_hz':1785 if inverted else 1615,
        'inverted':inverted,'snr_db':noise_snr,'preamble_pairs':16,
        'first_copy_slot':'REP/even','second_copy_slot':'ALPHA/odd','fec_separation_slots':5,
        'fec_start_to_start_ms':350,'fec_intervening_gap_ms':280,
        'corrected_characters':expected_corrected,'erased_characters':expected_erased,
        'disagreement_characters':expected_disagreement,'sources':SOURCES,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path('/tmp/radio-navtex-fixtures'))
    args = parser.parse_args(); args.output.mkdir(parents=True, exist_ok=True)
    cases = [(8000,'mono',v) for v in ['clean','offset','noisy','repaired','lost','disagree','inverted','drift','resync']]
    cases += [(44100,'stereo','clean'),(48000,'stereo','opposite')]
    manifest = {'schema_version':1,'date':'2026-10-13','generator':'script/generate_navtex_fixtures.py',
                'provenance':'Independent transmitter using emitted B/Y codeword strings from ITU Table 1, not decoder bytes/output',
                'limitations':['Synthetic audio, not off-air reception','No validation of national figures alphabets or selective B mode'], 'fixtures':[]}
    for rate, layout, variant in cases:
        samples, protocol = make_wave(rate, variant)
        channels = 1 if layout == 'mono' else 2
        pcm = array('h')
        for sample in samples:
            value = round(max(-1,min(1,sample))*32767)
            pcm.append(value)
            if channels == 2: pcm.append(-value if variant == 'opposite' else value)
        if sys.byteorder != 'little': pcm.byteswap()
        name = f'navtex_{rate}_{layout}_{variant}.wav'; path = args.output/name
        with wave.open(str(path),'wb') as f:
            f.setnchannels(channels); f.setsampwidth(2); f.setframerate(rate); f.writeframes(pcm.tobytes())
        manifest['fixtures'].append({'file':name,'sample_rate_hz':rate,'channels':channels,'duration_seconds':len(samples)/rate,
                                    'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'protocol':protocol})
    (args.output/'navtex-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'output':str(args.output),'fixtures':len(cases)},indent=2))


if __name__ == '__main__': main()
