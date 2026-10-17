#!/usr/bin/env python3
"""Synthesises the pets' original sound effects (no samples, no third-party audio).

    python3 tools/make_sounds.py        # writes Pets/<pet>/sounds/*.wav

Mono 22.05 kHz 16-bit WAVs, each well under a second, so the AVAudioPlayer pool stays tiny.
"""
import math, os, random, struct, wave

RATE = 22050
random.seed(7)

def write(path, samples):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    peak = max(1e-9, max(abs(s) for s in samples))
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s / peak * 0.85)) * 32767)) for s in samples))

def env(i, n, attack=0.05, release=0.5):
    t = i / n
    if t < attack: return t / attack
    return max(0.0, 1 - (t - attack) / max(1e-9, 1 - attack)) ** (1 / max(release, 1e-3))

def lowpass(xs, k):
    out, acc = [], 0.0
    for x in xs:
        acc += (x - acc) * k
        out.append(acc)
    return out

def noise(n): return [random.uniform(-1, 1) for _ in range(n)]

def whoosh(d=0.55):
    n = int(RATE * d); x = noise(n); out, acc = [], 0.0
    for i, s in enumerate(x):
        k = 0.02 + 0.25 * math.sin(math.pi * i / n)       # filter opens then closes: a pass-by
        acc += (s - acc) * k
        out.append(acc * math.sin(math.pi * i / n))
    return out

def thud(d=0.3):
    n = int(RATE * d); out = []
    for i in range(n):
        t = i / RATE; f = 90 - 50 * i / n
        out.append(math.sin(2 * math.pi * f * t) * math.exp(-t * 14) + random.uniform(-1, 1) * math.exp(-t * 60) * 0.4)
    return out

def zap(d=0.3):
    n = int(RATE * d); out, ph = [], 0.0
    for i in range(n):
        f = 1400 * (1 - i / n) + 260; ph += f / RATE
        out.append((1 if (ph % 1) < 0.5 else -1) * env(i, n, 0.02, 0.4) * 0.6 + random.uniform(-1, 1) * 0.1 * env(i, n, 0.01, 0.2))
    return lowpass(out, 0.5)

def beam(d=1.2):
    n = int(RATE * d); out, ph = [], 0.0
    for i in range(n):
        t = i / RATE; f = 180 + 12 * math.sin(2 * math.pi * 7 * t); ph += f / RATE
        saw = 2 * (ph % 1) - 1
        out.append((saw * 0.7 + random.uniform(-1, 1) * 0.25) * env(i, n, 0.08, 0.7))
    return lowpass(out, 0.3)

def thwip(d=0.16):
    n = int(RATE * d); out = []
    for i in range(n):
        t = i / RATE
        out.append(random.uniform(-1, 1) * math.exp(-t * 35) * 0.8 + math.sin(2 * math.pi * (2400 - 9000 * t) * t) * math.exp(-t * 30) * 0.4)
    return out

def blip(d=0.28):
    n = int(RATE * d); out = []
    for i in range(n):
        t = i / RATE; f = 1250 if t < d / 2 else 1700
        local = (t % (d / 2)) / (d / 2)
        out.append(math.sin(2 * math.pi * f * t) * (1 - local) ** 2)
    return out

def swish(d=0.4):
    return [s * 0.7 for s in lowpass(whoosh(d), 0.4)]

def boom(d=0.7):
    n = int(RATE * d); x = lowpass(noise(n), 0.05); out = []
    for i, s in enumerate(x):
        t = i / RATE
        out.append(s * math.exp(-t * 5) * 3 + math.sin(2 * math.pi * 55 * t) * math.exp(-t * 6))
    return out

def chomp(d=0.22):
    n = int(RATE * d); x = lowpass(noise(n), 0.3); out = []
    for i, s in enumerate(x):
        t = i / RATE
        bite = 1.0 if t < 0.03 or 0.11 < t < 0.14 else 0.25   # two quick snaps
        out.append(s * bite * env(i, n, 0.02, 0.6) + math.sin(2 * math.pi * 90 * t) * math.exp(-t * 18) * 0.6)
    return out

def roar(d=0.8):
    n = int(RATE * d); x = lowpass(noise(n), 0.08); out = []
    for i, s in enumerate(x):
        t = i / RATE
        growl = 0.6 + 0.4 * math.sin(2 * math.pi * 23 * t)          # rough amplitude flutter
        out.append((s * 2 + math.sin(2 * math.pi * (70 + 20 * t) * t) * 0.5) * growl * env(i, n, 0.15, 0.7))
    return out

def snikt(d=0.35):
    n = int(RATE * d); out = []
    for i in range(n):
        t = i / RATE
        ring = sum(math.sin(2 * math.pi * f * t) / k for k, f in enumerate((2400, 3550, 5100), 1))
        scrape = random.uniform(-1, 1) * math.exp(-t * 40)
        out.append(ring * math.exp(-t * 9) * 0.6 + scrape)
    return out

SOUNDS = {
    "ironman": {"whoosh": whoosh, "thud": thud, "zap": zap, "beam": beam, "blip": blip, "boom": boom},
    "spiderman": {"whoosh": whoosh, "thud": thud, "thwip": thwip},
    "batman": {"swish": swish, "thud": thud, "whoosh": whoosh},
    "blackpanther": {"swish": swish, "thud": thud, "whoosh": whoosh, "zap": zap, "boom": boom},
    "captainamerica": {"swish": swish, "thud": thud, "whoosh": whoosh, "blip": blip},
    "ghostrider": {"whoosh": whoosh, "thud": thud, "zap": zap, "boom": boom, "swish": swish},
    "hela": {"swish": swish, "whoosh": whoosh, "zap": zap, "boom": boom, "beam": beam},
    "thanos": {"thud": thud, "boom": boom, "beam": beam, "zap": zap, "blip": blip},
    "venom": {"chomp": chomp, "roar": roar, "swish": swish, "thud": thud, "thwip": thwip},
    "wolverine": {"snikt": snikt, "swish": swish, "thud": thud, "whoosh": whoosh, "boom": boom},
    "flash": {"whoosh": whoosh, "zap": zap, "swish": swish, "thud": thud},
    "superman": {"whoosh": whoosh, "beam": beam, "boom": boom, "thud": thud, "swish": swish, "zap": zap},
}

if __name__ == "__main__":
    root = os.path.join(os.path.dirname(__file__), "..", "Pets")
    for pet, sounds in SOUNDS.items():
        for name, fn in sounds.items():
            write(os.path.join(root, pet, "sounds", f"{name}.wav"), fn())
            print(f"{pet}/sounds/{name}.wav")
