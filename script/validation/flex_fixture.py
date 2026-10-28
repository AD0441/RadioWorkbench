#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Create synthetic FLEX discriminator WAVs. No SDR, socket or transmitter access.

Framing is independently constructed (generic BCH polynomial division, not the
vendor encoder/tables). Layout checked against multimon-ng 1.6.2 gen_flex.c:
https://github.com/EliasOenal/multimon-ng/blob/3d8e925782b389ec16e3d48dd8b6d94fbb132197/gen_flex.c
Only short-address, unencrypted, single-frame ALPHA/NUMERIC/TONO are generated.
The resulting samples are our synthetic test data under MIT; they are not a
recording of a real subscriber or an independent over-the-air interoperability corpus.
"""
import argparse
import math
import struct
import wave


def reverse(value, count):
    return int(f'{value:0{count}b}'[::-1], 2)


def codeword(data):
    data &= 0x1fffff
    remainder = reverse(data, 21) << 10
    for bit in range(30, 9, -1):
        if remainder & (1 << bit):
            remainder ^= 0x769 << (bit - 10)
    value = data | (reverse(remainder & 0x3ff, 10) << 21)
    return value | ((bin(value).count("1") & 1) << 31)


def checksum(value):
    return (15 - sum((value >> bit) & 15 for bit in range(4, 21, 4))) & 15


def words_for(kind='alpha', message='CQ RADIOWORKBENCH FLEX TEST', capcode=1234567, damage=0):
    words = [0xaaaaa if i % 2 == 0 else 0x155555 for i in range(88)]
    words[0] = 2 << 10
    words[1] = capcode + 0x8000
    if kind == 'alpha':
        chars = [ord(c) for c in message] + [3]
        slots = [0] + chars
        slots += [3] * (-len(slots) % 3)
        slots[0] = (~sum(c for c in slots[1:] if c != 3)) & 0x7f
        payload = [sum(slots[i + j] << (j * 7) for j in range(3)) for i in range(0, len(slots), 3)]
        header = (3 << 11) | (1 << 19)
        k_sum = sum((word & 255) + ((word >> 8) & 255) + ((word >> 16) & 31) for word in [header] + payload)
        payload = [header | ((~k_sum) & 1023)] + payload
        vector = (5 << 4) | (3 << 7) | (len(payload) << 14)
    elif kind == 'numeric':
        bits = [0, 0]
        alphabet = '0123456789 U -]['
        for char in message:
            digit = alphabet.index(char)
            bits += [(digit >> bit) & 1 for bit in range(4)]
        while len(bits) % 21:
            bits += [0, 0, 1, 1]  # fill digit C
        payload = [sum(bits[i + bit] << bit for bit in range(21)) for i in range(0, len(bits), 21)]
        vector = (3 << 4) | (3 << 7) | ((len(payload) - 1) << 14)
    else:
        payload = []
        vector = 2 << 4
    words[2] = vector | checksum(vector)
    words[3:3 + len(payload)] = payload
    encoded = [codeword(word) for word in words]
    # Damage one data word, including its overall parity. Three errors must not
    # be silently miscorrected as a two-bit BCH repair.
    if damage:
        encoded[1] ^= sum(1 << bit for bit in [2, 11, 23][:damage])
    return encoded


def samples(kind='alpha', message='CQ RADIOWORKBENCH FLEX TEST', capcode=1234567,
            baud=1600, levels=2, inverted=False, damage=0, rate=22050, silence=2):
    codes = {(1600, 2): 0x870c, (1600, 4): 0xb068, (3200, 2): 0x7b18, (3200, 4): 0xdea0}
    sync = (codes[baud, levels] << 48) | (0xa6c6aaaa << 16) | (codes[baud, levels] ^ 65535)
    header = [i & 1 for i in range(960)]
    header += [1 - ((sync >> bit) & 1) for bit in range(63, -1, -1)]
    header += [i & 1 for i in range(16)]
    fiw = (2 << 4) | (42 << 8)
    fiw |= checksum(fiw)
    header += [(codeword(fiw) >> bit) & 1 for bit in range(32)]
    values = [0.6 if bit else -0.6 for bit in header]
    # SYNC2 occupies 25 ms at the selected symbol rate. It is timing-only in
    # this helper, but use the published C and inverse-C patterns, repeated at 3200.
    sync2 = [i & 1 for i in range(4)] + [(0xed84 >> bit) & 1 for bit in range(15, -1, -1)]
    sync2 += [1 - (i & 1) for i in range(4)] + [(0x127b >> bit) & 1 for bit in range(15, -1, -1)]
    data = [0.6 if bit else -0.6 for bit in sync2 * (baud // 1600)]
    words = words_for(kind, message, capcode, damage)
    for block in range(11):
        for bit in range(32):
            for word in range(block * 8, block * 8 + 8):
                a = (words[word] >> bit) & 1
                # Test data are repeated on all active phases, with distinct
                # metadata A/B/C/D expected; no claim about independent users.
                value = (0.2 if a else -0.2) if levels == 4 and a else (0.6 if a else -0.6)
                data += [value] * (baud // 1600)
    data += [0.6 if i & 1 else -0.6 for i in range(128)]
    output = []
    for segment, speed in [(values, 1600), (data, baud)]:
        output += [segment[min(len(segment) - 1, i * speed // rate)] for i in range(math.ceil(len(segment) * rate / speed))]
    output += [0.0] * int(silence * rate)
    if inverted:
        output = [-v for v in output]
    return output


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output')
    parser.add_argument('--kind', choices=['alpha', 'numeric', 'tone'], default='alpha')
    parser.add_argument('--message', default='CQ RADIOWORKBENCH FLEX TEST')
    parser.add_argument('--baud', type=int, choices=[1600, 3200], default=1600)
    parser.add_argument('--levels', type=int, choices=[2, 4], default=2)
    parser.add_argument('--errors', type=int, choices=[0, 1, 2, 3], default=0)
    parser.add_argument('--inverted', action='store_true')
    parser.add_argument('--rate', type=int, default=22050)
    args = parser.parse_args()
    audio = samples(kind=args.kind, message=args.message, baud=args.baud, levels=args.levels,
                    inverted=args.inverted, damage=args.errors, rate=args.rate)
    with wave.open(args.output, 'wb') as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(args.rate)
        wav.writeframes(struct.pack('<' + 'h' * len(audio), *(round(v * 32767) for v in audio)))
