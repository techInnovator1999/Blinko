import React from "react";
import { AbsoluteFill, useCurrentFrame, Img, staticFile } from "remotion";
import { MacBook } from "../components/MacBook";
import { Desktop } from "../components/Desktop";
import { Stage, cam } from "../components/Stage";
import { CompactMusic, Wings } from "../components/IslandUI";
import { Super } from "../components/Supers";
import { lerp, sans, serif, easeOut, easeIn } from "../theme";
import { LiveIsland, pop } from "./common";

/** 0–6 s: macro on a dead notch. A sliver of light crawls across the bezel. */
export const ColdOpen: React.FC = () => {
  const f = useCurrentFrame();
  const camera = cam(f, [{ f: 0, scale: 5.4, y: 40, rx: 6, focus: 6 }, { f: 40, scale: 5.6, y: 20, rx: 5, focus: 0 }, { f: 180, scale: 6.6, y: 0, rx: 3 }]);
  const sweep = lerp(f, [10, 170], [-30, 130]);
  const exposure = lerp(f, [0, 30], [0, 1]);
  return (
    <AbsoluteFill style={{ opacity: exposure }}>
      <Stage color="#2A2340" intensity={0.5} />
      <MacBook camera={camera}>
        <Desktop dim={0.55} windows={false}>
          {/* soft top-light so the dead notch reads as a silhouette */}
          <div style={{ position: "absolute", left: "50%", top: 0, width: 700, height: 260, marginLeft: -350,
            background: "radial-gradient(50% 60% at 50% 0%, rgba(150,130,255,0.55), transparent 70%)" }} />
          <LiveIsland />
          <div style={{ position: "absolute", inset: 0, background: `linear-gradient(100deg, transparent ${sweep - 8}%, rgba(255,255,255,0.10) ${sweep}%, transparent ${sweep + 8}%)` }} />
        </Desktop>
      </MacBook>
      <Super at={14} out={88} eyebrow="EVERY DAY" lead="You stare at the same " accent="black bar." align="center" bottom={150} size={78} />
      <Super at={98} out={176} lead="And it does " accent="absolutely nothing." align="center" bottom={150} size={78} />
    </AbsoluteFill>
  );
};

/** 6–10 s: "Until now." The notch blinks awake on the drop, then the camera rips back. */
export const Reveal: React.FC = () => {
  const f = useCurrentFrame(); // local; drop at local 60
  const wake = pop(f, 58, 11, 210);
  const camera = cam(f, [
    { f: 0, scale: 6.6, y: 0, rx: 3 },
    { f: 64, scale: 6.9, y: -5, rx: 3 },
    { f: 108, scale: 0.66, y: -250, rx: -4, ry: -16 },
    { f: 120, scale: 0.64, y: -255, rx: -5, ry: -18 },
  ]);
  const flash = lerp(f, [58, 61, 74], [0, 0.55, 0], easeOut);
  const bright = lerp(f, [58, 90], [0.86, 0.15]);
  const title = lerp(f, [84, 100], [0, 1]) ;
  return (
    <AbsoluteFill>
      <Stage color="#FF4F9A" intensity={lerp(f, [58, 100], [0.4, 1])} />
      <MacBook camera={camera} screenGlow={lerp(f, [60, 100], [0, 1])}>
        <Desktop dim={bright} windows={f > 70}>
          <div style={{ position: "absolute", left: "50%", top: 0, width: 700, height: 260, marginLeft: -350, opacity: 1 - lerp(f, [58, 80], [0, 1]),
            background: "radial-gradient(50% 60% at 50% 0%, rgba(150,130,255,0.55), transparent 70%)" }} />
          <LiveIsland wing={42 * wake} glow={wake} glowColor="#FF4F9A">
            <div style={{ opacity: lerp(f, [62, 72], [0, 1]) }}><CompactMusic frame={f} /></div>
          </LiveIsland>
        </Desktop>
      </MacBook>
      <AbsoluteFill style={{ background: "#fff", opacity: flash, mixBlendMode: "screen" }} />
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "flex-start", paddingTop: 70, opacity: title }}>
        <div style={{ display: "flex", alignItems: "center", gap: 22, translate: `0 ${lerp(f, [84, 104], [20, 0])}px` }}>
          <Img src={staticFile("logo.png")} style={{ width: 92, height: 92 }} />
          <div style={{ fontFamily: sans, fontSize: 104, fontWeight: 700, letterSpacing: -4, color: "#fff" }}>Blinko</div>
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

/** 10–16 s: orbit around the laptop; music wings, then the player blooms open. */
export const Music: React.FC = () => {
  const f = useCurrentFrame();
  const camera = cam(f, [
    { f: 0, scale: 0.64, y: -255, rx: -5, ry: -18, x: 0 },
    { f: 60, scale: 0.9, y: -230, rx: -3, ry: -6, x: 260 },
    { f: 180, scale: 2.0, y: -170, rx: 2, ry: 10, x: 330 },
  ]);
  const open = pop(f, 66, 14, 160);
  const cursorX = lerp(f, [24, 62], [380, 8]);
  const cursorY = lerp(f, [24, 62], [380, 10]);
  return (
    <AbsoluteFill>
      <Stage color="#FF4F9A" intensity={0.9} />
      <MacBook camera={camera} screenGlow={0.8}>
        <Desktop>
          <LiveIsland wing={42 * (1 - open)} open={open} glow={0.7} glowColor="#FF4F9A">
            <div style={{ opacity: 1 - open }}><CompactMusic frame={f} /></div>
            {open > 0.02 && <PlayerBloom f={f} reveal={lerp(f, [70, 84], [0, 1])} />}
          </LiveIsland>
          <div style={{ position: "absolute", left: `calc(50% + ${cursorX}px)`, top: cursorY, opacity: lerp(f, [20, 26], [0, 1]) * lerp(f, [100, 112], [1, 0]) }}>
            <CursorIcon />
          </div>
        </Desktop>
      </MacBook>
      <Super at={10} out={176} eyebrow="NOW PLAYING" lead="Music, right " accent="up here." align="right" bottom={110} size={92} />
    </AbsoluteFill>
  );
};

import { Panel, PlayerPanel, CompactVolume, Agenda } from "../components/IslandUI";
import { Cursor } from "../components/Icons";
export const CursorIcon = Cursor;
const PlayerBloom: React.FC<{ f: number; reveal: number }> = ({ f, reveal }) => (
  <Panel tab={0} reveal={reveal}><PlayerPanel frame={f} progress={0.31 + f * 0.0012} /></Panel>
);

/** 16–21 s: keycap macro → the grey square dies → the island HUD takes over. */
export const Hud: React.FC = () => {
  const f = useCurrentFrame(); // local 0..150; presses at 27, 40, 54; dismiss 65; island 75
  const press = (at: number) => lerp(f, [at, at + 3, at + 9], [0, 1, 0], easeOut);
  const level = 0.38 + 0.12 * (lerp(f, [27, 30], [0, 1]) + lerp(f, [40, 43], [0, 1]) + lerp(f, [54, 57], [0, 1]));
  const phase = f < 48 ? "keys" : "screen";
  const camera = cam(f, [
    { f: 48, scale: 1.05, y: -380, rx: 0 },
    { f: 64, scale: 1.08, y: -380, rx: 0 },
    { f: 76, scale: 3.0, y: -170, rx: 2 },
    { f: 150, scale: 3.3, y: -180, rx: 3, ry: -6 },
  ]);
  const osd = lerp(f, [48, 54], [0, 1], easeOut) * lerp(f, [64, 72], [1, 0], easeIn);
  const hud = pop(f, 74, 13, 200);
  const brightness = f > 108;
  return (
    <AbsoluteFill>
      {phase === "keys" ? <KeysMacro f={f} press={press} /> : (
        <>
          <Stage color={brightness ? "#FFD60A" : "#4FE3FF"} intensity={0.8} />
          <MacBook camera={camera}>
            <Desktop>
              <LiveIsland wing={108 * hud} glow={hud * 0.6} glowColor={brightness ? "#FFD60A" : "#4FE3FF"}>
                <div style={{ opacity: hud }}>
                  {brightness ? <BrightnessWings level={lerp(f, [110, 130], [0.45, 0.85])} /> : <CompactVolume level={level} />}
                </div>
              </LiveIsland>
              {/* the old grey square */}
              <div style={{ position: "absolute", left: "50%", top: "62%", width: 200, height: 200, marginLeft: -100, marginTop: -100,
                borderRadius: 34, background: "rgba(60,60,64,0.78)", backdropFilter: "blur(30px)", opacity: osd,
                scale: `${lerp(f, [64, 72], [1, 0.85])}`, filter: `blur(${lerp(f, [64, 72], [0, 8])}px)`,
                display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 26 }}>
                <svg width="74" height="74" viewBox="0 0 24 24"><path d="M4 9.5h3.2L12 5.5v13l-4.8-4H4z" fill="rgba(255,255,255,0.85)" /><path d="M15.5 9.2a4 4 0 0 1 0 5.6M18 7a7.2 7.2 0 0 1 0 10" stroke="rgba(255,255,255,0.85)" strokeWidth="1.8" fill="none" strokeLinecap="round" /></svg>
                <div style={{ display: "flex", gap: 3 }}>{Array.from({ length: 16 }).map((_, i) => <div key={i} style={{ width: 7, height: 7, background: i < 9 ? "rgba(255,255,255,0.85)" : "rgba(255,255,255,0.2)" }} />)}</div>
              </div>
            </Desktop>
          </MacBook>
        </>
      )}
      <Super at={6} out={46} eyebrow="VOLUME · BRIGHTNESS" lead="Goodbye, " accent="grey square." bottom={120} size={92} />
      <Super at={80} out={148} lead="Hello, " accent="beautiful." align="right" bottom={120} size={92} />
    </AbsoluteFill>
  );
};

import { Sun } from "../components/Icons";
const BrightnessWings: React.FC<{ level: number }> = ({ level }) => (
  <Wings wing={108} left={<Sun size={17} color="#FFD60A" />} right={
    <div style={{ width: 64, height: 5, borderRadius: 5, background: "rgba(255,255,255,0.16)" }}><div style={{ width: `${level * 100}%`, height: 5, borderRadius: 5, background: "#FFD60A" }} /></div>} />
);

const KeysMacro: React.FC<{ f: number; press: (at: number) => number }> = ({ f, press }) => {
  const keys = [{ ats: [] as number[], icon: "mute", label: "F10" }, { ats: [], icon: "down", label: "F11" }, { ats: [27, 40, 54], icon: "up", label: "F12" }];
  return (
    <AbsoluteFill style={{ background: "radial-gradient(60% 60% at 50% 40%, #23242A, #08080A)", perspective: 1400 }}>
      <div style={{ position: "absolute", left: "50%", top: "46%", translate: "-50% -50%", display: "flex", gap: 60,
        transform: `rotateX(42deg) rotateZ(${lerp(f, [0, 48], [-4, -1])}deg) scale(${lerp(f, [0, 48], [2.1, 2.45])})` }}>
        {keys.map((k, i) => {
          const p = Math.max(0, ...k.ats.map(press));
          return (
            <div key={i} style={{ width: 230, height: 150, borderRadius: 26, background: "linear-gradient(180deg,#141416,#0B0B0C)",
              boxShadow: `0 ${18 - 14 * p}px 0 #000, 0 ${30 - 20 * p}px 50px rgba(0,0,0,0.6), inset 0 1px 0 rgba(255,255,255,0.08)`,
              translate: `0 ${p * 12}px`, display: "grid", placeItems: "center" }}>
              <svg width="60" height="60" viewBox="0 0 24 24"><path d="M4 9.5h3.2L12 5.5v13l-4.8-4H4z" fill="rgba(255,255,255,0.75)" />
                {k.icon !== "mute" && <path d="M15.5 9.2a4 4 0 0 1 0 5.6" stroke="rgba(255,255,255,0.75)" strokeWidth="1.6" fill="none" strokeLinecap="round" />}
                {k.icon === "up" && <path d="M18 7a7.2 7.2 0 0 1 0 10" stroke="rgba(255,255,255,0.75)" strokeWidth="1.6" fill="none" strokeLinecap="round" />}
              </svg>
              <div style={{ position: "absolute", bottom: 18, fontFamily: sans, fontSize: 18, color: "rgba(255,255,255,0.5)", fontWeight: 500 }}>{k.label}</div>
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};
export { Agenda, serif };
