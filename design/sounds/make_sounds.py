"""Blinko notification sounds — original, synthesized from scratch.

Laptop speakers can't reproduce true sub-bass, so every sound pairs a deep fundamental
(55–110 Hz) with tuned, softly saturated harmonics: the ear reconstructs the low note
("missing fundamental"), so the bass is *felt* on a MacBook and real on headphones.
All sounds are loudness-matched, gently limited and fade cleanly (no clicks).

Run: promo/.venv/bin/python design/sounds/make_sounds.py   → Resources/Sounds/*.wav
"""
import pathlib
import numpy as np
import soundfile as sf
from scipy import signal

SR = 48000
OUT = pathlib.Path(__file__).resolve().parents[2] / "Resources" / "Sounds"
rng = np.random.default_rng(11)

def t(d): return np.arange(int(d * SR)) / SR
def env(n, a, d, curve=5.0):
    e = np.ones(n); na = max(1, int(a * SR)); e[:na] = np.sin(np.linspace(0, np.pi / 2, na)) ** 2
    rest = np.arange(n - na) / SR; e[na:] = np.exp(-rest * curve / max(d, 1e-3)); return e
def note(m): return 440 * 2 ** ((m - 69) / 12)
def lp(x, f): b, a = signal.butter(2, f / (SR / 2), "low"); return signal.lfilter(b, a, x)
def hp(x, f): b, a = signal.butter(2, f / (SR / 2), "high"); return signal.lfilter(b, a, x)

def bass(f0, d, drop=0.0, a=0.004, decay=None, drive=2.2):
    """Deep body: pitch-dropping sine + saturation harmonics so laptops 'hear' it."""
    tt = t(d); f = f0 * (1 + drop * np.exp(-tt * 30))
    x = np.sin(2 * np.pi * np.cumsum(f) / SR)
    x = np.tanh(drive * x) / np.tanh(drive)          # adds 2nd/3rd-order harmonics
    x = x + 0.35 * np.sin(2 * 2 * np.pi * np.cumsum(f) / SR) + 0.18 * np.sin(3 * 2 * np.pi * np.cumsum(f) / SR)
    return x * env(len(tt), a, decay or d * 0.5, 4.5)

def bell(m, d, bright=1.0, inharm=2.76):
    tt = t(d); f = note(m)
    x = np.sin(2 * np.pi * f * tt) + 0.5 * bright * np.sin(2 * np.pi * f * inharm * tt) * np.exp(-tt * 6)
    x += 0.25 * bright * np.sin(2 * np.pi * f * 2 * tt) * np.exp(-tt * 3)
    return x * env(len(tt), 0.003, d * 0.6, 4)

def fm(m, d, ratio=1.4, index=2.0, decay=3.0):
    tt = t(d); f = note(m)
    mod = index * np.exp(-tt * decay) * np.sin(2 * np.pi * f * ratio * tt)
    return np.sin(2 * np.pi * f * tt + mod) * env(len(tt), 0.004, d * 0.55, 4)

def noise_click(d=0.02, f=3000):
    n = rng.standard_normal(int(d * SR)); return signal.lfilter(*signal.butter(2, [f * 0.6 / (SR/2), min(f * 1.6, 20000) / (SR/2)], "band"), n) * np.exp(-np.arange(len(n)) / (SR * 0.004))

def mix(parts, length):
    out = np.zeros((int(length * SR), 2))
    for x, at, g, pan in parts:
        i = int(at * SR); x = x[: len(out) - i]
        l, r = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
        out[i:i + len(x), 0] += x * g * l * np.sqrt(2); out[i:i + len(x), 1] += x * g * r * np.sqrt(2)
    return out

def room(x, mix_=0.14, d=0.9):
    n = int(d * SR); ir = rng.standard_normal((n, 2)) * np.exp(-np.linspace(0, 8, n))[:, None]
    ir = np.stack([lp(ir[:, c], 7000) for c in range(2)], 1); ir /= np.abs(ir).sum(0) / 5
    wet = np.stack([signal.fftconvolve(x[:, c], ir[:, c])[: len(x)] for c in range(2)], 1)
    return x * (1 - mix_) + wet * mix_

def finish(x, name, target_rms=0.06):
    x = hp(x.T, 35).T                                   # remove inaudible rumble/DC
    rms = np.sqrt(np.mean(x ** 2) + 1e-12); x *= target_rms / rms   # loudness-match
    x = np.tanh(x * 1.4) / np.tanh(1.4)                 # soft limiter
    x /= max(1.0, np.abs(x).max() / 0.89)               # ≤ -1 dBFS
    fade = int(0.03 * SR); x[-fade:] *= np.linspace(1, 0, fade)[:, None]
    OUT.mkdir(parents=True, exist_ok=True)
    sf.write(OUT / f"{name}.wav", x.astype(np.float32), SR, subtype="PCM_16")
    print(f"{name:6s} {len(x)/SR:.2f}s")

# Blink — the signature: a deep 'thum' like an eyelid closing, then a glassy two-note opening.
finish(room(mix([
    (bass(73, 0.55, drop=0.6, decay=0.22), 0.0, 1.0, 0),
    (bell(88, 0.7, 0.8), 0.07, 0.42, -0.25),   # E6
    (bell(95, 0.9, 0.6), 0.16, 0.36, 0.25),    # B6
    (noise_click(0.015, 4000), 0.0, 0.12, 0),
], 1.0)), "blink")

# Pulse — two warm 808-style heartbeats.
finish(room(mix([
    (bass(55, 0.5, drop=1.2, decay=0.18, drive=3.0), 0.0, 1.0, 0),
    (bass(55, 0.55, drop=1.0, decay=0.22, drive=3.0), 0.19, 0.85, 0),
    (fm(76, 0.35, 2.0, 1.2, 8), 0.0, 0.18, 0),
], 0.85), 0.1), "pulse")

# Bloom — a major-7 chord swells over a soft sub; gentle, made for timers.
chord = sum(fm(m, 1.3, 1.0, 0.6, 2.0) * 0.32 for m in (60, 64, 67, 71))
finish(room(mix([
    (bass(65.4, 1.2, drop=0.0, a=0.05, decay=0.6, drive=1.6), 0.0, 0.9, 0),
    (chord * np.minimum(1, t(1.3) / 0.12), 0.02, 0.7, 0),
    (bell(84, 1.1, 0.4), 0.18, 0.25, 0.3),
], 1.4), 0.2), "bloom")

# Orbit — FM bell that bends up, riding a round low body.
tt = t(0.9); bend = note(81) * (1 + 0.06 * (1 - np.exp(-tt * 6)))
orbit = np.sin(2 * np.pi * np.cumsum(bend) / SR + 1.6 * np.exp(-tt * 5) * np.sin(2 * np.pi * np.cumsum(bend * 1.5) / SR)) * env(len(tt), 0.004, 0.45, 4)
finish(room(mix([
    (bass(82.4, 0.7, drop=0.3, decay=0.3), 0.0, 0.9, 0),
    (orbit, 0.03, 0.55, -0.2),
    (bell(93, 0.6, 0.5), 0.12, 0.25, 0.3),
], 1.0)), "orbit")

# Drop — a liquid droplet: fast pitch fall into a deep tail.
tt = t(0.7); f = 1400 * np.exp(-tt * 22) + 180
drop = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(len(tt), 0.002, 0.18, 5)
finish(room(mix([
    (drop, 0.0, 0.7, 0),
    (bass(61.7, 0.7, drop=0.8, decay=0.28), 0.03, 1.0, 0),
    (bell(100, 0.4, 0.3), 0.05, 0.12, 0.2),
], 0.85), 0.12), "drop")

# Halo — airy shimmer over a low hum; the softest alert.
tt = t(1.2); shimmer = sum(np.sin(2 * np.pi * note(m) * tt + k) for k, m in enumerate((91, 95, 98))) / 3
shimmer *= np.sin(np.pi * np.minimum(tt / 1.2, 1)) ** 2 * (0.6 + 0.4 * np.sin(2 * np.pi * 7 * tt))
finish(room(mix([
    (bass(98, 1.1, drop=0.0, a=0.12, decay=0.5, drive=1.3), 0.0, 0.7, 0),
    (shimmer, 0.0, 0.5, 0),
], 1.3), 0.25), "halo")

# Tap — minimal: a soft woody knock with a little low body.
tt = t(0.25); knock = np.sin(2 * np.pi * 420 * tt) * np.exp(-tt * 38)
finish(mix([
    (knock, 0.0, 0.8, 0),
    (bass(110, 0.25, drop=0.4, decay=0.08), 0.0, 0.8, 0),
    (noise_click(0.01, 2500), 0.0, 0.25, 0),
], 0.3), "tap", target_rms=0.05)
