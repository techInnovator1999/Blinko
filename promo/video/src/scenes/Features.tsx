import React from "react";
import { AbsoluteFill, useCurrentFrame, Img, staticFile } from "remotion";
import { MacBook } from "../components/MacBook";
import { Desktop } from "../components/Desktop";
import { Stage, cam } from "../components/Stage";
import { Panel, ShelfPanel, Agenda, FocusPanel, ClipboardPanel, StatsPanel, CompactCharging, CompactPods, FileTile, Artwork } from "../components/IslandUI";
import { Super } from "../components/Supers";
import { Cursor } from "../components/Icons";
import { lerp, sans, serif, rounded, easeOut, easeInOut, C } from "../theme";
import { LiveIsland, pop } from "./common";

/** 21–27 s: a file is dragged from a window up into the notch; Shelf; AirDrop pulse. */
export const Shelf: React.FC = () => {
  const f = useCurrentFrame(); // lands 76, airdrop 129
  const camera = cam(f, [
    { f: 0, scale: 0.95, y: -260, rx: -4, ry: 10, x: -220 },
    { f: 70, scale: 1.05, y: -270, rx: -3, ry: 6, x: -230 },
    { f: 120, scale: 2.1, y: -200, rx: 2, ry: -4, x: -60 },
    { f: 180, scale: 2.25, y: -210, rx: 3, ry: -8, x: -60 },
  ]);
  // Drag path in screen coordinates (relative to the screen's top-centre).
  const t = lerp(f, [14, 74], [0, 1], easeInOut);
  const px = (1 - t) ** 2 * -380 + 2 * (1 - t) * t * -260 + t * t * 0;
  const py = (1 - t) ** 2 * 420 + 2 * (1 - t) * t * 60 + t * t * 14;
  const near = lerp(f, [50, 70], [0, 1]);
  const open = pop(f, 76, 14, 170);
  const airdrop = lerp(f, [129, 165], [0, 1], (x) => x);
  return (
    <AbsoluteFill>
      <Stage color="#0A84FF" intensity={0.9} />
      <MacBook camera={camera} screenGlow={0.6}>
        <Desktop>
          <LiveIsland open={open} peek={near * (1 - open)} glow={0.5 + near * 0.4} glowColor="#0A84FF">
            {open > 0.02 && <Panel tab={1} reveal={lerp(f, [80, 94], [0, 1])}><ShelfPanel files={1 + (f > 100 ? 1 : 0) + (f > 112 ? 1 : 0)} airdrop={airdrop} /></Panel>}
          </LiveIsland>
          {f < 78 && (
            <div style={{ position: "absolute", left: `calc(50% + ${px}px)`, top: py, translate: "-50% -50%", rotate: `${lerp(f, [14, 74], [-8, 0])}deg`,
              scale: `${lerp(f, [60, 76], [1, 0.4])}`, opacity: lerp(f, [70, 78], [1, 0]), filter: "drop-shadow(0 18px 24px rgba(0,0,0,0.5))" }}>
              <FileTile name="Launch-Brief.pdf" color="#FF453A" size={64} />
              <div style={{ position: "absolute", left: 30, top: 40 }}><Cursor size={30} /></div>
            </div>
          )}
        </Desktop>
      </MacBook>
      <Super at={8} out={178} eyebrow="SHELF + AIRDROP" lead="Drop it. Park it. " accent="Send it." align="right" bottom={130} size={88} />
    </AbsoluteFill>
  );
};

/** 27–32 s: low hero angle; the meeting row lights up and gets clicked. */
export const Calendar: React.FC = () => {
  const f = useCurrentFrame(); // click 78
  const camera = cam(f, [
    { f: 0, scale: 2.2, y: -190, rx: 12, ry: 12, x: 60 },
    { f: 150, scale: 2.6, y: -210, rx: 8, ry: 4, x: 20 },
  ]);
  const glow = lerp(f, [30, 50], [0, 1]) * (f < 78 ? 1 : lerp(f, [78, 90], [1, 0.4]));
  const click = lerp(f, [78, 81, 88], [1, 0.82, 1]);
  const cx = lerp(f, [36, 74], [520, 302]);
  const cy = lerp(f, [36, 74], [380, 112]);
  return (
    <AbsoluteFill>
      <Stage color="#30D158" intensity={0.75} />
      <MacBook camera={camera}>
        <Desktop>
          <LiveIsland open={1} glow={0.6} glowColor="#30D158">
            <Panel tab={0} reveal={1}>
              <div style={{ display: "flex", gap: 28, height: "100%", fontFamily: sans }}>
                <div style={{ width: 210, paddingTop: 6 }}>
                  <div style={{ fontFamily: rounded, fontSize: 44, fontWeight: 600, color: "#fff", letterSpacing: -1 }}>9:58</div>
                  <div style={{ fontSize: 13, fontWeight: 600 }}><span style={{ color: "#FF6B6B" }}>Thursday</span> <span style={{ color: C.dim }}>14 Nov</span></div>
                </div>
                <div style={{ width: 1, background: "rgba(255,255,255,0.08)", margin: "6px 0" }} />
                <div style={{ flex: 1, paddingTop: 4, scale: `${click}`, transformOrigin: "85% 35%" }}>
                  <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1, color: C.green }}>STARTS IN 2 MIN</div>
                  <Agenda frame={f} joinGlow={glow} />
                </div>
              </div>
            </Panel>
          </LiveIsland>
          <div style={{ position: "absolute", left: `calc(50% + ${cx}px)`, top: cy, opacity: lerp(f, [30, 38], [0, 1]) }}><Cursor size={22} /></div>
        </Desktop>
      </MacBook>
      <Super at={8} out={148} eyebrow="CALENDAR" lead="Your next meeting, " accent="one click away." bottom={120} size={84} />
    </AbsoluteFill>
  );
};

/** 32–40 s: five whip-panned shots, one per beat-bar. */
export const Montage: React.FC = () => {
  const f = useCurrentFrame();
  const shots = [
    { color: C.orange, word: "Focus.", eyebrow: "POMODORO", el: (lf: number) => <Panel tab={4} reveal={1}><FocusPanel progress={0.32 + lf * 0.004} /></Panel>, open: 1, cam: { rx: 6, ry: -16, scale: 2.0, y: -250, x: 40 } },
    { color: C.violet, word: "Clipboard.", eyebrow: "HISTORY", el: () => <Panel tab={2} reveal={1}><ClipboardPanel /></Panel>, open: 1, cam: { rx: 12, ry: 8, scale: 2.0, y: -200, x: -40 } },
    { color: C.cyan, word: "Live stats.", eyebrow: "SYSTEM", el: (lf: number) => <Panel tab={3} reveal={1}><StatsPanel frame={lf} /></Panel>, open: 1, cam: { rx: -4, ry: 16, scale: 2.0, y: -260, x: 40 } },
    { color: C.green, word: "Charging.", eyebrow: "POWER", el: (lf: number) => <CompactCharging level={lerp(lf, [0, 40], [62, 64])} />, open: 0, wing: 92, cam: { rx: 4, ry: -8, scale: 4.4, y: -120, x: 0 } },
    { color: "#E5E5EA", word: "AirPods.", eyebrow: "BLUETOOTH", el: () => <CompactPods />, open: 0, wing: 116, cam: { rx: 6, ry: 10, scale: 4.0, y: -120, x: 0, rz: -2 } },
  ];
  const i = Math.min(4, Math.floor(f / 48));
  const lf = f - i * 48;
  const s = shots[i];
  const whipIn = lerp(lf, [0, 7], [1, 0], easeOut);
  const whipOut = lerp(lf, [42, 48], [0, 1], (x) => x * x);
  const dir = i % 2 ? -1 : 1;
  const shift = (whipIn * -1 + whipOut) * 900 * dir;
  const blur = (whipIn + whipOut) * 26;
  const camera = { ...s.cam, scale: s.cam.scale * (1 + lf * 0.0016), x: s.cam.x + shift };
  return (
    <AbsoluteFill>
      <Stage color={s.color} intensity={0.95} />
      <AbsoluteFill style={{ filter: `blur(${blur}px)` }}>
        <MacBook camera={camera}>
          <Desktop>
            <LiveIsland open={s.open} wing={s.wing ?? 0} glow={0.75} glowColor={s.color}>{s.el(lf)}</LiveIsland>
          </Desktop>
        </MacBook>
      </AbsoluteFill>
      <div key={i} style={{ position: "absolute", left: 0, right: 0, bottom: 90, textAlign: "center", color: "#fff", opacity: lerp(lf, [3, 10], [0, 1]) * lerp(lf, [40, 46], [1, 0]),
        translate: `0 ${lerp(lf, [3, 14], [24, 0], easeOut)}px` }}>
        <div style={{ fontFamily: sans, fontSize: 22, fontWeight: 700, letterSpacing: 5, opacity: 0.55, marginBottom: 10 }}>{s.eyebrow}</div>
        <div style={{ fontFamily: serif, fontStyle: "italic", fontSize: 128, lineHeight: 1, letterSpacing: -2 }}>{s.word}</div>
      </div>
    </AbsoluteFill>
  );
};

/** 40–47 s: the performance claim, typographic, on black. */
export const Perf: React.FC = () => {
  const f = useCurrentFrame();
  const num = lerp(f, [10, 70], [38, 0.2], easeOut);
  const line = (at: number) => ({ opacity: lerp(f, [at, at + 12], [0, 1]), translate: `0 ${lerp(f, [at, at + 16], [20, 0], easeOut)}px` });
  const out = lerp(f, [192, 210], [1, 0]);
  return (
    <AbsoluteFill style={{ background: "#030305", opacity: out }}>
      <AbsoluteFill style={{ background: "radial-gradient(40% 30% at 50% 0%, rgba(139,108,255,0.35), transparent 70%)" }} />
      {/* the island lives at the top edge of the frame, like the frame is the screen */}
      <div style={{ position: "absolute", left: 0, right: 0, top: 0, height: 60, scale: "2.2", transformOrigin: "50% 0%" }}>
        <LiveIsland wing={42} glow={0.6}><div style={{ position: "absolute", inset: 0 }} /></LiveIsland>
      </div>
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", flexDirection: "column", gap: 10, color: "#fff", fontFamily: sans }}>
        <div style={{ fontFamily: rounded, fontSize: 260, fontWeight: 700, letterSpacing: -10, lineHeight: 1, ...line(6) }}>
          {num < 1 ? num.toFixed(1) : Math.round(num)}<span style={{ fontSize: 140, opacity: 0.6 }}>%</span>
        </div>
        <div style={{ fontSize: 40, fontWeight: 600, color: "rgba(255,255,255,0.7)", letterSpacing: 1, ...line(20) }}>CPU at rest</div>
        <div style={{ display: "flex", gap: 54, marginTop: 64, fontSize: 52, fontWeight: 650, letterSpacing: -1 }}>
          <span style={line(78)}><span style={{ fontFamily: serif, fontStyle: "italic", fontWeight: 400 }}>Native</span> Swift.</span>
          <span style={line(98)}>No Electron.</span>
          <span style={line(118)}>Event‑driven.</span>
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

/** 47–57 s: hero crane, the notch blinks, end card. */
export const End: React.FC = () => {
  const f = useCurrentFrame(); // hit at 78
  const camera = cam(f, [
    { f: 0, scale: 0.6, y: -235, rx: 14, ry: 0 },
    { f: 78, scale: 0.7, y: -260, rx: 4, ry: 0 },
  ]);
  const toCard = lerp(f, [74, 92], [0, 1], easeInOut);
  const blink = f >= 92 && f < 104 ? Math.abs(Math.cos(((f - 92) / 12) * Math.PI)) : 1; // icon blinks once
  const iconIn = lerp(f, [84, 104], [0, 1], easeOut);
  const word = lerp(f, [100, 118], [0, 1]);
  const tag = lerp(f, [116, 134], [0, 1]);
  const cta = lerp(f, [150, 168], [0, 1]);
  return (
    <AbsoluteFill>
      <AbsoluteFill style={{ opacity: 1 - toCard }}>
        <Stage color="#8B6CFF" intensity={1} />
        <MacBook camera={camera} screenGlow={1}>
          <Desktop>
            <LiveIsland wing={42} glow={0.8}><CompactMusicStill f={f} /></LiveIsland>
          </Desktop>
        </MacBook>
      </AbsoluteFill>
      <AbsoluteFill style={{ opacity: toCard, background: "#040407" }}>
        <AbsoluteFill style={{ background: "radial-gradient(38% 42% at 50% 42%, rgba(255,79,154,0.32), rgba(139,108,255,0.12) 50%, transparent 75%)" }} />
        <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", flexDirection: "column" }}>
          <Img src={staticFile("logo.png")} style={{ width: 260, height: 260, opacity: iconIn, scale: `${0.85 + 0.15 * iconIn} ${(0.85 + 0.15 * iconIn) * blink}` }} />
          <div style={{ fontFamily: sans, fontSize: 132, fontWeight: 700, letterSpacing: -5, color: "#fff", marginTop: 6, opacity: word,
            translate: `0 ${lerp(f, [100, 120], [18, 0], easeOut)}px` }}>Blinko</div>
          <div style={{ fontFamily: sans, fontSize: 48, fontWeight: 500, color: "rgba(255,255,255,0.75)", marginTop: 4, opacity: tag }}>
            Your notch, <span style={{ fontFamily: serif, fontStyle: "italic", color: "#fff" }}>alive.</span>
          </div>
          <div style={{ marginTop: 60, display: "flex", flexDirection: "column", alignItems: "center", gap: 22, opacity: cta }}>
            <div style={{ fontFamily: sans, fontSize: 30, fontWeight: 600, color: "#000", background: "#fff", padding: "16px 34px", borderRadius: 40 }}>Free for macOS</div>
            <div style={{ display: "flex", alignItems: "center", gap: 10, fontFamily: sans, fontSize: 22, fontWeight: 600 }}>
              <span style={{ color: "rgba(255,255,255,0.5)" }}>Designed by</span>
              <Img src={staticFile("og-mark.png")} style={{ width: 26, height: 26 }} />
              <span style={{ color: "rgba(255,255,255,0.8)" }}>OptimaGeeks</span>
            </div>
          </div>
        </AbsoluteFill>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

import { CompactMusic } from "../components/IslandUI";
const CompactMusicStill: React.FC<{ f: number }> = ({ f }) => <CompactMusic frame={f} />;
export { Artwork };
