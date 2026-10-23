# Blinko promo film

60-second launch promo, built entirely in code: every screen is a dummy recreation (no real screen captures).

- `video/`: Remotion project (React). Scenes in `video/src/scenes`, the 3D MacBook / island / dummy desktop in `video/src/components`.
- `audio/vo.py`: narration, rendered locally with Kokoro neural TTS (`af_heart`).
- `audio/mix.py`: original score + sound design synthesized with numpy/scipy, mixed with the narration (music ducks under voice).

```bash
uv venv --python 3.12 .venv && uv pip install --python .venv/bin/python kokoro soundfile scipy
.venv/bin/python audio/vo.py && .venv/bin/python audio/mix.py
cd video && npm i && npx remotion render BlinkoPromo ../out/Blinko-Promo.mp4 --codec=h264 --crf=16
```
