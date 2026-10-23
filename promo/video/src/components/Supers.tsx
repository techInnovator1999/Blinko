import React from "react";
import { useCurrentFrame } from "remotion";
import { lerp, sans, serif, easeOut } from "../theme";

/** Editorial on-screen line: small eyebrow + big statement with an italic serif accent. */
export const Super: React.FC<{
  at: number; out: number; eyebrow?: string; lead?: string; accent?: string; tail?: string;
  align?: "left" | "center" | "right"; bottom?: number; size?: number;
}> = ({ at, out, eyebrow, lead, accent, tail, align = "left", bottom = 120, size = 84 }) => {
  const f = useCurrentFrame();
  const a = lerp(f, [at, at + 14], [0, 1], easeOut) * lerp(f, [out - 10, out], [1, 0]);
  const y = lerp(f, [at, at + 18], [26, 0], easeOut);
  const side = align === "center" ? { left: 0, right: 0, textAlign: "center" as const } : align === "left" ? { left: 130 } : { right: 130, textAlign: "right" as const };
  return (
    <>
    <div style={{ position: "absolute", left: 0, right: 0, bottom: 0, height: 520, opacity: a, pointerEvents: "none",
      background: `radial-gradient(70% 90% at ${align === "left" ? "18%" : align === "right" ? "82%" : "50%"} 100%, rgba(0,0,0,0.78), transparent 70%)` }} />
    <div style={{ position: "absolute", bottom, ...side, opacity: a, translate: `0 ${y}px`, color: "#fff", fontFamily: sans,
      textShadow: "0 4px 30px rgba(0,0,0,0.6)" }}>
      {eyebrow && <div style={{ fontSize: 22, fontWeight: 700, letterSpacing: 5, opacity: 0.55, marginBottom: 14 }}>{eyebrow}</div>}
      <div style={{ fontSize: size, fontWeight: 650, letterSpacing: -2, lineHeight: 1.02 }}>
        {lead}{accent && <span style={{ fontFamily: serif, fontStyle: "italic", fontWeight: 400, letterSpacing: -1 }}>{accent}</span>}{tail}
      </div>
    </div>
    </>
  );
};
