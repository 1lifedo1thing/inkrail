#!/usr/bin/env python3
"""Validate Inkrail's 42 bundled WAVs using only Python's standard library.

Checks file/header integrity, duration, distinct PCM/timbre and the different
envelopes of the warning bell and carriage return. Does not play any audio,
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
SAMPLES = ("key-1", "key-2", "key-3", "space", "return", "erase", "bell")
STYLES = ("classic", "soft", "royal", "vintage", "portable", "electric")


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
    assert 0.08 < peak < 0.90, f"silent or clipped peak: {peak:.3f}"
    assert rms > 0.006, f"sample is nearly silent: RMS {rms:.4f}"
    assert abs(sum(values) / count) / 32768 < 0.02, "large DC offset"
    return {"duration": count / 44100, "peak": peak, "rms": rms,
            "first": values[0], "last": values[-1],
            "values": values,
            "pcm_hash": hashlib.sha256(pcm).hexdigest()}


def strongest_tone(values, low_hz, high_hz):
    """Fraction of energy in the strongest Fourier bin in the specified band."""
    size = len(values)
    peak = 0.0
    for k in range(math.ceil(low_hz * size / 44100), math.ceil(high_hz * size / 44100)):
        coefficient = 2 * math.cos(math.tau * k / size)
        previous = older = 0.0
        for value in values:
            current = value + coefficient * previous - older
            older, previous = previous, current
        peak = max(peak, previous ** 2 + older ** 2 - coefficient * previous * older)
    energy = sum(x * x for x in values)
    return 2 * peak / (size * energy) if energy else 0.0


def check_carriage(values):
    # Independent recordings put the stop at different times. Look for an
    # audible slide followed by a louder impact toward the end of travel.
    block = round(0.012 * 44100)
    power = [sum(x * x for x in values[i:i + block]) / block
             for i in range(0, len(values), block)]
    travel = power[len(power) // 5:len(power) // 2]
    stop = max(power[len(power) // 2:])
    relative_power = sum(travel) / len(travel) / stop if stop else 0
    assert 0.001 < relative_power < 0.8, "missing carriage travel or end stop"


def waveform_signature(values):
    # Compare the waveforms on the same relative time axis so simply
    # resampling a take at another playback speed cannot create a new machine.
    result = []
    for i in range(2048):
        offset = i * (len(values) - 1) / 2048
        index = int(offset)
        result.append(values[index] + (values[index + 1] - values[index]) * (offset - index))
    length = math.sqrt(sum(v * v for v in result))
    return [v / length for v in result]


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
                lower, upper = {"bell": (0.30, 1.20), "return": (0.22, 1.50)}.get(name, (0.035, 0.35))
                assert lower <= result["duration"] <= upper, "unexpected sample duration"
                assert abs(result["first"]) <= 2 and abs(result["last"]) <= 2, "nonzero attack/release endpoint"
                values = result["values"]
                if name in ("return", "bell"):
                    # Measure after the hammer contact. Some small physical
                    # bells have their strongest partial above 6 kHz.
                    ringing = strongest_tone(values[4410:4410 + 2048], 600, 9500)
                    if name == "return":
                        check_carriage(values)
                        assert ringing < 0.15, "return contains sustained bell ringing"
                    else:
                        assert ringing > 0.15, "missing sustained bell resonance"
                else:
                    assert strongest_tone(values[:2048], 100, 4500) < 0.20, "pitched tone dominates the stroke"
                result["signature"] = waveform_signature(values)
                metrics[(style, name)] = result
                print(f"PASS {resource:14} {result['duration']:.3f}s  peak={result['peak']:.3f}  RMS={result['rms']:.3f}")
            except (OSError, wave.Error, AssertionError, ZeroDivisionError, struct.error) as error:
                failures.append(f"{resource}: {error}")
    expected_count = len(STYLES) * len(SAMPLES)
    if len(metrics) == expected_count:
        if len({result["pcm_hash"] for result in metrics.values()}) != expected_count:
            failures.append("two sound resources contain identical PCM")
        for style, name in metrics:
            if style == "soft" and metrics[(style, name)]["rms"] >= metrics[("classic", name)]["rms"] * 0.70:
                failures.append(f"{name}: Soft is too loud relative to Classic")
        for first, second in combinations(metrics, 2):
            first_shape = metrics[first]["signature"]
            second_shape = metrics[second]["signature"]
            correlation = abs(sum(a * b for a, b in zip(first_shape, second_shape)))
            if correlation > 0.95:
                failures.append(f"{first} and {second} sound files duplicate a scaled or resampled take")
        if not failures:
            print(f"PASS {expected_count} distinct samples, independent waveform shapes and lower Soft levels.")
    if failures:
        for message in failures:
            print(f"FAIL {message}", file=sys.stderr)
        return 1
    print(f"Validated all {expected_count} WAVs, including a separate margin bell and carriage sweep per style.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
