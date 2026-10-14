#!/usr/bin/env python3
"""Generate reproducible protocol audio fixtures using only Python's stdlib.

No decoder implementation is imported, inspected or invoked. Nothing is played
or transmitted. Waveforms are calculated at their final sample rates, without
resampling, and are saved as little-endian PCM16 WAV files.
"""

import argparse
import hashlib
import json
import math
from pathlib import Path
import random
import struct
import wave

TAU = 2.0 * math.pi
AMPLITUDE = 0.58

MORSE = {
    "C": "-.-.", "Q": "--.-", "T": "-", "E": ".", "S": "...",
    "1": ".----", "2": "..---", "3": "...--",
}

# Only the public G3PLX codewords needed by this fixture. These were checked
# against ARRL's protocol specification, not a modem implementation.
VARICODE = {
    "C": "10101101", "Q": "111011101", " ": "1", "t": "101",
    "e": "11", "s": "10111", "1": "10111101", "2": "11101101",
    "3": "11111111",
}

# ITA2 integer values; data is serialized least-significant bit first.
LETTERS = {"C": 14, "Q": 23, "T": 16, "E": 1, "S": 5, " ": 4}
FIGURES = {"1": 23, "2": 19, "3": 1, " ": 4}
LTRS, FIGS = 31, 27

DTMF_ROWS = [697.0, 770.0, 852.0, 941.0]
DTMF_COLUMNS = [1209.0, 1336.0, 1477.0, 1633.0]
DTMF_KEYS = ["123A", "456B", "789C", "*0#D"]

SOURCES = {
    "morse": [{
        "title": "ITU-R M.1677-1: International Morse code",
        "url": "https://www.itu.int/rec/R-REC-M.1677-1-200910-I/en",
        "role": "International alphabet and element/gap timing ratios",
    }],
    "rtty": [{
        "title": "ITU-T S.1: International Telegraph Alphabet No. 2",
        "url": "https://www.itu.int/rec/T-REC-S.1/en",
        "role": "Public ITA2 alphabet; selected amateur framing and tones are explicit fixture parameters",
    }],
    "bpsk31": [{
        "title": "ARRL PSK31 Spec, Steven L Karty N5SK, citing Peter Martinez G3PLX",
        "url": "https://www.arrl.org/psk31-spec",
        "role": "31.25 baud, differential mapping, cosine shaping, idle and needed G3PLX varicode entries",
    }, {
        "title": "Peter Martinez G3PLX: PSK31: A New Radio-Teletype Mode",
        "url": "https://www.arrl.org/files/file/Technology/tis/info/pdf/x9907003.pdf",
        "role": "Original author G3PLX's RadCom article, reprinted in QEX July/August 1999; Table 1 also directly checked for all needed codewords",
    }, {
        "title": "ITU-R M.2034: Telegraphic alphabet for data communication by phase shift keying at 31 baud",
        "url": "https://www.itu.int/rec/R-REC-M.2034/en",
        "role": "Primary standard locator for the published alphabet; not used as an unverified table transcription",
    }],
    "dtmf": [{
        "title": "ITU-T Q.23: Technical features of push-button telephone sets",
        "url": "https://www.itu.int/rec/T-REC-Q.23/en",
        "role": "DTMF 4 by 4 frequency matrix",
    }],
}


def edge_envelope(t, duration, ramp=0.005):
    """Five-millisecond raised-cosine attack/release; t is local time."""
    if t < 0.0 or t >= duration:
        return 0.0
    distance = min(t, duration - t)
    if distance >= ramp:
        return 1.0
    return 0.5 - 0.5 * math.cos(math.pi * distance / ramp)


def add_morse(sample_rate, phase):
    message = "CQ TEST 123"
    unit = 1.2 / 20.0
    events = []
    t = 0.0
    words = message.split(" ")
    for word_index, word in enumerate(words):
        for character_index, character in enumerate(word):
            elements = MORSE[character]
            for element_index, element in enumerate(elements):
                duration = unit * (1 if element == "." else 3)
                events.append((t, t + duration))
                t += duration
                if element_index != len(elements) - 1:
                    t += unit
            if character_index != len(word) - 1:
                t += 3 * unit
        if word_index != len(words) - 1:
            t += 7 * unit
    samples = [0.0] * round(t * sample_rate)
    for start, end in events:
        for i in range(round(start * sample_rate), round(end * sample_rate)):
            local_time = i / sample_rate - start
            samples[i] = (AMPLITUDE * edge_envelope(local_time, end - start)
                          * math.sin(TAU * 700.0 * i / sample_rate + phase))
    return samples, {
        "expected_message": message, "tone_hz": 700.0, "wpm": 20.0,
        "wpm_convention": "PARIS 50 units", "dot_seconds": unit,
        "dash_units": 3, "intra_element_gap_units": 1,
        "character_gap_units": 3, "word_gap_units": 7,
        "keying_edge_seconds": 0.005, "morse_codewords": MORSE,
        "key_down_intervals_seconds_relative_to_signal_start": events,
    }


def add_rtty(sample_rate, phase):
    message = "CQ TEST 123"
    baud = 45.45
    codes = [LTRS]
    figures = False
    for character in message:
        want_figures = character in "123"
        if character != " " and want_figures != figures:
            codes.append(FIGS if want_figures else LTRS)
            figures = want_figures
        codes.append((FIGURES if figures else LETTERS)[character])
    # Explicit return to letters after the message exercises both shift codes.
    codes.append(LTRS)
    segments = [(1, 0.5)]
    for code in codes:
        segments.append((0, 1.0 / baud))
        segments.extend(((code >> bit) & 1, 1.0 / baud) for bit in range(5))
        segments.append((1, 1.5 / baud))
    segments.append((1, 0.4))
    end_time = 0.0
    oscillator_phase = phase
    samples = []
    start_time = 0.0
    for bit, duration in segments:
        end_time += duration
        frequency = 1585.0 if bit else 1415.0
        first, last = round(start_time * sample_rate), round(end_time * sample_rate)
        for i in range(first, last):
            local_time = i / sample_rate - start_time
            samples.append(AMPLITUDE * math.sin(oscillator_phase + TAU * frequency * local_time))
        oscillator_phase = (oscillator_phase + TAU * frequency * duration) % TAU
        start_time = end_time
    # Only the burst endpoints are tapered; FSK boundaries retain phase continuity.
    for i in range(len(samples)):
        samples[i] *= edge_envelope(i / sample_rate, end_time)
    return samples, {
        "expected_message": message, "baud": baud,
        "center_hz": 1500.0, "shift_hz": 170.0,
        "mark_hz": 1585.0, "space_hz": 1415.0,
        "mark_logical_bit": 1, "space_logical_bit": 0,
        "alphabet": "ITA2", "data_bits": 5, "data_bit_order": "LSB first",
        "start_bits": 1, "start_bit_value": 0,
        "stop_bits": 1.5, "stop_bit_value": 1,
        "initial_mark_seconds": 0.5, "final_mark_seconds": 0.4,
        "ita2_codes_decimal": codes, "letters_shift": LTRS, "figures_shift": FIGS,
        "frequency_switching": "Continuous oscillator phase; no clock quantization drift",
    }


def add_bpsk31(sample_rate, phase):
    message = "CQ test 123"
    baud, carrier = 31.25, 1500.0
    payload_bits = "".join(VARICODE[character] + "00" for character in message)
    bits = "0" * 64 + payload_bits + "0" * 16 + "1" * 32
    duration = len(bits) / baud
    samples = []
    previous_sign = 1.0
    symbol_signs = [previous_sign]
    for bit in bits:
        previous_sign *= -1.0 if bit == "0" else 1.0
        symbol_signs.append(previous_sign)
    for i in range(round(duration * sample_rate)):
        t = i / sample_rate
        symbol_position = t * baud
        symbol = min(int(symbol_position), len(bits) - 1)
        u = symbol_position - symbol
        # Raised-cosine interpolation between consecutive phase states:
        # unchanged phase has unit gain, a reversal crosses zero at mid-symbol.
        previous, following = symbol_signs[symbol], symbol_signs[symbol + 1]
        gain = 0.5 * (previous + following) + 0.5 * (previous - following) * math.cos(math.pi * u)
        samples.append(AMPLITUDE * gain * edge_envelope(t, duration)
                       * math.sin(TAU * carrier * t + phase))
    return samples, {
        "expected_message": message, "baud": baud, "carrier_hz": carrier,
        "modulation": "Differential BPSK", "zero_bit": "180 degree phase reversal",
        "one_bit": "No phase reversal", "character_separator_bits": "00",
        "varicode_codewords": VARICODE, "payload_bits": payload_bits,
        "idle_preamble_zero_bits": 64, "idle_after_payload_zero_bits": 16,
        "unmodulated_postamble_one_bits": 32,
        "waveform_shape": "Cosine interpolation of consecutive signed carrier states across each symbol; zero at reversal midpoint",
        "phase_state_reference": "At integer multiples of 1/31.25 seconds relative to signal start",
    }


def add_dtmf(sample_rate, phase):
    message = "123A456B789C*0#D"
    tone_seconds, gap_seconds = 0.14, 0.10
    duration = len(message) * tone_seconds + (len(message) - 1) * gap_seconds
    samples = [0.0] * round(duration * sample_rate)
    intervals = []
    for character_index, key in enumerate(message):
        row = next(index for index, text in enumerate(DTMF_KEYS) if key in text)
        column = DTMF_KEYS[row].index(key)
        low, high = DTMF_ROWS[row], DTMF_COLUMNS[column]
        start = character_index * (tone_seconds + gap_seconds)
        end = start + tone_seconds
        intervals.append({"key": key, "start_seconds": start, "end_seconds": end,
                          "low_hz": low, "high_hz": high})
        for i in range(round(start * sample_rate), round(end * sample_rate)):
            local_time = i / sample_rate - start
            low_tone = math.sin(TAU * low * local_time + phase)
            high_tone = math.sin(TAU * high * local_time + phase + 0.37)
            samples[i] = AMPLITUDE * 0.5 * (low_tone + high_tone) * edge_envelope(local_time, tone_seconds)
    return samples, {
        "expected_message": message, "tone_seconds": tone_seconds,
        "interdigit_gap_seconds": gap_seconds, "keying_edge_seconds": 0.005,
        "rows_hz": DTMF_ROWS, "columns_hz": DTMF_COLUMNS,
        "key_matrix": DTMF_KEYS, "twist_db": 0.0,
        "digit_intervals_seconds_relative_to_signal_start": intervals,
    }


def write_pcm16(path, samples, sample_rate, channels):
    data = bytearray()
    clipped = 0
    for sample in samples:
        if sample < -1.0 or sample > 1.0:
            clipped += 1
        pcm = round(max(-1.0, min(1.0, sample)) * 32767)
        data.extend(struct.pack("<h", pcm) * channels)
    with wave.open(str(path), "wb") as writer:
        writer.setnchannels(channels)
        writer.setsampwidth(2)
        writer.setframerate(sample_rate)
        writer.writeframes(data)
    return clipped


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("/tmp/radio-fixtures"))
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    variants = {
        "clean": {"initial_silence_seconds": 0.5, "phase_radians": 0.0, "snr_db": None},
        "offset": {"initial_silence_seconds": 0.37319, "phase_radians": 1.23456789, "snr_db": None},
        "noisy": {"initial_silence_seconds": 0.21737, "phase_radians": 2.173913, "snr_db": 14.0},
    }
    manifest = {
        "schema_version": 1,
        "provenance": "Independent mathematical fixture generator using public protocol specifications and Python standard library only",
        "no_decoder_code_used": True, "no_playback_or_hardware": True,
        "wav_encoding": "Little-endian signed PCM16", "source_verification_date": "2026-10-12",
        "generator": str(Path(__file__).resolve()),
        "sources": SOURCES,
        "limitations": [
            "Synthetic laboratory signals; do not establish real-radio or fading-channel interoperability",
            "Stereo fixtures have identical channels; channel selection and antiphase cancellation are not exercised",
            "Carrier-frequency offsets, speed drift, multipath and adjacent-channel interference are not included",
            "Nominal protocol settings are chosen explicitly; this is not a reproduction of proprietary application audio",
        ],
        "fixtures": [],
    }
    generators = {"morse": add_morse, "rtty": add_rtty, "bpsk31": add_bpsk31, "dtmf": add_dtmf}
    for mode_index, (mode, generator) in enumerate(generators.items()):
        for sample_rate, channels in [(8000, 1), (44100, 2)]:
            for variant_index, (variant, settings) in enumerate(variants.items()):
                body, protocol = generator(sample_rate, settings["phase_radians"])
                prefix_frames = round(settings["initial_silence_seconds"] * sample_rate)
                suffix_frames = round(1.0 * sample_rate)
                samples = [0.0] * prefix_frames + body + [0.0] * suffix_frames
                # Independent deterministic white Gaussian noise in the single
                # mathematical signal; identical stereo copies preserve it.
                seed = 20261012 + 1000 * mode_index + sample_rate + variant_index
                noise_sigma = 0.0
                signal_rms = math.sqrt(sum(sample * sample for sample in body) / len(body))
                if settings["snr_db"] is not None:
                    noise_sigma = signal_rms / (10.0 ** (settings["snr_db"] / 20.0))
                    rng = random.Random(seed)
                    samples = [sample + rng.gauss(0.0, noise_sigma) for sample in samples]
                filename = f"{mode}_{sample_rate}_{'mono' if channels == 1 else 'stereo'}_{variant}.wav"
                path = args.output / filename
                clipped = write_pcm16(path, samples, sample_rate, channels)
                assert clipped == 0, f"Clipped samples in {filename}: {clipped}"
                with wave.open(str(path), "rb") as reader:
                    assert reader.getframerate() == sample_rate
                    assert reader.getnchannels() == channels
                    assert reader.getsampwidth() == 2
                    assert reader.getnframes() == len(samples)
                manifest["fixtures"].append({
                    "file": filename, "absolute_path": str(path.resolve()),
                    "mode": mode, "variant": variant, "sample_rate_hz": sample_rate,
                    "channels": channels, "channel_layout": "mono" if channels == 1 else "identical left and right",
                    "frames": len(samples), "duration_seconds": len(samples) / sample_rate,
                    "signal_start_frame": prefix_frames,
                    "initial_silence_requested_seconds": settings["initial_silence_seconds"],
                    "initial_silence_actual_seconds": prefix_frames / sample_rate,
                    "final_silence_seconds": 1.0, "carrier_phase_radians": settings["phase_radians"],
                    "noise_model": "none" if not noise_sigma else "deterministic zero-mean Gaussian white noise across whole file",
                    "snr_db_relative_to_body_rms": settings["snr_db"],
                    "signal_body_rms": signal_rms, "noise_standard_deviation": noise_sigma,
                    "random_seed": seed if noise_sigma else None, "clipped_sample_count": clipped,
                    "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                    "protocol": protocol,
                })
    manifest_path = args.output / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({"output_directory": str(args.output.resolve()),
                      "manifest": str(manifest_path.resolve()),
                      "wav_files": len(manifest["fixtures"]),
                      "bytes": sum((args.output / item["file"]).stat().st_size for item in manifest["fixtures"]),
                      "modes": list(generators)}, indent=2))


if __name__ == "__main__":
    main()
