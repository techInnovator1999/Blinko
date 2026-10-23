"""Narration for the Blinko promo, rendered locally with Kokoro (Apache-2.0).
Usage: .venv/bin/python audio/vo.py [voice] [speed]  ->  video/public/vo/NN.wav + vo.json
"""
import json, sys, pathlib
import numpy as np
import soundfile as sf
from kokoro import KPipeline

VOICE = sys.argv[1] if len(sys.argv) > 1 else "af_heart"
SPEED = float(sys.argv[2]) if len(sys.argv) > 2 else 0.94
LINES = [
    "Every day, you stare at the same black bar.",
    "And every day... it does absolutely nothing.",
    "Until now. Meet Blinko.",
    "Your music lives up here now. Artwork, controls, a scrubber that feels like butter.",
    "Volume and brightness? Finally beautiful.",
    "Toss a file into the notch. Grab it later, or AirDrop it in one move.",
    "Your next meeting, one click away.",
    "Focus sessions. Clipboard history. Live system stats. Charging. AirPods. All right where you already look.",
    "Built native, from the ground up. Your battery won't even notice.",
    "Blinko. Your notch, alive.",
]

out = pathlib.Path(__file__).resolve().parents[1] / "video" / "public" / "vo"
out.mkdir(parents=True, exist_ok=True)
pipe = KPipeline(lang_code="a" if VOICE[0] == "a" else "b")
meta = []
for i, text in enumerate(LINES, 1):
    chunks = [a for _, _, a in pipe(text, voice=VOICE, speed=SPEED)]
    audio = np.concatenate([np.asarray(c) for c in chunks]).astype(np.float32)
    # Trim leading/trailing near-silence, keep 40 ms of air.
    idx = np.where(np.abs(audio) > 0.01)[0]
    pad = int(0.04 * 24000)
    audio = audio[max(idx[0] - pad, 0): idx[-1] + pad]
    path = out / f"{i:02d}.wav"
    sf.write(path, audio, 24000)
    meta.append({"id": i, "text": text, "seconds": round(len(audio) / 24000, 3)})
    print(f"{i:02d} {meta[-1]['seconds']:5.2f}s  {text}")
(out / "vo.json").write_text(json.dumps(meta, indent=2))
