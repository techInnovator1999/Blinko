import React from "react";
import { spring } from "remotion";
import { Island } from "../components/Island";
import { NOTCH, OPEN } from "../components/IslandUI";
import { FPS } from "../theme";

export const pop = (frame: number, start: number, damping = 15, stiffness = 170) =>
  spring({ frame: frame - start, fps: FPS, config: { damping, stiffness, mass: 0.9 } });

export const mix = (a: number, b: number, t: number) => a + (b - a) * t;

/** Island whose size springs between states (closed → wings → open). */
export const LiveIsland: React.FC<React.PropsWithChildren<{
  wing?: number; open?: number; glow?: number; glowColor?: string; peek?: number;
}>> = ({ wing = 0, open = 0, glow = 0, glowColor, peek = 0, children }) => {
  const cw = NOTCH.w + wing * 2 + peek * 18;
  const ch = NOTCH.h + peek * 5;
  const w = mix(cw, OPEN.w, open);
  const h = mix(ch, OPEN.h, open);
  return (
    <Island width={w} height={h} topRadius={mix(6, 19, open)} bottomRadius={mix(wing > 0 ? 16 : 14, 26, open)}
      glow={glow} glowColor={glowColor} shadow={open}>
      {children}
    </Island>
  );
};
