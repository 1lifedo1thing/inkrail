#!/usr/bin/env python3
"""Assemble Inkrail's six offline typewriter sound banks.

Recorded edits are masters in Sources/Inkrail/Resources. Copy those verbatim
and render the remaining mechanical actions from their individual scores.
"""
import argparse
import math
from pathlib import Path
import random
import shutil
import struct
import wave

RATE = 44100
ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Sources/Inkrail/Resources"
SAMPLES = ("key-1", "key-2", "key-3", "space", "erase", "return", "bell")

# Impact responses. First the contact noise (bandwidth in Hz, decay in ms),
# then the modes it excites in the object (Hz, relative strength, decay in ms).
# The short, inharmonic frame modes die out in the first few oscillations.
SURFACES = {
    "keycap": (3400, 1.5, [(680, .22, 2.9), (1870, .16, 1.8)]),
    "platen": (2100, 3.6, [(205, .45, 6), (585, .28, 4), (1060, .15, 2.8)]),
    "basket": (4700, 2.6, [(380, .34, 5.4), (925, .29, 4.4), (2150, .23, 3.1)]),
    "pawl": (6100, 1.15, [(1480, .24, 2.0), (2640, .18, 1.6)]),
    "spring": (5000, 1.45, [(730, .24, 3.1), (2310, .24, 3.3), (3860, .10, 1.8)]),
    "cast": (1350, 4, [(142, .36, 7.2), (330, .31, 6.3), (564, .29, 4.8)]),
    "wood": (1460, 3.2, [(245, .37, 5.7), (530, .32, 4.6), (925, .13, 2.9)]),
    "felt": (810, 4.5, [(220, .28, 4.2), (430, .23, 4.6)]),
    "rubber": (600, 3.8, [(130, .39, 7.9), (275, .31, 6.5)]),
    "shell": (4650, 2.2, [(560, .33, 3.4), (1120, .30, 3.8), (2950, .21, 2.1)]),
    "cam": (2850, 1.8, [(340, .29, 3.9), (1060, .31, 2.9)]),
}


class Take:
    def __init__(self, duration_ms, seed):
        self.frames = [0.] * round(duration_ms * RATE / 1000)
        self.rng = random.Random(seed)

    def hit(self, at, surface, gain):
        """Contact and elastic response of a struck part, in milliseconds."""
        start = round(at * RATE / 1000)
        cutoff, decay_ms, modes = SURFACES[surface]
        count = min(len(self.frames) - start, round(decay_ms * .007 * RATE))
        alpha = -math.expm1(-math.tau * cutoff / RATE)
        decay = math.exp(-1000 / (decay_ms * RATE))
        amplitude, low, body = 1., 0., 0.
        for i in range(count):
            low += alpha * (self.rng.uniform(-1, 1) - low)
            body += .012 * (low - body)
            self.frames[start + i] += gain * min(1, i / 5) * amplitude * (low - body)
            amplitude *= decay
        for hz, strength, tail in modes:
            # Variation among individual bars, clearances and contact points.
            self.mode(at, hz * self.rng.uniform(.956, 1.045),
                      gain * strength * self.rng.uniform(.85, 1.15), tail, .32)

    def hits(self, *contacts):
        for at, surface, gain in contacts:
            self.hit(at, surface, gain)

    def mode(self, at, hz, gain, decay_ms, attack_ms):
        start = round(at * RATE / 1000)
        count = min(len(self.frames) - start, round(7 * decay_ms * RATE / 1000))
        amplitude = gain
        decay = math.exp(-1000 / (RATE * decay_ms))
        attack = attack_ms * RATE / 1000
        angle = math.tau * hz / RATE
        for i in range(count):
            self.frames[start + i] += amplitude * min(1, i / attack) * math.sin(angle * i)
            amplitude *= decay

    def slide(self, at, duration, gain, band, end_band, grain=0.):
        """Unpitched friction, with optional pressure ripples in a moving rail."""
        start = round(at * RATE / 1000)
        count = round(duration * RATE / 1000)
        low = body = grain_noise = 0.
        for i in range(count):
            p = i / count
            cutoff = band + (end_band - band) * p
            low += -math.expm1(-math.tau * cutoff / RATE) * (self.rng.uniform(-1, 1) - low)
            body += .018 * (low - body)
            grain_noise += .0009 * (self.rng.uniform(-1, 1) - grain_noise)
            envelope = min(1, i / (.11 * count), (count - i - 1) / (.09 * count))
            pressure = 1 + grain * min(1, max(-1, 38 * grain_noise))
            self.frames[start + i] += gain * pressure * envelope * (low - .65 * body)

    def teeth(self, times, gain):
        for at in times:
            self.hit(at, "pawl", gain * self.rng.uniform(.70, 1.14))

    def motor(self, at, duration, gain, cruise_hz):
        """Brief electric drive under load, with brush noise and commutator pulses."""
        start = round(at * RATE / 1000)
        count = round(duration * RATE / 1000)
        phase = brush = vibration = 0.
        for i in range(count):
            p = i / count
            speed = .68 + .32 * min(1, p * 8, (1 - p) * 5)
            phase += speed * cruise_hz / RATE
            brush += .17 * (self.rng.uniform(-1, 1) - brush)
            vibration += .037 * (self.rng.uniform(-1, 1) - vibration)
            commutator = (1 - ((phase * 5) % 1)) ** 3
            envelope = min(1, p * 15, (1 - p) * 12)
            self.frames[start + i] += gain * envelope * (
                brush * (.45 + 2.2 * commutator) + .70 * vibration +
                .085 * math.sin(math.tau * phase) + .07 * (commutator - .25))

    def bell(self, at, modes, attack=.70):
        for hz, gain, decay_ms in modes:
            self.mode(at, hz, gain, decay_ms, attack)


def classic(take, action):
    # The reversing pawl catches the heavier manual carriage.
    take.hits((0, "keycap", .43), (8, "pawl", .88),
              (16, "basket", .67), (35, "pawl", .29))


def soft(take, action):
    if action == "space":
        take.hit(0, "felt", .77)
        take.slide(3, 27, .23, 980, 430)
        take.hits((17, "rubber", .95), (53, "wood", .24))
    elif action == "erase":
        take.hit(0, "felt", .67)
        take.slide(4, 23, .40, 750, 1950)
        take.hits((27, "wood", .86), (48, "felt", .28))
    else:
        # The cushion absorbs the end of the stroke after the rail glides shut.
        take.hit(0, "wood", .52)
        take.slide(7, 239, .49, 670, 2050, .30)
        take.slide(137, 104, .26, 1900, 380, .32)
        take.hits((247, "rubber", 1.25), (254, "felt", .85), (279, "wood", .25))


def royal(take, action):
    # The broad space lever bottoms out in the frame, the dog releases, then
    # the keylever returns more slowly. Backspace engages the reversing pawl.
    if action == "space":
        take.hits((0, "wood", .93), (12, "cast", 1.17), (32, "pawl", .56),
                  (61, "wood", .54), (68, "cast", .38))
    else:
        take.hits((0, "cast", .65), (19, "basket", .89), (28, "platen", 1.0),
                  (53, "pawl", .47), (65, "cast", .34))


def vintage(take, action):
    if action == "space":
        take.hit(0, "wood", .76)
        take.teeth([9, 22, 31], .67)
        take.slide(32, 19, .27, 2700, 690)
        take.hits((51, "spring", .48), (73, "wood", .29))
    elif action == "erase":
        take.hit(0, "spring", .45)
        take.slide(1, 20, .45, 1020, 3300, .8)
        take.teeth([10, 18, 29, 47], .73)
        take.hits((50, "wood", .87), (77, "spring", .33))
    else:
        # The loose striker excites two closely spaced bell modes.
        take.hits((0, "spring", .29), (6, "pawl", .18))
        take.bell(7, [(1770, .54, 117), (1802, .42, 138), (3900, .35, 74),
                      (5540, .17, 51), (7200, .12, 24)])


def portable(take, action):
    # Short travel, a thin shell and a fast escapement reset.
    if action == "space":
        take.hits((0, "keycap", .70), (2, "shell", 1.06), (21, "spring", .51))
    else:
        take.hits((0, "pawl", .96), (6, "shell", .70), (17, "keycap", .56))


def electric(take, action):
    if action == "space":
        take.hit(0, "keycap", .55)
        take.motor(3, 41, .78, 156)
        take.hits((7, "cam", .48), (30, "pawl", .77), (43, "rubber", .37))
    elif action == "erase":
        take.hit(0, "cam", .54)
        take.motor(4, 61, .94, 105)
        take.hits((20, "pawl", .56), (41, "cam", .87), (62, "rubber", .39))
    elif action == "return":
        take.hit(0, "cam", .64)
        take.motor(4, 273, .60, 118)
        take.slide(24, 234, .17, 850, 1980)
        take.hits((266, "platen", 1.38), (269, "cam", .89), (286, "rubber", .47))
    else:
        take.hit(0, "cam", .35)
        take.bell(3, [(2340, .74, 91), (2358, .10, 63), (4030, .24, 42),
                      (7060, .13, 20)], attack=.4)


# Each entry lists only the synthesized actions (duration in ms, peak gain).
# Every other action is an edited field recording of that particular machine.
MODELED = {
    "classic": (classic, 4816, {"erase": (89, .66)}),
    "soft": (soft, 81173, {"space": (106, .16), "erase": (91, .18), "return": (322, .27)}),
    "royal": (royal, 97321, {"space": (139, .68), "erase": (129, .63)}),
    "vintage": (vintage, 29411, {"space": (132, .55), "erase": (137, .52), "bell": (625, .43)}),
    "portable": (portable, 53017, {"space": (69, .33), "erase": (59, .31)}),
    "electric": (electric, 61283, {"space": (77, .47), "erase": (92, .51),
                                   "return": (344, .68), "bell": (445, .41)}),
}


def write_wave(path, frames, peak):
    gain = peak * 32767 / max(map(abs, frames))
    release = round(.006 * RATE)
    pcm = [round(value * gain * min(1, (len(frames) - i - 1) / release))
           for i, value in enumerate(frames)]
    with wave.open(str(path), "wb") as output:
        output.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        output.writeframes(struct.pack(f"<{len(pcm)}h", *pcm))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=RESOURCES)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    for style, (perform, seed, score) in MODELED.items():
        for index, sample in enumerate(SAMPLES):
            stem = sample if style == "classic" else f"{style}-{sample}"
            path = args.output / f"{stem}.wav"
            if sample in score:
                duration, peak = score[sample]
                take = Take(duration, seed + index * 991)
                perform(take, sample)
                write_wave(path, take.frames, peak)
            else:
                master = RESOURCES / path.name
                if not master.is_file():
                    raise FileNotFoundError(f"Missing bundled recording master: {master}")
                if path.resolve() != master.resolve():
                    shutil.copyfile(master, path)
    print(f"Assembled {len(MODELED) * len(SAMPLES)} WAVs in {args.output}.")


if __name__ == "__main__":
    main()
