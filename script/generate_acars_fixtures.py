"""Independent ACARS byte/CRC/NRZI audio generator (Python stdlib only)."""
import math, pathlib, struct, wave, hashlib, json
ROOT = pathlib.Path(__file__).resolve().parents[1] / 'Tests/RadioCoreTests/Fixtures'

def parity(byte):
    return byte | (0x80 if bin(byte).count('1') % 2 == 0 else 0)

def crc16(data):
    crc = 0
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ (0x8408 if crc & 1 else 0)
    return crc

def transmit(name, rate, parity_errors=0, bad_crc=False, body=None):
    body = body or b'2.TEST00\x15H11\x020001TST001RADIOWORKBENCH ACARS TEST\x03'
    framed = bytearray(parity(b) for b in body)
    check = crc16(framed)
    if parity_errors:
        # Four independently wrong parity bits exceed the engine's repair bound.
        for index in (2, 3, 4, 5)[:parity_errors]: framed[index] ^= 0x80
    if bad_crc: check ^= 0xffff
    carrier = bytes([255] * 40) + bytes([0xab,0x2a,0x16,0x16,0x01]) + framed + struct.pack('<H',check) + bytes([0x7f,255,255])
    bits = [(b >> i) & 1 for b in carrier for i in range(8)]
    tones, previous = [], 1
    for bit in bits:
        tones.append(2400 if bit == previous else 1200); previous = bit
    phases = [0.731]
    for frequency in tones: phases.append(phases[-1] + 2 * math.pi * frequency / 2400)
    out = bytearray()
    for _ in range(int(rate * .15)): out.extend(b'\0\0')
    for n in range(math.ceil(len(bits) * rate / 2400)):
        # Integrate exact symbol boundaries, including fractional sample periods.
        # Rounding each tone switch to a sample introduces cumulative phase error.
        t = (n + 1) / rate
        symbol = min(len(tones)-1, int(t * 2400))
        phase = phases[symbol] + 2 * math.pi * tones[symbol] * (t - symbol / 2400)
        out.extend(struct.pack('<h', int(.55 * 32767 * math.sin(phase))))
    out.extend(b'\0\0' * int(rate * .2))
    path = ROOT / (name + '.wav')
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate); w.writeframes(out)
    return {'file': path.name,'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'expected_messages': 0 if parity_errors > 3 or bad_crc else 1, 'bytes_hex': carrier.hex()}

if __name__ == '__main__':
    rows = [transmit(f'acars_synthetic_{r}',r) for r in (12000,44100,48000)]
    rows.append(transmit('acars_synthetic_bad_parity',12000,4))
    rows.append(transmit('acars_synthetic_repaired',12000,1))
    rows.append(transmit('acars_synthetic_bad_crc',12000,bad_crc=True))
    (ROOT/'acars-synthetic-manifest.json').write_text(json.dumps(rows,indent=2)+'\n')
