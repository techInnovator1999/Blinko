import React from "react";
import { SCREEN } from "./Desktop";

/** Supersampling factor: layout is SS× larger, then scaled down — keeps 3D close-ups crisp. */
const SS = 3;
const BEZEL = { side: 16, top: 16, bottom: 22 };
export const LID = { w: SCREEN.w + BEZEL.side * 2, h: SCREEN.h + BEZEL.top + BEZEL.bottom };

export type Camera = {
  rx?: number; // pitch (deg)
  ry?: number; // yaw (deg)
  rz?: number;
  x?: number; // px, screen space after scaling
  y?: number;
  scale?: number;
  focus?: number; // 0 = sharp, >0 = depth-of-field blur on the whole rig
};

/**
 * CSS-3D MacBook. Origin of the rig is the top-centre of the display (the notch), so
 * camera moves can push straight into the notch without the subject drifting.
 */
export const MacBook: React.FC<React.PropsWithChildren<{ camera: Camera; lidTilt?: number; screenGlow?: number }>> = ({
  camera, lidTilt = -6, screenGlow = 0, children,
}) => {
  const { rx = 0, ry = 0, rz = 0, x = 0, y = 0, scale = 1, focus = 0 } = camera;
  return (
    <div style={{ position: "absolute", inset: 0, perspective: 2600, perspectiveOrigin: "50% 40%",
      filter: focus > 0 ? `blur(${focus}px)` : undefined }}>
      <div style={{ position: "absolute", left: "50%", top: "50%", transformStyle: "preserve-3d",
        transform: `translate3d(${x}px, ${y}px, 0) scale(${scale / SS}) rotateX(${rx}deg) rotateY(${ry}deg) rotateZ(${rz}deg)` }}>
       <div style={{ zoom: SS, transformStyle: "preserve-3d" }}>
        {/* Lid: hinged at its bottom edge; the rig origin is the notch (top-centre of the screen). */}
        <div style={{ position: "absolute", left: -LID.w / 2, top: -BEZEL.top, width: LID.w, height: LID.h,
          transformStyle: "preserve-3d", transformOrigin: "50% 100%", transform: `rotateX(${lidTilt}deg)` }}>
          {/* back of lid */}
          <div style={{ position: "absolute", inset: 0, borderRadius: 26, background: "linear-gradient(180deg,#3A3B40,#1E1F23)",
            transform: "translateZ(-6px)" }} />
          {/* bezel */}
          <div style={{ position: "absolute", inset: 0, borderRadius: 26, background: "#050506",
            boxShadow: "0 0 0 2px #2A2B30, 0 0 0 3px #55565C", overflow: "hidden" }}>
            <div style={{ position: "absolute", left: BEZEL.side, top: BEZEL.top, width: SCREEN.w, height: SCREEN.h,
              borderRadius: "10px 10px 6px 6px", overflow: "hidden", background: "#000" }}>
              {children}
              {/* glass reflection */}
              <div style={{ position: "absolute", inset: 0, pointerEvents: "none",
                background: "linear-gradient(115deg, rgba(255,255,255,0.07) 0%, rgba(255,255,255,0) 32%, rgba(255,255,255,0) 70%, rgba(255,255,255,0.04) 100%)" }} />
            </div>
            {/* hardware notch is part of the bezel — the island draws over it */}
            <div style={{ position: "absolute", left: "50%", top: BEZEL.top - 1, width: SCREEN.notchW, height: SCREEN.notchH + 1,
              marginLeft: -SCREEN.notchW / 2, background: "#050506", borderRadius: "0 0 12px 12px" }} />
          </div>
        </div>
        {/* Base / keyboard deck lying flat, extending toward the viewer from the hinge. */}
        <div style={{ position: "absolute", left: -(LID.w + 60) / 2, top: LID.h - BEZEL.top, width: LID.w + 60, height: 1060,
          transformOrigin: "50% 0%", transform: "rotateX(90deg)", borderRadius: "10px 10px 34px 34px",
          background: "linear-gradient(180deg,#2C2D32,#1B1C20)", boxShadow: "inset 0 0 0 2px #45464C" }}>
          <Keyboard />
          <div style={{ position: "absolute", left: "50%", bottom: 70, width: 620, height: 380, marginLeft: -310,
            borderRadius: 18, background: "linear-gradient(180deg,#26272C,#202126)", boxShadow: "inset 0 0 0 1px #3A3B40" }} />
        </div>
        {screenGlow > 0 && (
          <div style={{ position: "absolute", left: -LID.w * 0.6, top: LID.h - 80, width: LID.w * 1.2, height: 500,
            transform: "rotateX(90deg)", transformOrigin: "50% 0%",
            background: "radial-gradient(50% 50% at 50% 0%, rgba(140,110,255,0.35), transparent 70%)", opacity: screenGlow }} />
        )}
       </div>
      </div>
    </div>
  );
};

const Keyboard: React.FC = () => {
  const rows = [14, 14, 14, 13, 12, 10];
  return (
    <div style={{ position: "absolute", left: 90, right: 90, top: 60, display: "flex", flexDirection: "column", gap: 10 }}>
      {rows.map((n, r) => (
        <div key={r} style={{ display: "flex", gap: 10, height: r === 0 ? 34 : 64 }}>
          {Array.from({ length: n }).map((_, i) => (
            <div key={i} style={{ flex: r === 5 && i === 4 ? 6 : 1, borderRadius: 9, background: "#0C0C0E",
              boxShadow: "inset 0 -2px 0 rgba(255,255,255,0.05), 0 1px 0 rgba(255,255,255,0.04)" }} />
          ))}
        </div>
      ))}
    </div>
  );
};
