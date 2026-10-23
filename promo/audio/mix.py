"""Original score + sound design for the Blinko promo, synthesized from scratch and
mixed with the narration (music ducks under the voice). Output: video/public/audio/master.wav
Run with: python3 audio/mix.py
"""
import json, pathlib
import numpy as np
import soundfile as sf
from scipy import signal

SR = 44100
FPS = 30
DUR = 1710 / FPS
BPM = 120
BEAT = 60 / BPM
BAR = BEAT * 4
VO_AT = [12, 96, 200, 306, 492, 640, 822, 966, 1216, 1515]   # frames (keep in sync with timeline.ts)
DROP = 8.0          # "Meet Blinko"
END_HIT = 1488 / FPS  # logo blink
rng = np.random.default_rng(7)
root = pathlib.Path(__file__).resolve().parents[1]
N = int(DUR * SR)
music = np.zeros((N, 2))
sfx = np.zeros((N, 2))

def t_(sec): return np.arange(int(sec * SR)) / SR
def place(buf, x, at, gain=1.0, pan=0.0):
    i = int(at * SR)
    if i >= len(buf): return
    x = x[: len(buf) - i]
    if x.ndim == 1:
        l, r = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
        x = np.stack([x * l, x * r], 1) * np.sqrt(2)
    buf[i:i + len(x)] += x * gain
def lp(x, f, order=2): b, a = signal.butter(order, f / (SR / 2), "low"); return signal.lfilter(b, a, x, axis=0)
def hp(x, f, order=2): b, a = signal.butter(order, f / (SR / 2), "high"); return signal.lfilter(b, a, x, axis=0)
def bp(x, lo, hi): b, a = signal.butter(2, [lo / (SR / 2), hi / (SR / 2)], "band"); return signal.lfilter(b, a, x, axis=0)
def env(n, a, d, curve=4):
    e = np.ones(n); na = max(1, int(a * SR)); e[:na] = np.linspace(0, 1, na)
    tail = np.arange(n - na) / SR; e[na:] = np.exp(-tail * curve / max(d, 1e-3)); return e
def saw(f, t): return 2 * (t * f % 1) - 1
def note(m): return 440 * 2 ** ((m - 69) / 12)

# Simple stereo reverb: decaying filtered noise IR.
def reverb(x, seconds=2.4, mix=0.25):
    n = int(seconds * SR)
    ir = rng.standard_normal((n, 2)) * np.exp(-np.linspace(0, 7, n))[:, None]
    ir = lp(ir, 6000); ir /= np.abs(ir).sum(0) / 6
    wet = np.stack([signal.fftconvolve(x[:, c], ir[:, c])[: len(x)] for c in range(2)], 1)
    return x * (1 - mix) + wet * mix

# ---------- Instruments ----------
def kick(g=1.0):
    t = t_(0.5); f = 48 + 120 * np.exp(-t * 28)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-t * 7) * g + lp(rng.standard_normal(len(t)), 3000) * np.exp(-t * 90) * 0.15 * g
def clap():
    t = t_(0.35); n = rng.standard_normal(len(t))
    e = sum(np.exp(-np.clip(t - d, 0, None) * 60) * (t >= d) for d in (0, 0.011, 0.022)) + np.exp(-t * 14) * 0.6
    return bp(n, 900, 5000) * e * 0.5
def hat(open_=False):
    t = t_(0.4 if open_ else 0.08); return hp(rng.standard_normal(len(t)), 7000) * np.exp(-t * (9 if open_ else 55)) * 0.22
def sub(m, dur):
    t = t_(dur); s = np.sin(2 * np.pi * note(m) * t) + 0.25 * np.sin(4 * np.pi * note(m) * t)
    return s * env(len(t), 0.01, dur * 0.9, 1.2) * 0.5
def pluck(m, dur=0.25, cutoff=3200):
    t = t_(dur + 0.3); x = sum(saw(note(m) * d, t) for d in (1, 1.004, 0.996)) / 3
    x = lp(x, cutoff) * env(len(t), 0.003, 0.18, 5) * 0.18; return x
def pad(chord, dur, bright=1400):
    t = t_(dur); x = np.zeros((len(t), 2))
    for m in chord:
        for k, d in enumerate((0.997, 1.0, 1.003)):
            v = saw(note(m) * d, t + rng.random()) * 0.08
            x[:, k % 2] += v; x[:, (k + 1) % 2] += v * 0.6
    x = lp(x, bright); a = min(0.6, dur / 3)
    e = np.minimum(1, np.minimum(t / a, (dur - t) / a)); return x * e[:, None]
def bell(m, dur=2.5):
    t = t_(dur); x = np.sin(2 * np.pi * note(m) * t) + 0.4 * np.sin(2 * np.pi * note(m) * 2.76 * t) * np.exp(-t * 3)
    return x * np.exp(-t * 2.2) * 0.22
def riser(dur):
    t = t_(dur); n = rng.standard_normal(len(t)); out = np.zeros(len(t)); step = 2048
    for s in range(0, len(t), step):
        f = 300 + 9000 * (s / len(t)) ** 2; seg = n[s:s + step]
        out[s:s + step] = bp(seg, f * 0.7, min(f * 1.4, 20000))
    tone = np.sin(2 * np.pi * np.cumsum(110 * 2 ** (3 * t / dur)) / SR) * 0.15
    return (out * 0.5 + tone) * (t / dur) ** 2.2
def whoosh(dur=0.7, up=True):
    t = t_(dur); n = rng.standard_normal(len(t)); out = np.zeros(len(t)); step = 1024
    for s in range(0, len(t), step):
        p = s / len(t); f = 400 + 5000 * (p if up else 1 - p)
        out[s:s + step] = bp(n[s:s + step], f * 0.6, min(f * 1.6, 20000))
    return out * np.sin(np.pi * t / dur) ** 1.5 * 0.55
def boom():
    t = t_(2.2); f = 36 + 60 * np.exp(-t * 6)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 1.6) * 1.1
def tick(f=2600, g=0.35):
    t = t_(0.05); return np.sin(2 * np.pi * f * t) * np.exp(-t * 160) * g
def pop(f=880):
    t = t_(0.25); x = np.sin(2 * np.pi * (f + 600 * np.exp(-t * 40)) * t) * np.exp(-t * 18) * 0.35
    return x + bell(96, 0.25)[: len(x)] * 0.2
def shimmer():
    out = np.zeros(int(1.6 * SR))
    for k, m in enumerate((88, 93, 95, 100)):
        b = bell(m, 1.6 - k * 0.08); out[int(k * 0.05 * SR): int(k * 0.05 * SR) + len(b)] += b * 0.7
    return out

# ---------- Score ----------
CHORDS = [(57, 60, 64, 67), (53, 57, 60, 65), (48, 55, 60, 64), (55, 59, 62, 67)]  # Am7 F C G
ROOTS = [33, 29, 36, 31]
ARP = [[69, 72, 76, 79], [65, 69, 72, 77], [67, 72, 76, 79], [67, 71, 74, 79]]

# Intro: drone + heartbeat + glass pings, riser into the drop.
place(music, pad((45, 52, 57), DROP + 0.5, 700), 0.0, 1.0)
for b in np.arange(2.0, DROP - 0.6, BEAT * 2):
    place(music, kick(0.55) * 0.6, b); place(music, kick(0.35) * 0.5, b + 0.28)
for at, m, p in ((1.2, 88, -0.4), (3.4, 91, 0.4), (5.0, 86, -0.2)):
    place(music, bell(m), at, 0.5, p)
place(sfx, riser(2.3), DROP - 2.3, 0.9)

def groove(start, end, energy):
    t = start
    while t < end - 1e-6:
        bar = int(round((t - DROP) / BAR)) % 4
        place(music, pad(CHORDS[bar], BAR + 0.4, 1600 + 1400 * energy), t, 0.55)
        for beat in range(4):
            bt = t + beat * BEAT
            if bt >= end: break
            place(music, kick(), bt, 0.85)
            place(music, sub(ROOTS[bar], BEAT * 0.95), bt, 0.9)
            if beat in (1, 3): place(music, clap(), bt, 0.8, 0.05)
            for h in (0, 0.5): place(music, hat(open_=(energy > 0.6 and h == 0.5)), bt + h * BEAT, 0.9, 0.3 if h else -0.25)
            for s in range(4):
                place(music, pluck(ARP[bar][(beat * 4 + s) % 4] + (12 if energy > 0.6 and s % 2 else 0), cutoff=2200 + 3000 * energy),
                      bt + s * BEAT / 4, 0.65, (-0.5, 0.5, -0.2, 0.2)[s])
        t += BAR

place(music, boom(), DROP, 1.0)
place(sfx, shimmer(), DROP, 0.9)
groove(DROP, 32.0, 0.35)
groove(32.0, 40.0, 0.85)
# Breakdown for the performance claim: pad + pulsing sub + clock ticks.
place(music, pad(CHORDS[0], 7.2, 900), 40.0, 0.7)
for b in np.arange(40.0, 47.0, BEAT):
    place(music, sub(33, BEAT * 0.8), b, 0.6)
    place(music, tick(3200, 0.25), b + BEAT / 2, 1.0, 0.2)
place(sfx, riser(2.4), END_HIT - 2.4, 0.8)
# Finale: hit on the logo blink, then a warm tail.
place(music, boom(), END_HIT, 1.1)
place(sfx, shimmer(), END_HIT, 1.0)
place(music, pad((45, 52, 57, 64, 71), DUR - END_HIT, 1200), END_HIT, 0.9)
for k, m in enumerate((81, 88, 84, 91)):
    place(music, bell(m, 3.0), END_HIT + 0.5 + k * 0.75, 0.45, (-0.3, 0.3, -0.1, 0.1)[k])

# ---------- Sound design (times in seconds, synced to the picture) ----------
for at in (10.0, 16.0, 21.0, 27.0, 32.0, 33.6, 35.2, 36.8, 38.4, 40.0, 47.0):
    place(sfx, whoosh(0.6, up=True), at - 0.3, 0.55, rng.uniform(-0.4, 0.4))
place(sfx, whoosh(1.1, up=False), 8.35, 0.5)          # dolly-out after the blink
for at in (12.2,):                                    # island expands to player
    place(sfx, pop(700), at, 0.6)
for at in (16.9, 17.35, 17.8):                        # key presses
    place(sfx, tick(1800, 0.5), at, 0.9); place(sfx, lp(rng.standard_normal(2000), 1500) * np.exp(-np.arange(2000) / 300) * 0.2, at)
place(sfx, whoosh(0.35, up=False), 18.15, 0.4)        # grey HUD dismissed
place(sfx, pop(980), 18.55, 0.55)                     # island HUD
place(sfx, pop(620), 23.55, 0.7)                      # file lands in the notch
place(sfx, whoosh(0.9, up=True), 25.3, 0.45)          # AirDrop
for k in range(3): place(sfx, bell(96 + k * 3, 0.6), 25.5 + k * 0.12, 0.25)
place(sfx, tick(2200, 0.5), 29.6, 1.0)                # Join click
for at in (32.0, 33.6, 35.2, 36.8, 38.4):
    place(sfx, pop(800 + 60 * ((at * 10) % 5)), at + 0.25, 0.35)

music = reverb(music, 2.2, 0.18)
sfx = reverb(sfx, 1.6, 0.2)

# ---------- Narration + ducking ----------
vo = np.zeros((N, 2))
for i, f in enumerate(VO_AT, 1):
    a, sr = sf.read(root / "video/public/vo" / f"{i:02d}.wav")
    a = signal.resample_poly(a, SR, sr)
    place(vo, a, f / FPS, 1.0)
level = np.abs(vo[:, 0])
k = int(0.12 * SR)
smooth = signal.filtfilt(np.ones(k) / k, [1], level)
duck = 1 - 0.55 * np.clip(smooth / 0.03, 0, 1)            # ≈ -7 dB under speech
vo = hp(vo, 80) * 1.25
mix = music * 0.42 * duck[:, None] + sfx * 0.5 + vo
fade = np.ones(N); fn = int(2.5 * SR); fade[-fn:] = np.linspace(1, 0, fn) ** 1.5
mix *= fade[:, None]
mix = np.tanh(mix * 1.1) / np.tanh(1.1)                 # gentle soft-clip limiter
mix /= np.abs(mix).max() / 0.89
out = root / "video/public/audio"; out.mkdir(parents=True, exist_ok=True)
sf.write(out / "master.wav", mix.astype(np.float32), SR, subtype="PCM_24")
sf.write(out / "music_only.wav", (music * 0.42 + sfx * 0.5).astype(np.float32) / max(1e-9, np.abs(music * 0.42 + sfx * 0.5).max()) * 0.89, SR, subtype="PCM_24")
print("wrote", out / "master.wav", f"{DUR:.1f}s")
