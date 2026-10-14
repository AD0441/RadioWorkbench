#!/usr/bin/env python3
"""Independent public-protocol image fixtures; Python stdlib only.

Calculate mathematical SSTV/FAX FM audio and NOAA APT AM audio, save PCM16 WAV
and exact PNG source patterns. No decoder code, audio playback or hardware.
"""
import argparse
from array import array
import hashlib
import json
import math
from pathlib import Path
import struct
import sys
import wave
import zlib

TAU = 2 * math.pi
NS = 1_000_000_000
AMPLITUDE = 0.65
SSTV_SOURCE = "https://www.classicsstv.com/downloads/daytonpaper.pdf"
FAX_SOURCE = "https://www.weather.gov/media/marine/WMO_386_Vol_I_2009_en.pdf"
APT_SOURCE = "https://repository.library.noaa.gov/view/noaa/1354/noaa_1354_DS1.pdf"
APT_KLM_SOURCE = "https://www.ncei.noaa.gov/pub/data/cdo/documentation/podguides/N-15%20thru%20N-19/pdf/0.0%20NOAA%20KLM%20Users%20Guide.pdf"
COLORS = [(255, 255, 255), (255, 255, 0), (0, 255, 255), (0, 255, 0),
          (255, 0, 255), (255, 0, 0), (0, 0, 255), (0, 0, 0)]
GRAY = [0, 36, 73, 109, 146, 182, 219, 255]


def png(path, width, height, rows, rgb=False):
    """Write deterministic lossless PNG using built-in zlib and CRC32."""
    color_type, channels = (2, 3) if rgb else (0, 1)
    assert len(rows) == height and all(len(row) == width * channels for row in rows)
    def chunk(kind, payload):
        return (struct.pack(">I", len(payload)) + kind + payload
                + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF))
    raw = b"".join(b"\x00" + bytes(row) for row in rows)
    data = (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, color_type, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    path.write_bytes(data)


class FMAudio:
    """Phase-continuous, piecewise constant frequency on a precise timeline.

    Segment boundaries round the cumulative time rather than each duration,
    so short SSTV porches do not accumulate soundcard clock rounding errors.
    """
    def __init__(self, sample_rate, phase=0.0):
        self.sample_rate = sample_rate
        self.samples = array("f")
        self.duration_ns = 0
        self.phase = phase

    def tone(self, duration_ns, frequency):
        start_ns = self.duration_ns
        end_ns = start_ns + duration_ns
        first = round(start_ns * self.sample_rate / NS)
        last = round(end_ns * self.sample_rate / NS)
        assert first == len(self.samples)
        for index in range(first, last):
            local = index / self.sample_rate - start_ns / NS
            self.samples.append(AMPLITUDE * math.sin(self.phase + TAU * frequency * local))
        self.phase = (self.phase + TAU * frequency * duration_ns / NS) % TAU
        self.duration_ns = end_ns


def vis_header(audio, code):
    audio.tone(300_000_000, 1900)
    audio.tone(10_000_000, 1200)
    audio.tone(300_000_000, 1900)
    audio.tone(30_000_000, 1200)
    bits = [(code >> bit) & 1 for bit in range(7)]
    parity = sum(bits) % 2
    for bit in bits + [parity]:
        audio.tone(30_000_000, 1100 if bit else 1300)
    audio.tone(30_000_000, 1200)
    return bits, parity


def sstv_rows():
    rows = []
    for y in range(256):
        if y < 16:
            palette = [(value, value, value) for value in GRAY]
        elif y >= 240:
            palette = list(reversed(COLORS))
        else:
            palette = COLORS
        rows.append([palette[x // 40] for x in range(320)])
    return rows


def sstv(mode, sample_rate, phase):
    assert mode in {"martin_m1", "scottie_s1"}
    code = 44 if mode == "martin_m1" else 60
    audio = FMAudio(sample_rate, phase)
    bits, parity = vis_header(audio, code)
    image_start_ns = audio.duration_ns
    scan_ns = 146_432_000 if mode == "martin_m1" else 138_240_000
    rows = sstv_rows()
    first_line_start_sync_ns = 9_000_000 if mode == "scottie_s1" else 0
    if first_line_start_sync_ns:
        audio.tone(first_line_start_sync_ns, 1200)
    def component(row, channel):
        # Eight constant colour bars, exactly equivalent to 320 pixel values.
        for bar in range(8):
            intensity = row[bar * 40][channel]
            audio.tone(scan_ns // 8, 1500.0 + 800.0 * intensity / 255.0)
    for row in rows:
        if mode == "martin_m1":
            audio.tone(4_862_000, 1200)
            audio.tone(572_000, 1500)
            component(row, 1)
            audio.tone(572_000, 1500)
            component(row, 2)
            audio.tone(572_000, 1500)
            component(row, 0)
            audio.tone(572_000, 1500)
        else:
            audio.tone(1_500_000, 1500)
            component(row, 1)
            audio.tone(1_500_000, 1500)
            component(row, 2)
            audio.tone(9_000_000, 1200)
            audio.tone(1_500_000, 1500)
            component(row, 0)
    line_seconds = ((4_862_000 + 4 * 572_000 + 3 * scan_ns) if mode == "martin_m1"
                    else (3 * 1_500_000 + 9_000_000 + 3 * scan_ns)) / NS
    return audio.samples, {
        "mode": mode, "vis_code": code, "vis_data_bits_lsb_first": bits,
        "vis_even_parity_bit": parity, "calibration_and_vis_seconds": 0.91,
        "width": 320, "height": 256, "color_scan_order": "G, B, R",
        "black_hz": 1500, "white_hz": 2300, "sync_hz": 1200,
        "intensity_to_frequency": "1500 + 800 * unsigned_rgb_byte / 255",
        "scan_seconds_per_component": scan_ns / NS,
        "pixel_seconds": scan_ns / NS / 320,
        "line_seconds": line_seconds, "image_start_seconds_relative_to_signal": image_start_ns / NS,
        "extra_initial_scottie_sync_seconds": first_line_start_sync_ns / NS,
        "image_scan_duration_seconds": (audio.duration_ns - image_start_ns) / NS,
        "pattern": "Rows0-15 grayscale bars; rows16-239 eight color bars white,yellow,cyan,green,magenta,red,blue,black; rows240-255 reverse colors",
        "color_bar_rgb": COLORS, "grayscale_bar_bytes": GRAY,
        "expected_png": "sstv_expected_320x256.png",
        "source": {"url": SSTV_SOURCE, "pages": "2-4,12 (one-based)",
                   "title": "JL Barber N7CXI: Proposal for SSTV Mode Specifications, Dayton 2000, timing derived from Robot1200C firmware"},
        "timing_note": "Exact published decimal timings are used, not rounded display durations of114/110 seconds",
    }


def alternating_fax(audio, duration_ns, alternation_hz):
    # Start/stop rates modulate the fax frequency; they are not standalone audio tones.
    cycles = round(duration_ns / NS * alternation_hz)
    half_ns = duration_ns // (2 * cycles)
    consumed = 0
    for _ in range(cycles):
        audio.tone(half_ns, 2300)
        audio.tone(half_ns, 1500)
        consumed += 2 * half_ns
    if consumed != duration_ns:
        audio.tone(duration_ns - consumed, 1500)


def fax_rows(width=1810, height=64, margin=False):
    rows = []
    white_margin = round(width * 0.05) if margin else 0
    for y in range(height):
        palette = GRAY if y < height - 8 else list(reversed(GRAY))
        row = [255] * white_margin
        for x in range(white_margin, width):
            bar = min(7, (x - white_margin) * 8 // (width - white_margin))
            row.append(palette[bar])
        rows.append(row)
    return rows


def fax(complete, sample_rate, phase):
    audio = FMAudio(sample_rate, phase)
    if complete:
        alternating_fax(audio, 5 * NS, 300)
        # Asymmetrical WMO phasing: each half-second line is white5%, black95%.
        for _ in range(60):
            audio.tone(25_000_000, 2300)
            audio.tone(475_000_000, 1500)
    picture_start = audio.duration_ns / NS
    rows = fax_rows(margin=complete)
    for row in rows:
        # Encode per-pixel durations with cumulative nanosecond endpoints.
        run_start = 0
        for x in range(1, len(row) + 1):
            if x == len(row) or row[x] != row[run_start]:
                start_ns = round(run_start * 0.5 * NS / len(row))
                end_ns = round(x * 0.5 * NS / len(row))
                audio.tone(end_ns - start_ns, 1500.0 + 800.0 * row[run_start] / 255.0)
                run_start = x
    if complete:
        alternating_fax(audio, 5 * NS, 450)
        audio.tone(10 * NS, 1500)
    return audio.samples, {
        "mode": "wefax_hf120_ioc576", "capture_type": "complete_start_phasing_image_stop" if complete else "unsynchronized_manual_start_image_only",
        "width": 1810, "height": 64, "ioc": 576, "width_convention": "round(pi * IOC)",
        "lines_per_minute": 120, "line_seconds": 0.5,
        "center_hz": 1900, "black_hz": 1500, "white_hz": 2300,
        "picture_start_seconds_relative_to_signal": picture_start,
        "picture_duration_seconds": 32,
        "start_alternation_hz": 300 if complete else None,
        "start_duration_seconds": 5 if complete else 0,
        "phasing_duration_seconds": 30 if complete else 0,
        "phasing_hz": 2 if complete else None,
        "phasing_white_fraction": 0.05 if complete else None,
        "stop_alternation_hz": 450 if complete else None,
        "stop_duration_seconds": 5 if complete else 0,
        "final_black_duration_seconds": 10 if complete else 0,
        "pattern": "Eight ascending grayscale bars; last8 rows reverse. Full capture includes a5% white dead-sector margin.",
        "grayscale_bar_bytes": GRAY, "expected_png": "wefax_complete_expected_1810x64.png" if complete else "wefax_manual_expected_1810x64.png",
        "source": {"url": FAX_SOURCE, "pages": "289-290 (one-based)",
                   "title": "WMO-No386 VolumeI2009, PartIII sections5.2 and5.3"},
        "start_stop_note": "300/450Hz are black/white alternation rates of1500/2300Hz FM fax audio",
    }


def apt_words():
    low, high = 11, 244
    sync_a = [low] * 4 + [high, high, low, low] * 7 + [low] * 7
    sync_b = [low] * 4 + [high, high, high, low, low] * 7
    assert len(sync_a) == len(sync_b) == 39
    rows, channel_a, channel_b = [], [], []
    for y in range(24):
        a_palette = GRAY if y < 16 else list(reversed(GRAY))
        b_palette = list(reversed(a_palette))
        a = [a_palette[min(7, x * 8 // 909)] for x in range(909)]
        b = [b_palette[min(7, x * 8 // 909)] for x in range(909)]
        # Exercise a minute marker followed by ordinary channel-space levels.
        a_space = b_space = high if y < 2 else low
        if y >= 4:
            a_space, b_space = low, high
        telemetry = [32 * (1 + y // 8)] * 45
        row = sync_a + [a_space] * 47 + a + telemetry + sync_b + [b_space] * 47 + b + telemetry
        assert len(row) == 2080
        rows.append(row)
        channel_a.append(a)
        channel_b.append(b)
    return rows, channel_a, channel_b, sync_a, sync_b


def apt(sample_rate, phase):
    rows, _, _, sync_a, sync_b = apt_words()
    words = [word for row in rows for word in row]
    duration = len(words) / 4160.0
    samples = array("f")
    for i in range(round(duration * sample_rate)):
        t = i / sample_rate
        index = min(len(words) - 1, int(t * 4160.0))
        # Audio following the RF FM detector: image words set the amplitude of
        # the2400Hz subcarrier. There is no RF carrier or FM RF stage here.
        samples.append(AMPLITUDE * words[index] / 255.0 * math.sin(TAU * 2400.0 * t + phase))
    return samples, {
        "mode": "noaa_apt_demodulated_audio", "subcarrier_hz": 2400,
        "audio_modulation": "AM envelope proportional to unsigned8bit image word",
        "word_rate_per_second": 4160, "words_per_line": 2080, "lines_per_second": 2,
        "lines": 24, "signal_duration_seconds": duration,
        "channels": ["A", "B"], "words_per_channel": 1040,
        "fields_per_channel": {"sync": 39, "space_and_minute_marker": 47, "image": 909, "telemetry": 45},
        "sync_a_words": sync_a, "sync_b_words": sync_b,
        "sync_a": "4 low +7 cycles of2 high,2 low +7 low;1040Hz50% duty",
        "sync_b": "4 low +7 cycles of3 high,2 low;832Hz60% duty",
        "sync_low_byte": 11, "sync_high_byte": 244,
        "space_minute_marker": "First2 rows high,next2 low; afterwards A low,B high",
        "telemetry_fixture": "8 lines each of gray32,64,96;24line partial frame, not a complete128line calibration frame",
        "pattern": "ChannelA ascending eight grayscale bars, B descending; last8 rows reverse both",
        "expected_png": "apt_expected_full_2080x24.png",
        "expected_channel_a_png": "apt_expected_channel_a_909x24.png",
        "expected_channel_b_png": "apt_expected_channel_b_909x24.png",
        "source": [{"url": APT_SOURCE, "pages": "17-22 (one-based)",
                    "title": "NOAA Technical Report NESS107: Data extraction and calibration of TIROS-N/NOAA radiometers"},
                   {"url": APT_KLM_SOURCE, "section": "4.2.3, Figure4.2.3-3",
                    "title": "NOAA KLM Users Guide, APT synchronization numerical levels"}],
        "audio_boundary": "Mathematical post-FM-demodulator AM subcarrier audio only; no RF/FM signal or hardware",
        "filtering_limit": "Ideal zero-order-held word amplitude; does not model spacecraft analog reconstruction filters",
    }


def save_wav(path, body, sample_rate, initial_silence):
    prefix = round(initial_silence * sample_rate)
    suffix = sample_rate
    pcm = array("h", [0]) * prefix
    clipped = 0
    for value in body:
        if value > 1 or value < -1:
            clipped += 1
        pcm.append(round(32767 * max(-1.0, min(1.0, value))))
    pcm.extend(array("h", [0]) * suffix)
    assert clipped == 0
    if sys.byteorder != "little":
        pcm.byteswap()
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(sample_rate)
        wav.writeframes(pcm.tobytes())
    return {
        "file": path.name, "absolute_path": str(path.resolve()),
        "sample_rate_hz": sample_rate, "wav_channels": 1, "pcm_bits": 16,
        "frames": len(pcm), "duration_seconds": len(pcm) / sample_rate,
        "initial_silence_frames": prefix, "initial_silence_seconds": prefix / sample_rate,
        "final_silence_seconds": 1.0, "clipped_sample_count": clipped,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("/tmp/radio-image-fixtures"))
    args = parser.parse_args()
    output = args.output
    output.mkdir(parents=True, exist_ok=True)
    pattern = sstv_rows()
    png(output / "sstv_expected_320x256.png", 320, 256,
        [[byte for pixel in row for byte in pixel] for row in pattern], rgb=True)
    for complete in [False, True]:
        name = "complete" if complete else "manual"
        png(output / f"wefax_{name}_expected_1810x64.png", 1810, 64, fax_rows(margin=complete))
    rows, channel_a, channel_b, _, _ = apt_words()
    png(output / "apt_expected_full_2080x24.png", 2080, 24, rows)
    png(output / "apt_expected_channel_a_909x24.png", 909, 24, channel_a)
    png(output / "apt_expected_channel_b_909x24.png", 909, 24, channel_b)
    manifest = {
        "schema_version": 1, "source_verification_date": "2026-10-12",
        "generator": str(Path(__file__).resolve()),
        "provenance": "Independent mathematics from public primary protocol documents; no project decoder code consulted",
        "no_decoder_code_used": True, "no_playback_or_hardware": True,
        "limitations": ["Synthetic laboratory fixture, not a proprietary or recorded radio transmission",
                        "No fading, adjacent-channel interference, sample-clock drift or noise in this image suite",
                        "APT spans24 lines, shorter than a full128line telemetry frame",
                        "SSTV/FAX published timings mapped to cumulative sample boundaries, avoiding persegment rounding drift"],
        "fixtures": [],
    }
    for mode in ["martin_m1", "scottie_s1"]:
        for variant, silence, phase in [("clean", 0.5, 0.0), ("offset", 0.37319, 1.23456789)]:
            body, protocol = sstv(mode, 8000, phase)
            path = output / f"sstv_{mode}_8000_mono_{variant}.wav"
            item = save_wav(path, body, 8000, silence)
            item.update({"carrier_phase_radians": phase, "variant": variant, "protocol": protocol})
            item["picture_start_seconds_absolute"] = item["initial_silence_seconds"] + protocol["image_start_seconds_relative_to_signal"]
            manifest["fixtures"].append(item)
    for complete in [False, True]:
        name = "complete" if complete else "manual"
        body, protocol = fax(complete, 8000, 0.731234)
        item = save_wav(output / f"wefax_hf120_ioc576_8000_mono_{name}.wav", body, 8000, 0.5)
        item.update({"carrier_phase_radians": 0.731234, "protocol": protocol})
        item["picture_start_seconds_absolute"] = item["initial_silence_seconds"] + protocol["picture_start_seconds_relative_to_signal"]
        manifest["fixtures"].append(item)
    for sample_rate in [16640, 48000]:
        body, protocol = apt(sample_rate, 1.973512)
        item = save_wav(output / f"noaa_apt_2400am_{sample_rate}_mono_24lines.wav", body, sample_rate, 0.37319)
        item.update({"carrier_phase_radians": 1.973512, "protocol": protocol})
        manifest["fixtures"].append(item)
    path = output / "manifest.json"
    path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({"output_directory": str(output.resolve()), "manifest": str(path.resolve()),
                      "wav_files": len(manifest["fixtures"]), "expected_png_files": 6,
                      "wav_bytes": sum((output / item["file"]).stat().st_size for item in manifest["fixtures"])}, indent=2))


if __name__ == "__main__":
    main()
