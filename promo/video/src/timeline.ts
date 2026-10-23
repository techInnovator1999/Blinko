// Scene boundaries in frames (30 fps). Tempo 120 BPM → 1 beat = 15 frames, 1 bar = 60.
export const T = {
  cold: { from: 0, dur: 180 },        // macro on the dead notch
  reveal: { from: 180, dur: 120 },    // blink → logo → dolly out (drop @ 240)
  music: { from: 300, dur: 180 },
  hud: { from: 480, dur: 150 },
  shelf: { from: 630, dur: 180 },
  calendar: { from: 810, dur: 150 },
  montage: { from: 960, dur: 240 },   // 5 shots × 48f
  perf: { from: 1200, dur: 210 },
  end: { from: 1410, dur: 300 },
  total: 1710,
  drop: 240,
};

// Narration cue points (frames). Filled with the real Kokoro durations in Root via vo.json.
export const VO_AT = [12, 96, 200, 306, 492, 640, 822, 966, 1216, 1515];
