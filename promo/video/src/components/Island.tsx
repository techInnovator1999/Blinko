import React from "react";

/** Same silhouette as the app's NotchShape: concave top ears + continuous bottom corners. */
export const islandPath = (w: number, h: number, t: number, b: number) => {
  t = Math.min(t, w / 4);
  b = Math.min(b, (h - t) / 1.2, w / 4);
  return [
    `M0 0`,
    `Q${t} 0 ${t} ${t}`,
    `L${t} ${h - b}`,
    `C${t} ${h - b * 0.45} ${t + b * 0.45} ${h} ${t + b} ${h}`,
    `L${w - t - b} ${h}`,
    `C${w - t - b * 0.45} ${h} ${w - t} ${h - b * 0.45} ${w - t} ${h - b}`,
    `L${w - t} ${t}`,
    `Q${w - t} 0 ${w} 0`,
    `Z`,
  ].join(" ");
};

type Props = {
  width: number;
  height: number;
  topRadius?: number;
  bottomRadius?: number;
  glow?: number; // 0..1 accent glow under the island
  glowColor?: string;
  shadow?: number; // 0..1
  children?: React.ReactNode;
};

/** Island anchored at its top-centre. Content is clipped to the silhouette. */
export const Island: React.FC<Props> = ({
  width, height, topRadius = 6, bottomRadius = 14, glow = 0, glowColor = "#FF4F9A", shadow = 0, children,
}) => {
  const d = islandPath(width, height, topRadius, bottomRadius);
  const id = React.useId().replace(/:/g, "");
  return (
    <div style={{ position: "absolute", left: "50%", top: 0, width, height, marginLeft: -width / 2 }}>
      {glow > 0 && (
        <div style={{
          position: "absolute", left: width * 0.1, right: width * 0.1, top: height * 0.4, height: height * 0.9,
          background: `radial-gradient(50% 50% at 50% 30%, ${glowColor}, transparent 70%)`,
          opacity: glow * 0.7, filter: `blur(${Math.max(12, height * 0.35)}px)`,
        }} />
      )}
      <svg width={width} height={height} style={{
        position: "absolute", inset: 0, overflow: "visible",
        filter: shadow > 0 ? `drop-shadow(0 ${height * 0.08}px ${height * 0.18}px rgba(0,0,0,${0.7 * shadow}))` : undefined,
      }}>
        <defs>
          <clipPath id={`c${id}`}><path d={d} /></clipPath>
          <linearGradient id={`r${id}`} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0.55" stopColor="#fff" stopOpacity="0" />
            <stop offset="1" stopColor="#fff" stopOpacity="0.09" />
          </linearGradient>
        </defs>
        <path d={d} fill="#000" />
        <path d={d} fill="none" stroke={`url(#r${id})`} strokeWidth={1.2} />
      </svg>
      <div style={{ position: "absolute", inset: 0, clipPath: `path('${d}')` }}>{children}</div>
    </div>
  );
};
