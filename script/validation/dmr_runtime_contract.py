#!/usr/bin/env python3
"""Offline contract probe for the pinned official DSD-neo 2.10.0 binary.

No network, devices, playback or installation. Supply the independently obtained
SDRTrunk issue #1803 WAV; it is IQ (50 kHz stereo), despite its historical name.
External audio and generated audio remain in --work-dir, never in the report.
Requires numpy. The report stores hashes, metrics and selected protocol lines.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import threading
import time
import wave

import numpy as np


def sha(data):
    return hashlib.sha256(data).hexdigest()


ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")


def protocol(stderr):
    text = ANSI.sub("", stderr.decode(errors="replace"))
    return {
        "color_codes": sorted(set(re.findall(r"Color Code=(\d+|XX)", text))),
        "calls": sorted(set(re.findall(r"SLOT ([12?]) TGT=(\d+) SRC=(\d+) (Private|Group) Call", text))),
        "sync_losses": text.count("Sync: no sync"),
        "flco_fec_errors": text.count("FLCO FEC ERR"),
        "shutdown_seen": "Exiting." in text,
    }


def audio_metrics(data, floating=False):
    width = 4 if floating else 2
    valid = len(data) // (width * 2) * width * 2
    a = np.frombuffer(data[:valid], dtype="<f4" if floating else "<i2").astype(np.float64).reshape(-1, 2)
    return {
        "bytes": len(data), "sha256": sha(data), "frames_stereo": len(a),
        "whole_stereo_frames": valid == len(data),
        "nonzero_samples": [int(np.count_nonzero(a[:, k])) for k in (0, 1)],
        "rms": [float(np.sqrt(np.mean(a[:, k] ** 2))) if len(a) else 0 for k in (0, 1)],
        "channels_equal": bool(np.array_equal(a[:, 0], a[:, 1])),
        "finite": bool(np.isfinite(a).all()),
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--binary", required=True, type=Path)
    ap.add_argument("--iq-wav", required=True, type=Path)
    ap.add_argument("--work-dir", required=True, type=Path)
    ap.add_argument("--report", required=True, type=Path)
    args = ap.parse_args()
    args.work_dir.mkdir(parents=True, exist_ok=True)
    assert sha(args.binary.read_bytes()) == "dff6a26e4fb1bd6bc67dc408b4e06352ca875376135681aa2d17bda02c26efe7", "Unexpected runtime; this probe's contract is pinned to the official 2.10.0 arm64 asset."
    raw_source = args.iq_wav.read_bytes()
    assert sha(raw_source) == "5cc14eb12ce0d2fb452582484f415dc873b8b6c5df8d7a3186bcdd183986e675", "Unexpected corpus; do not apply another recording's oracle."
    with wave.open(str(args.iq_wav)) as w:
        input_format = dict(rate=w.getframerate(), channels=w.getnchannels(), width=w.getsampwidth(), frames=w.getnframes())
        assert input_format["rate"] == 50000 and input_format["channels"] == 2 and input_format["width"] == 2
        iq = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float32).reshape(-1, 2)
    z = iq[:, 0] + 1j * iq[:, 1]
    x = np.angle(z[1:] * np.conj(z[:-1]))
    n = np.arange(-64, 65)
    h = 2 * 6000 / 50000 * np.sinc(2 * 6000 / 50000 * n) * np.hanning(len(n))
    h /= h.sum()
    x = np.convolve(x, h, "same")
    x = np.interp(np.arange(int(len(x) * 48000 / 50000)) * 50000 / 48000, np.arange(len(x)), x)
    pcm = (np.clip(x / np.pi * .75, -1, 1) * 32767).astype("<i2").tobytes()
    discriminator = args.work_dir / "discriminator.wav"
    with wave.open(str(discriminator), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(48000); w.writeframes(pcm)
    env = {**os.environ, "DSD_NEO_NO_BOOTSTRAP": "1"}
    env.pop("DSD_NEO_CONFIG", None)
    common = [str(args.binary.resolve()), "--frontend", "none"]
    cases = []
    for name, mode, voice, preference, floating in [
        ("both-auto", "-fs", 3, 2, False),
        ("slot1", "-fs", 1, 2, False),
        ("slot2", "-fs", 2, 2, False),
        ("voice-off", "-fs", 0, 2, False),
        ("prefer1", "-fs", 3, 0, False),
        ("prefer2", "-fs", 3, 1, False),
        ("single-slot-decoder", "-fr", 3, 2, False),
        ("float-output", "-fs", 3, 2, True),
    ]:
        wav_path = args.work_dir / (name + ".wav")
        event_path = args.work_dir / (name + ".events")
        event_path.write_text("")
        flags = [mode, "-i", str(discriminator), "-o", "-", "-V", str(voice), "-z", str(preference), "-w", str(wav_path), "-J", str(event_path)]
        if floating:
            flags += ["-y"]
        start = time.monotonic()
        r = subprocess.run(common + flags, capture_output=True, timeout=20, cwd=args.work_dir, env=env)
        (args.work_dir / (name + ".stderr")).write_bytes(r.stderr)
        (args.work_dir / (name + ".pcm")).write_bytes(r.stdout)
        with wave.open(str(wav_path)) as w:
            info = dict(rate=w.getframerate(), channels=w.getnchannels(), width=w.getsampwidth(), frames=w.getnframes())
            wav_pcm = w.readframes(w.getnframes())
        cases.append(dict(name=name, mode=mode, voice=voice, preference=preference, floating=floating,
            exit=r.returncode, elapsed_seconds=round(time.monotonic() - start, 4),
            stdout=audio_metrics(r.stdout, floating), wav=info, stdout_equals_wav_pcm=r.stdout == wav_pcm,
            protocol=protocol(r.stderr), event_log=event_path.read_text(errors="replace") if event_path.exists() else ""))

    # Feed a regular PCM stream, keep stdin open after data and drain both pipes.
    # This verifies publication while running, distinct from output after EOF.
    def stream(cancel=False, silence=False, close_before_cancel=False):
        p = subprocess.Popen(common + ["-fs", "-i", "-", "-s", "48000", "-o", "-", "-V", "3", "-z", "2"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=args.work_dir, env=env)
        collected = {"stdout": bytearray(), "stderr": bytearray()}
        first = {}
        start = time.monotonic()
        def reader(name, pipe):
            while True:
                chunk = os.read(pipe.fileno(), 16384)
                if not chunk:
                    break
                first.setdefault(name, time.monotonic() - start)
                collected[name].extend(chunk)
        threads = [threading.Thread(target=reader, args=(name, getattr(p, name)), daemon=True) for name in collected]
        for t in threads: t.start()
        payload = bytes(48000 * 2 * 2) if silence else pcm
        # Deliberate odd-byte boundaries prove the s16 stream need not arrive aligned.
        for offset in range(0, len(payload), 8191):
            p.stdin.write(payload[offset:offset + 8191]); p.stdin.flush()
        time.sleep(.2)
        before = {k: len(v) for k, v in collected.items()}
        alive = p.poll() is None
        end_start = time.monotonic()
        if cancel:
            if close_before_cancel:
                p.stdin.close()
            try:
                p.send_signal(signal.SIGTERM)
            except ProcessLookupError:
                pass
        else:
            p.stdin.close()
        killed = False
        try:
            p.wait(timeout=3)
        except subprocess.TimeoutExpired:
            killed = True; p.kill(); p.wait(timeout=2)
        for t in threads: t.join(timeout=2)
        if not p.stdin.closed: p.stdin.close()
        return dict(cancel=cancel, silence=silence, close_before_cancel=close_before_cancel, was_alive_before_end=alive,
            bytes_before_end=before, first_read_seconds=first, exit=p.returncode,
            shutdown_seconds=round(time.monotonic() - end_start, 4), required_sigkill=killed,
            stdout=audio_metrics(bytes(collected["stdout"])), protocol=protocol(bytes(collected["stderr"])))

    result = dict(schema=1, tested_utc=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        runtime=dict(version="2.10.0", executable_sha256=sha(args.binary.read_bytes()), release_commit="ff5843f"),
        corpus=dict(url="https://adryd.co/public/20240122_141253_446800000_BrandMeister_UP_24_baseband.wav",
            source="https://github.com/DSheirer/sdrtrunk/issues/1803",
            bytes=len(raw_source), sha256=sha(raw_source), format=input_format,
            license="No redistribution license stated; original and derived audio not committed or bundled.",
            independent_oracle=dict(slot=1, target=9990, source=3025209, call="Private", color_code=None,
                evidence="lwvmobile's public DSD-FME decode in SDRTrunk issue #1803 (2024-01-24). Color code 07 is observed here, not part of that independent oracle.")),
        conversion=dict(description="IQ phase difference; 129-tap Hann-windowed sinc lowpass at6kHz; linear resample50k→48k; scaling .75/pi→s16LE.",
            discriminator_wav_sha256=sha(discriminator.read_bytes()), raw_pcm_sha256=sha(pcm)),
        cases=cases, streams=[stream(), stream(cancel=True), stream(cancel=True, close_before_cancel=True), stream(silence=True)],
        limits=["Single-slot MS/DM sample does not validate simultaneous independent TS1 and TS2 calls.",
            "Nonzero decoded PCM and framing are verified; speech quality is not independently scored.",
            "No microphone, hardware, remote TCP or on-air reception.",
            "Runtime measurements are ordinary subprocess evidence; no new REA Evidence ID is claimed."])
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({"cases": len(cases), "streams": len(result["streams"]), "all_exit_zero": all(c["exit"] == 0 for c in cases), "report": str(args.report)}))


if __name__ == "__main__":
    main()
