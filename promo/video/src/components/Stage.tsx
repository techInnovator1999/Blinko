import React from "react";
import { AbsoluteFill, useCurrentFrame, interpolate } from "remotion";
import { Camera } from "./MacBook";
import { easeInOut } from "../theme";

/** Dark studio stage with a coloured key light behind the subject and a soft floor. */
export const Stage: React.FC<{ color?: string; intensity?: number; floor?: number }> = ({ color = "#6B4CFF", intensity = 1, floor = 1 }) => (
  <AbsoluteFill style={{ background: "#040407" }}>
    <AbsoluteFill style={{ background: `radial-gradient(42% 46% at 50% 44%, ${color}, transparent 72%)`, opacity: 0.42 * intensity }} />
    <AbsoluteFill style={{ background: "radial-gradient(70% 40% at 50% 100%, rgba(255,255,255,0.05), transparent 70%)", opacity: floor }} />
    <AbsoluteFill style={{ background: "radial-gradient(120% 90% at 50% 50%, transparent 55%, rgba(0,0,0,0.75) 100%)" }} />
  </AbsoluteFill>
);

/** Animated film grain + subtle vignette so the CG never looks sterile. */
export const Grain: React.FC<{ opacity?: number }> = ({ opacity = 0.07 }) => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill style={{ pointerEvents: "none", mixBlendMode: "overlay", opacity }}>
      <svg width="100%" height="100%">
        <filter id="grain"><feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed={frame % 24} /></filter>
        <rect width="100%" height="100%" filter="url(#grain)" />
      </svg>
    </AbsoluteFill>
  );
};

type Key = { f: number } & Camera;

/** Piecewise camera path; every segment eased in-out like a real dolly/crane move. */
export const cam = (frame: number, keys: Key[]): Camera => {
  const fs = keys.map((k) => k.f);
  const pick = (p: keyof Camera, d: number) =>
    interpolate(frame, fs, keys.map((k) => (k[p] ?? d) as number), { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: easeInOut });
  return { rx: pick("rx", 0), ry: pick("ry", 0), rz: pick("rz", 0), x: pick("x", 0), y: pick("y", 0), scale: pick("scale", 1), focus: pick("focus", 0) };
};
