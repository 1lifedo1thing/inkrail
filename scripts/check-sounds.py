#!/usr/bin/env python3
"""Validate Inkrail's 36 bundled WAVs using only Python's standard library.

Checks file/header integrity, sample bounds, duration, non-silence, endings,
Existing-profile byte preservation and distinct PCM/timbre. Does not play any audio,
measure perceived sound quality, or claim validation of an audio output device.
"""

import argparse
import hashlib
from itertools import combinations
import math
from pathlib import Path
import struct
import sys
import wave

ROOT = Path(__file__).resolve().parents[1]
SAMPLES = ("key-1", "key-2", "key-3", "space", "return", "erase")
STYLES = ("classic", "soft", "crisp", "portable", "office", "electric")
# Frozen hashes from the eighteen sounds shipped before the new styles.
EXISTING_SHA256 = {
    "key-1": "9c8161dc81ca9bbab7432c057529e87735fbcb1f14a6a2a9c919ef36ebd594f7",
    "key-2": "b0e5f349bd237f96863b65af79336115cec24799651f1c11f239e22b5acf973f",
    "key-3": "1ad5a70d3ee8f12766a4fd0aa1c427de78e2e9021ff697f0886a8a88af60f3e9",
    "space": "3031a2ee7f53b5befa206dd89c70f9cdb7ec7b8bdc2c67e4c9d2abc782322d69",
    "return": "30a60dda4c6ba68b8f8dbe398b5c8c25fe8a01f061df1614cc7d5d06ec9629d2",
    "erase": "40c58b6b2d0f871db5433f4f2e9d1b4e404a3dd038a4a0ad867c85e8b8e8d505",
    "soft-key-1": "ae6adb41acd4c6ad8685a879bf5469572fed3c5325803fb1057634dc0aa3fae0",
    "soft-key-2": "4134f3901487ed3fbf5d4623e8c2141be4358ade9f618c046ef76fd58b19979b",
    "soft-key-3": "ea47aa6bc7f97fd3998cdf68794cadf9ca8a81b25f5c832374497331e1dc577e",
    "soft-space": "647829b1ab961170e6073aed0973a0337384f77a1b3e0974d419451ce02ae2c8",
    "soft-return": "eded755c2ab28c5af98dbd42e05ec5a8fb8536094ff68828a0b9346d0ee311dd",
    "soft-erase": "2badb24373444f0192ec1c2bde527aa7c4406df7383963ff299e8f9f43e919b4",
    "crisp-key-1": "ef5fc72cde98520767cf1d13c8320df81c34adfbe6e59711e773c1e9c1fcfd2c",
    "crisp-key-2": "5cba3141a1c8e5491323569d61a614626db94b1d7c4451fabc97a3e652f21cde",
    "crisp-key-3": "0db53187fcb9d4f8bbcfc1967efc6f6ff35574dfa6dfe9cbbdd7726f1df24390",
    "crisp-space": "540ad474b3169069ccfdfbbacc7549ae92206566fe59524b82c852e9cdc0a27d",
    "crisp-return": "fd354f26d7b904c30f4e03336632da3c5ab6da1654186dc2d98a0da3f5ffa7fa",
    "crisp-erase": "d9a1ae566ee400ae34a470e26ac6a6ce681896c7be03bf734300516c4a1c42b3",
}


def inspect(path):
    raw = path.read_bytes()
    assert raw[:4] == b"RIFF" and raw[8:12] == b"WAVE", "missing RIFF/WAVE header"
    assert struct.unpack("<I", raw[4:8])[0] + 8 == len(raw), "RIFF size does not match file"
    with wave.open(str(path), "rb") as audio:
        assert audio.getnchannels() == 1, "not mono"
        assert audio.getsampwidth() == 2, "not 16-bit PCM"
        assert audio.getframerate() == 44100, "sample rate is not 44.1 kHz"
        assert audio.getcomptype() == "NONE", "audio is compressed"
        count = audio.getnframes()
        pcm = audio.readframes(count)
        assert len(pcm) == count * 2, "truncated sample data"
    values = struct.unpack("<" + "h" * count, pcm)
    assert values, "empty sample"
    peak = max(abs(value) for value in values) / 32768
    energy = sum(value * value for value in values)
    rms = math.sqrt(energy / count) / 32768
    roughness = math.sqrt(sum((b - a) ** 2 for a, b in zip(values, values[1:])) / energy)
    assert 0.08 < peak < 0.90, f"silent or clipped peak: {peak:.3f}"
    assert rms > 0.006, f"sample is nearly silent: RMS {rms:.4f}"
    assert abs(sum(values) / count) / 32768 < 0.02, "large DC offset"
    return {"duration": count / 44100, "peak": peak, "rms": rms,
            "roughness": roughness, "first": values[0], "last": values[-1],
            "values": values, "energy": energy,
            "pcm_hash": hashlib.sha256(pcm).hexdigest(),
            "file_hash": hashlib.sha256(raw).hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--resources", type=Path, default=ROOT / "Sources/Inkrail/Resources")
    args = parser.parse_args()
    failures = []
    metrics = {}
    expected_names = {f"{name if style == 'classic' else f'{style}-{name}'}.wav"
                      for style in STYLES for name in SAMPLES}
    actual_names = {path.name for path in args.resources.glob("*.wav")}
    if actual_names != expected_names:
        failures.append(f"unexpected WAV set: missing {sorted(expected_names - actual_names)}, "
                        f"extra {sorted(actual_names - expected_names)}")
    for style in STYLES:
        for name in SAMPLES:
            resource = name if style == "classic" else f"{style}-{name}"
            try:
                result = inspect(args.resources / f"{resource}.wav")
                lower, upper = (0.25, 0.50) if name == "return" else (0.045, 0.18)
                assert lower <= result["duration"] <= upper, "unexpected sample duration"
                if resource in EXISTING_SHA256:
                    assert result["file_hash"] == EXISTING_SHA256[resource], "existing WAV changed"
                if style != "classic":
                    assert abs(result["first"]) <= 2 and abs(result["last"]) <= 2, "nonzero attack/release endpoint"
                metrics[(style, name)] = result
                print(f"PASS {resource:14} {result['duration']:.3f}s  peak={result['peak']:.3f}  RMS={result['rms']:.3f}")
            except (OSError, wave.Error, AssertionError, ZeroDivisionError, struct.error) as error:
                failures.append(f"{resource}: {error}")
    expected_count = len(STYLES) * len(SAMPLES)
    if len(metrics) == expected_count:
        if len({result["pcm_hash"] for result in metrics.values()}) != expected_count:
            failures.append("two sound resources contain identical PCM")
        for name in SAMPLES:
            soft, crisp = metrics[("soft", name)], metrics[("crisp", name)]
            if crisp["roughness"] <= soft["roughness"] * 3:
                failures.append(f"{name}: Crisp lacks the expected high-frequency distinction from Soft")
            if crisp["peak"] <= soft["peak"] * 1.5:
                failures.append(f"{name}: Soft/Crisp peak levels are insufficiently distinct")
            portable, office, electric = (metrics[(style, name)] for style in ("portable", "office", "electric"))
            if portable["roughness"] <= office["roughness"] * 1.5:
                failures.append(f"{name}: Portable lacks the expected brighter contact than Office")
            if electric["roughness"] <= office["roughness"] * 1.5:
                failures.append(f"{name}: Electric lacks the expected sharper contact than Office")
            if not electric["duration"] < portable["duration"] < office["duration"]:
                failures.append(f"{name}: expected short Electric, intermediate Portable and longer Office tails")
            # Distinct bytes alone would allow a copy with its volume changed.
            # Reject near-identical waveform shapes across every pair of styles.
            for first_style, second_style in combinations(STYLES, 2):
                first, second = metrics[(first_style, name)], metrics[(second_style, name)]
                correlation = abs(sum(a * b for a, b in zip(first["values"], second["values"])))
                correlation /= math.sqrt(first["energy"] * second["energy"])
                if correlation > 0.96:
                    failures.append(f"{name}: {first_style}/{second_style} appear to be gain-adjusted copies")
        if not failures:
            print(f"PASS distinct PCM for all {expected_count} WAVs; no gain-adjusted copies across styles.")
            print("PASS Soft/Crisp contrast and brighter, shorter Portable/Electric contacts than Office.")
    if failures:
        for message in failures:
            print(f"FAIL {message}", file=sys.stderr)
        return 1
    print(f"Validated all {expected_count} WAVs; all 18 existing WAV bytes preserved. No audio playback or subjective listening test performed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
