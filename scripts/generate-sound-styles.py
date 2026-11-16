#!/usr/bin/env python3
"""Synthesize Inkrail's original sound styles using Python's stdlib.

No recordings, downloaded assets, libraries or fonts are used. Seeds are fixed.
Classic's six existing WAVs are deliberately never opened or overwritten.
Run without arguments to refresh Soft, Crisp, Portable, Office and Electric, or pass
--output DIR to render reference files elsewhere for validation.
"""

import argparse
import math
from pathlib import Path
import random
import struct
import wave

RATE = 44100
ROOT = Path(__file__).resolve().parents[1]
SAMPLES = ("key-1", "key-2", "key-3", "space", "return", "erase")
DURATIONS = {
    "soft": (0.115, 0.119, 0.123, 0.145, 0.390, 0.105),
    "crisp": (0.070, 0.074, 0.078, 0.095, 0.310, 0.065),
    "portable": (0.092, 0.096, 0.100, 0.125, 0.410, 0.100),
    "office": (0.145, 0.151, 0.157, 0.175, 0.490, 0.135),
    "electric": (0.082, 0.086, 0.090, 0.110, 0.330, 0.085),
}


def envelope(t, attack, decay):
    return min(1.0, max(0.0, t) / attack) * math.exp(-max(0.0, t) / decay) if t >= 0 else 0.0


def tone(t, frequency):
    return math.sin(math.tau * frequency * t)


def synthesize(style, name, variant, duration):
    """Excite small synthetic bodies with filtered, deterministic noise."""
    if style in ("portable", "office", "electric"):
        return synthesize_mechanical(style, name, variant, duration)
    rng = random.Random((81173 if style == "soft" else 29411) + variant * 991)
    low = 0.0
    felt = 0.0
    result = []
    for frame in range(int(RATE * duration)):
        t = frame / RATE
        white = rng.uniform(-1.0, 1.0)
        low += 0.16 * (white - low)
        felt += 0.18 * (low - felt)
        high = white - low
        if style == "soft":
            if name.startswith("key"):
                body = 175 + variant * 18
                value = (0.33 * felt + 0.20 * tone(t, body)) * envelope(t, 0.0018, 0.026)
                value += 0.025 * tone(t, 650 + 37 * variant) * envelope(t, 0.0012, 0.012)
                value += 0.045 * tone(t - 0.025, 125) * envelope(t - 0.025, 0.0018, 0.012)
            elif name == "space":
                value = (0.24 * felt + 0.22 * tone(t, 125)) * envelope(t, 0.0022, 0.038)
                value += 0.035 * tone(t, 390) * envelope(t, 0.002, 0.016)
            elif name == "erase":
                value = (0.46 * felt + 0.15 * tone(t, 265)) * envelope(t, 0.0018, 0.023)
            else:
                # Muted bell, felt carriage sweep, then a soft lever stop.
                value = 0.035 * tone(t, 880) * envelope(t, 0.002, 0.070)
                for start in (0.035, 0.068, 0.105, 0.145, 0.190):
                    value += 0.19 * felt * envelope(t - start, 0.002, 0.012)
                value += 0.18 * tone(t - 0.245, 145) * envelope(t - 0.245, 0.0025, 0.029)
        else:
            if name.startswith("key"):
                value = 0.50 * high * envelope(t, 0.0002, 0.0065)
                value += 0.18 * tone(t, 2200 + variant * 190) * envelope(t, 0.0002, 0.010)
                value += 0.060 * tone(t, 430 + variant * 23) * envelope(t, 0.0003, 0.016)
                value += 0.20 * high * envelope(t - 0.014, 0.0002, 0.004)
            elif name == "space":
                value = 0.46 * high * envelope(t, 0.0003, 0.010)
                value += 0.13 * tone(t, 1340) * envelope(t, 0.0002, 0.014)
                value += 0.10 * tone(t - 0.018, 240) * envelope(t - 0.018, 0.0004, 0.018)
            elif name == "erase":
                value = 0.44 * high * envelope(t, 0.0002, 0.0055)
                value += 0.16 * tone(t, 3350) * envelope(t, 0.0002, 0.012)
            else:
                # Dry metal bell and ratchet, followed by a short carriage stop.
                value = (0.11 * tone(t, 2380) + 0.035 * tone(t, 3160)) * envelope(t, 0.0004, 0.048)
                for start in (0.035, 0.053, 0.074, 0.098, 0.125, 0.155):
                    value += 0.34 * high * envelope(t - start, 0.0002, 0.004)
                value += (0.24 * high + 0.12 * tone(t - 0.215, 340)) * envelope(t - 0.215, 0.0004, 0.016)
        # A short release window guarantees a zero endpoint without clipping.
        tail = min(1.0, (int(RATE * duration) - frame - 1) / (RATE * 0.006))
        result.append(value * max(0.0, tail))
    peak = max(abs(value) for value in result)
    target = 0.36 if style == "soft" else 0.74
    return [value * target / peak for value in result]


def impact(t, noise, body, decay, brightness=1.0):
    """A short contact crack followed by inharmonic housing vibration."""
    return (0.50 * noise * envelope(t, 0.0003, 0.0035)
            + 0.23 * tone(t, body) * envelope(t, 0.0005, decay)
            + 0.12 * brightness * tone(t, body * 2.71) * envelope(t, 0.0003, decay * 0.56)
            + 0.07 * brightness * tone(t, body * 5.13) * envelope(t, 0.0002, decay * 0.28))


def synthesize_mechanical(style, name, variant, duration):
    """Three different mechanisms, with their own strike, latch and return.

    These are invented mechanical voices, not recordings or emulations of a
    branded machine. Noise sources and contact timing are seeded per sample.
    Electric's cam/drive texture occurs only during a stroke or paper return;
    there is no idle loop, background hum, or runtime synthesis.
    """
    rng = random.Random({"portable": 53017, "office": 97321, "electric": 61283}[style] + variant * 991)
    low = 0.0
    body_noise = 0.0
    result = []
    frames = int(RATE * duration)
    for frame in range(frames):
        t = frame / RATE
        white = rng.uniform(-1.0, 1.0)
        low += 0.24 * (white - low)
        body_noise += 0.10 * (low - body_noise)
        high = white - low
        if style == "portable":
            # A small, light housing: bright typebar contact, a loose latch,
            # and two uneven rebound contacts rather than a single click.
            if name.startswith("key"):
                body = 510 + variant * 29
                value = impact(t, high, body, 0.014, 0.8)
                value += 0.46 * impact(t - 0.013, high, body * 1.44, 0.007)
                value += 0.28 * impact(t - 0.031, low, 310, 0.011, 0.4)
                value += 0.12 * impact(t - 0.053, high, 1120, 0.005)
            elif name == "space":
                value = impact(t, low, 290, 0.020, 0.6)
                value += 0.58 * impact(t - 0.021, high, 880, 0.009)
                value += 0.25 * impact(t - 0.046, high, 470, 0.011)
            elif name == "erase":
                value = 0.65 * impact(t, high, 760, 0.008)
                value += 0.85 * impact(t - 0.018, high, 440, 0.013)
                value += 0.24 * impact(t - 0.039, low, 310, 0.009)
            else:
                value = (0.085 * tone(t, 1950) + 0.025 * tone(t, 3217)) * envelope(t, 0.0006, 0.080)
                # Escapement teeth accelerate, then settle into the end stop.
                for index, start in enumerate((0.045, 0.077, 0.107, 0.134, 0.158, 0.180, 0.201, 0.221)):
                    value += (0.25 + index * 0.018) * impact(t - start, high, 820, 0.004)
                value += 0.72 * impact(t - 0.276, low, 260, 0.022, 0.4)
                value += 0.25 * impact(t - 0.308, high, 610, 0.009)
        elif style == "office":
            # A heavier chassis: deeper body, slower lever release and a
            # restrained metal ring. The return has a longer, lower bell.
            if name.startswith("key"):
                body = 180 + variant * 11
                value = impact(t, low * 1.8, body, 0.031, 0.65)
                value += 0.22 * high * envelope(t, 0.0004, 0.005)
                value += 0.46 * impact(t - 0.023, low, 365, 0.019, 0.6)
                value += 0.23 * impact(t - 0.057, body_noise * 2, 135, 0.024, 0.3)
            elif name == "space":
                value = impact(t, low * 1.6, 130, 0.039, 0.5)
                value += 0.46 * impact(t - 0.029, low, 310, 0.021, 0.5)
                value += 0.20 * impact(t - 0.067, body_noise * 2, 110, 0.028, 0.2)
            elif name == "erase":
                value = 0.65 * impact(t, high, 420, 0.013, 0.6)
                value += 0.85 * impact(t - 0.025, low * 1.5, 225, 0.028, 0.4)
                value += 0.24 * impact(t - 0.059, low, 160, 0.019, 0.3)
            else:
                value = (0.14 * tone(t, 1385) + 0.045 * tone(t, 2241)
                         + 0.020 * tone(t, 3598)) * envelope(t, 0.0007, 0.130)
                for start in (0.060, 0.094, 0.130, 0.169, 0.211, 0.254):
                    value += 0.32 * impact(t - start, low * 1.5, 440, 0.008, 0.5)
                value += 0.95 * impact(t - 0.322, low * 1.5, 145, 0.034, 0.4)
                value += 0.28 * impact(t - 0.370, body_noise * 2, 105, 0.025, 0.2)
        else:
            # A driven mechanism: cam engagement precedes a compact print
            # impact, followed by a short filtered mechanical release.
            if name.startswith("key"):
                body = 930 + variant * 41
                value = 0.34 * impact(t, high, 1560, 0.005, 0.6)
                value += impact(t - 0.008, high, body, 0.009, 0.5)
                value += 0.38 * impact(t - 0.026, low, 400, 0.009, 0.3)
                value += 0.12 * low * (0.6 + 0.4 * tone(t, 170)) * envelope(t - 0.010, 0.003, 0.015)
            elif name == "space":
                value = 0.52 * impact(t, high, 1280, 0.005, 0.4)
                value += 0.75 * impact(t - 0.015, low, 510, 0.013, 0.4)
                value += 0.18 * low * (0.6 + 0.4 * tone(t, 150)) * envelope(t - 0.008, 0.004, 0.024)
            elif name == "erase":
                value = impact(t, high, 1140, 0.007, 0.4)
                value += 0.68 * impact(t - 0.018, low, 670, 0.010, 0.4)
                value += 0.14 * low * envelope(t - 0.009, 0.003, 0.018)
            else:
                value = 0.5 * impact(t, high, 1150, 0.008, 0.5)
                # Short finite paper-drive sweep, with no traditional bell.
                drive = max(0.0, t - 0.018)
                drive_window = envelope(t - 0.018, 0.024, 0.070)
                value += (0.36 * low + 0.075 * tone(drive, 180 + 220 * drive)) * drive_window
                for start in (0.045, 0.070, 0.094, 0.116, 0.137, 0.157):
                    value += 0.18 * impact(t - start, high, 780, 0.004, 0.4)
                value += 0.70 * impact(t - 0.222, low, 335, 0.014, 0.5)
        # Preserve a genuine zero attack/release, even for delayed contacts.
        tail = min(1.0, (frames - frame - 1) / (RATE * 0.008))
        result.append(value * max(0.0, tail))
    peak = max(abs(value) for value in result)
    target = {"portable": 0.64, "office": 0.69, "electric": 0.60}[style]
    return [value * target / peak for value in result]


def write_wave(path, values):
    pcm = struct.pack("<" + "h" * len(values), *(round(value * 32767) for value in values))
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "Sources/Inkrail/Resources")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    for style, durations in DURATIONS.items():
        for variant, (name, duration) in enumerate(zip(SAMPLES, durations), start=1):
            write_wave(args.output / f"{style}-{name}.wav", synthesize(style, name, variant, duration))
    print(f"Generated {len(DURATIONS) * len(SAMPLES)} original WAVs in {args.output}; Classic WAVs were not modified.")


if __name__ == "__main__":
    main()
