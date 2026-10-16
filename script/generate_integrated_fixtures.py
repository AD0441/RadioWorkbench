#!/usr/bin/env python3
"""Rebuild public protocol fixtures. No sound device, radio, private recording or network is used."""
import hashlib
import json
import math
import os
from pathlib import Path
import runpy
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / 'Tests/RadioCoreTests/Fixtures'
modulator = runpy.run_path(str(ROOT / 'script/generate_acars_fixtures.py'))['transmit']
ads = b'/BOMASAI.ADS.VT-ANB072501A070A988CA73248F0E5DC10200000F5EE1ABC000102B885E0A19F5'
cpdlc = b'/MSTEC7X.AT1.VT-ANE21409DCC3DD03BB52350490502B2E5129D5A15692BA009A08892E7CC831E210A4C06EEBC28B1662BC02360165C80E1F7'
rows = [
    modulator('acars_adsc_12000', 12000, body=b'2.TEST00\x15H11\x02000ATST001' + ads + b'\x03'),
    modulator('acars_adsc_part1_12000', 12000, body=b'2.TEST00\x15H11\x02001ATST001' + ads[:38] + b'\x17'),
    modulator('acars_adsc_part2_12000', 12000, body=b'2.TEST00\x15H12\x02001BTST001' + ads[38:] + b'\x03'),
    modulator('acars_cpdlc_12000', 12000, body=b'2.TEST00\x15BA1\x02002ATST001' + cpdlc + b'\x03'),
    modulator('acars_adsc_bad_inner_crc_12000', 12000, body=b'2.TEST00\x15H11\x02003ATST001' + ads[:-1] + b'0\x03'),
]
(FIXTURES / 'acars-adsc-manifest.json').write_text(json.dumps({'source': 'libacars MIT examples; independent ACARS/MSK modulation', 'fixtures': rows}, indent=2) + '\n')
subprocess.run(['bash', str(ROOT / 'script/generate_ftx_fixtures.sh')], cwd=ROOT, check=True)
engine = os.environ.get('DSD_NEO_PATH')
if engine:
    engine = Path(engine).resolve()
    environment = dict(os.environ, DYLD_FALLBACK_LIBRARY_PATH=str(engine.parent.parent / 'lib'))
    subprocess.run([str(engine), '--frontend', 'none', '-fP', '-M', 'M17:9:TEST00:N0CALL', '-6', str(FIXTURES / 'm17_packet_48000_synthetic.wav'), '-8', '-i', '-', '-o', 'null'], input=b'', env=environment, check=True, capture_output=True, timeout=20)
    tone = b''.join(struct.pack('<h', int(12000 * math.sin(2 * math.pi * 700 * i / 48000))) for i in range(48000 * 3))
    subprocess.run([str(engine), '--frontend', 'none', '-fZ', '-M', 'M17:9:TEST00:N0CALL:48000', '-6', str(FIXTURES / 'm17_voice_48000_synthetic.wav'), '-8', '-i', '-', '-o', 'null'], input=tone, env=environment, check=True, capture_output=True, timeout=20)
cw = runpy.run_path(str(ROOT / 'script/generate_radio_fixtures.py'))['add_morse']
samples, _ = cw(12000, .731, 900, 28)
samples = [0.0] * 6000 + samples + [0.0] * 12000
import wave
with wave.open(str(FIXTURES / 'cwkit_12000_900hz_28wpm.wav'), 'wb') as wav:
    wav.setnchannels(1); wav.setsampwidth(2); wav.setframerate(12000)
    wav.writeframes(b''.join(struct.pack('<h', int(x * 32767)) for x in samples))
files = [p for p in FIXTURES.glob('*.wav') if p.stem.startswith(('ft8_', 'ft4_', 'cwkit_', 'acars_adsc', 'acars_cpdlc', 'm17_'))]
(FIXTURES / 'integrated-engines-manifest.json').write_text(json.dumps({
    'generatedLocally': True, 'noRFTransmission': True,
    'FTX': 'pinned kgoba/ft8_lib generator; CQ LU1ABC GF05, 1500/1200 Hz',
    'ACARS': 'independent MSK, public libacars example payloads; complete/fragmented/invalid-inner-CRC cases',
    'M17': 'official DSD-neo 2.10.0 encoder; public-domain Lorem ipsum packet and synthetic 700 Hz tone through Codec2; no private audio',
    'files': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}
}, indent=2) + '\n')
