#!/usr/bin/env python3
"""SSTV transmitter fixtures from the independently researched protocol catalog.

Imports no decoder code and uses no decoder output. Timings come from N7CXI's
published tables; M3/M4/S3/S4 use the documented historical family extensions.
Python standard library only. This is a mathematical transmitter, not RF data.
"""
import argparse
import json
from pathlib import Path
import re
from generate_image_fixtures import FMAudio, vis_header, png, save_wav, COLORS, GRAY

EXISTING = {"Martin M1", "Scottie S1", "PD50", "Robot36"}
FAMILIES = {"Martin", "Scottie", "PD", "Robot", "Pasokon", "WraaseSC2"}


def color_values(rgb, full=False):
    r, g, b = rgb
    if full:
        return (0.299*r + 0.587*g + 0.114*b,
                min(255, 128 + 0.5*r - 0.418688*g - 0.081312*b),
                min(255, 128 - 0.168736*r - 0.331264*g + 0.5*b))
    # N7CXI Appendix B: rounded BT.601 limited-range equations.
    return (16 + .003906*(65.738*r + 129.057*g + 25.064*b),
            128 + .003906*(112.439*r - 94.154*g - 18.285*b),
            128 + .003906*(-37.945*r - 74.494*g + 112.439*b))


def encode(record, full=False):
    w, h = record["width"], record["height"]
    rows = []
    for y in range(h):
        palette = [(v, v, v) for v in GRAY] if y < 16 else COLORS if y < h-16 else list(reversed(COLORS))
        rows.append(palette)
    audio = FMAudio(8000, .731234)
    bits, parity = vis_header(audio, record["vis_code"])
    start = audio.duration_ns
    timing = record["timing_ms"]
    family = record["family"]

    def tone(ms, hz):
        audio.tone(round(ms * 1_000_000), hz)

    def scan(values, ms):
        # Cumulative endpoints also preserve scans not divisible by eight.
        total = round(ms * 1_000_000)
        for bar in range(8):
            duration = round((bar+1)*total/8) - round(bar*total/8)
            audio.tone(duration, 1500 + 800*values[bar]/255)

    if family == "Scottie":
        tone(timing["initial_extra_sync"], 1200)
    if family == "PD":
        for y in range(0, h, 2):
            first = [color_values(c, full) for c in rows[y]]
            second = [color_values(c, full) for c in rows[y+1]]
            tone(timing["sync"], 1200); tone(timing["porch"], 1500)
            scan([c[0] for c in first], timing["scan"])
            for channel in (1, 2):
                scan([(a[channel]+b[channel])/2 for a, b in zip(first, second)], timing["scan"])
            scan([c[0] for c in second], timing["scan"])
    elif family == "Robot":
        for y in range(h):
            values = [color_values(c, full) for c in rows[y]]
            tone(timing["sync"], 1200); tone(timing["porch"], 1500)
            scan([c[0] for c in values], timing["Y"])
            if record["name"] == "Robot36":
                other = [color_values(c, full) for c in rows[y ^ 1]]
                channel = 1 if y % 2 == 0 else 2
                tone(timing["separator"], 1500 if channel == 1 else 2300)
                tone(timing["chroma_porch"], 1900)
                scan([(a[channel]+b[channel])/2 for a, b in zip(values, other)], timing["C"])
            else:
                for channel in (1, 2):
                    tone(timing["separator"], 1500 if channel == 1 else 2300)
                    tone(timing["chroma_porch"], 1900 if channel == 1 else 1500)
                    scan([c[channel] for c in values], timing["C"])
    else:
        for row in rows:
            channels = [1, 2, 0] if family in {"Martin", "Scottie"} else [0, 1, 2]
            if family != "Scottie":
                tone(timing["sync"], 1200); tone(timing["porch"], 1500)
            for index, channel in enumerate(channels):
                if family == "Scottie":
                    if index == 2: tone(timing["sync"], 1200)
                    tone(timing["porch"] if index == 2 else timing["separator"], 1500)
                scan([c[channel] for c in row], timing["scan"])
                if family == "Martin": tone(timing["separator"], 1500)
                elif family == "Pasokon": tone(timing["porch"], 1500)
    original = [[component for x in range(w) for component in row[min(7, x*8//w)]] for row in rows]
    return audio, original, {
        "mode": record["name"], "vis_code": record["vis_code"], "width": w, "height": h,
        "vis_bits_lsb_first": bits, "vis_even_parity": parity,
        "color_range": "full" if full else "bt601-limited" if family in {"PD", "Robot"} else "rgb",
        "timing_ms": timing, "image_payload_seconds": (audio.duration_ns-start)/1e9,
        "source_urls": record["source_urls"], "timing_evidence": record["evidence_status"],
        "pattern": "Eight vertical color bars, first16 grayscale rows, last16 reversed bars",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("/tmp/radio-sstv-families"))
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    catalog = json.loads((Path(__file__).resolve().parent.parent / "docs/sstv-modes.json").read_text())
    records = [r for r in catalog["modes"] if r["family"] in FAMILIES and r["identification"] == "VIS-7-even" and r.get("timing_ms") and r["name"] not in EXISTING]
    # Only the implemented/documented variants, excluding pending Robot/SC2 modes.
    records = [r for r in records if r["evidence_status"] in {"primary-protocol", "family-extension-needs-interoperability-test"}]
    full_range = [r for r in catalog["modes"] if r["name"] in {"PD50", "Robot36"}]
    manifest = {"schema_version": 1, "source_verification_date": "2026-10-13",
                "generator": "script/generate_sstv_family_fixtures.py",
                "provenance": "Independent mathematical transmitter using researched primary protocol tables, not application decoder output/code",
                "limitations": ["Synthetic PCM, no RF reception, fading, noise or clock drift", "Historical family extensions still require independent transmitter interoperability"],
                "fixtures": []}
    for record, full in [(r, False) for r in records] + [(r, True) for r in full_range]:
        audio, original, protocol = encode(record, full)
        slug = re.sub(r"[^a-z0-9]+", "_", record["name"].lower()).strip("_")
        variant = "fullrange" if full else "clean"
        name = f"sstv_{slug}_8000_mono_{variant}"
        png(args.output / (name+".png"), protocol["width"], protocol["height"], original, rgb=True)
        item = save_wav(args.output / (name+".wav"), audio.samples, 8000, .37319)
        item.update({"carrier_phase_radians": .731234, "protocol": protocol})
        manifest["fixtures"].append(item)
    (args.output / "family-image-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+"\n")
    print(json.dumps({"output": str(args.output), "fixtures": len(manifest["fixtures"]), "bytes": sum((args.output/x["file"]).stat().st_size for x in manifest["fixtures"])}, indent=2))


if __name__ == "__main__":
    main()
