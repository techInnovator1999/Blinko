import React from "react";
import { sans } from "../theme";

export const SCREEN = { w: 1512, h: 982, notchW: 185, notchH: 32 };

/** Original aurora wallpaper — layered gradients, no stock imagery. */
const Wallpaper: React.FC<{ dim?: number }> = ({ dim = 0 }) => (
  <div style={{ position: "absolute", inset: 0, background: "#0B0B1A", overflow: "hidden" }}>
    <div style={{ position: "absolute", inset: 0, background: `
      radial-gradient(60% 55% at 18% 78%, #3B1E8C 0%, transparent 70%),
      radial-gradient(55% 60% at 85% 85%, #0F5E8A 0%, transparent 70%),
      radial-gradient(45% 40% at 70% 25%, #8A2A6B 0%, transparent 70%),
      radial-gradient(70% 70% at 40% 40%, #161638 0%, transparent 80%)` }} />
    <div style={{ position: "absolute", left: "-10%", right: "-10%", top: "38%", height: "30%",
      background: "linear-gradient(100deg, transparent 10%, rgba(120,255,220,0.18) 40%, rgba(160,120,255,0.22) 60%, transparent 90%)",
      filter: "blur(40px)", rotate: "-8deg" }} />
    <div style={{ position: "absolute", inset: 0, background: `rgba(0,0,0,${dim})` }} />
  </div>
);

const MenuBar: React.FC<{ time: string }> = ({ time }) => (
  <div style={{ position: "absolute", left: 0, right: 0, top: 0, height: SCREEN.notchH, display: "flex",
    alignItems: "center", padding: "0 18px", gap: 22, fontFamily: sans, fontSize: 14, fontWeight: 500,
    color: "rgba(255,255,255,0.92)", background: "rgba(10,10,24,0.35)", backdropFilter: "blur(20px)" }}>
    <svg width="14" height="16" viewBox="0 0 14 16"><circle cx="7" cy="9" r="5.6" fill="#fff" /></svg>
    <span style={{ fontWeight: 700 }}>Studio</span>
    {["File", "Edit", "View", "Window", "Help"].map((m) => <span key={m}>{m}</span>)}
    <div style={{ flex: 1 }} />
    {/* generic status glyphs */}
    <svg width="18" height="14" viewBox="0 0 18 14"><path d="M9 12.5 2 5.6a10 10 0 0 1 14 0z" fill="#fff" /></svg>
    <svg width="26" height="13" viewBox="0 0 26 13"><rect x=".7" y=".7" width="21.6" height="11.6" rx="3.2" fill="none" stroke="#fff" strokeOpacity=".6" /><rect x="2.4" y="2.4" width="15" height="8.2" rx="1.8" fill="#fff" /><rect x="23.4" y="4.3" width="1.8" height="4.4" rx=".9" fill="#fff" fillOpacity=".6" /></svg>
    <svg width="16" height="16" viewBox="0 0 16 16"><rect x="1" y="2" width="6" height="5" rx="1.5" fill="#fff" /><rect x="9" y="2" width="6" height="5" rx="1.5" fill="#fff" fillOpacity=".7" /><rect x="1" y="9" width="14" height="5" rx="1.5" fill="#fff" fillOpacity=".85" /></svg>
    <span>{time}</span>
  </div>
);

/** Fake window with placeholder content bars only — no real text or data. */
export const Win: React.FC<React.PropsWithChildren<{ x: number; y: number; w: number; h: number; title: string; light?: boolean }>> = ({ x, y, w, h, title, light, children }) => (
  <div style={{ position: "absolute", left: x, top: y, width: w, height: h, borderRadius: 14, overflow: "hidden",
    background: light ? "rgba(246,246,250,0.96)" : "rgba(30,30,40,0.92)", boxShadow: "0 30px 80px rgba(0,0,0,0.45), 0 0 0 1px rgba(255,255,255,0.08)" }}>
    <div style={{ height: 38, display: "flex", alignItems: "center", gap: 8, padding: "0 14px",
      borderBottom: light ? "1px solid rgba(0,0,0,0.06)" : "1px solid rgba(255,255,255,0.06)" }}>
      {["#FF5F57", "#FEBC2E", "#28C840"].map((c) => <div key={c} style={{ width: 12, height: 12, borderRadius: 6, background: c }} />)}
      <div style={{ flex: 1, textAlign: "center", fontFamily: sans, fontSize: 13, fontWeight: 600, color: light ? "#333" : "#ddd", marginRight: 50 }}>{title}</div>
    </div>
    <div style={{ position: "absolute", top: 38, left: 0, right: 0, bottom: 0 }}>{children}</div>
  </div>
);

const Bars: React.FC<{ rows: number[]; color: string; gap?: number }> = ({ rows, color, gap = 14 }) => (
  <div style={{ display: "flex", flexDirection: "column", gap, padding: 26 }}>
    {rows.map((w, i) => <div key={i} style={{ width: `${w}%`, height: 10, borderRadius: 5, background: color }} />)}
  </div>
);

const Dock: React.FC = () => {
  const tiles = ["#5E5CE6", "#FF9F0A", "#30D158", "#0A84FF", "#FF375F", "#64D2FF", "#BF5AF2", "#FFD60A"];
  return (
    <div style={{ position: "absolute", left: "50%", bottom: 10, translate: "-50% 0", display: "flex", gap: 10, padding: 10,
      borderRadius: 24, background: "rgba(255,255,255,0.14)", backdropFilter: "blur(24px)", boxShadow: "0 0 0 1px rgba(255,255,255,0.12)" }}>
      {tiles.map((c, i) => (
        <div key={i} style={{ width: 54, height: 54, borderRadius: 13, background: `linear-gradient(160deg, ${c}, ${c}AA)`,
          boxShadow: "inset 0 1px 0 rgba(255,255,255,0.35)" }}>
          <div style={{ margin: 15, width: 24, height: 24, borderRadius: i % 2 ? 12 : 6, background: "rgba(255,255,255,0.85)" }} />
        </div>
      ))}
    </div>
  );
};

/** Full dummy macOS desktop at the 14" MacBook Pro logical resolution. */
export const Desktop: React.FC<React.PropsWithChildren<{ dim?: number; windows?: boolean; time?: string }>> = ({ dim = 0, windows = true, time = "Thu 9:41 AM", children }) => (
  <div style={{ position: "absolute", inset: 0, overflow: "hidden" }}>
    <Wallpaper dim={dim} />
    {windows && (
      <>
        <Win x={120} y={120} w={760} h={520} title="Moodboard — Launch">
          <div style={{ position: "absolute", inset: 0, background: "#16161F" }}>
            <div style={{ position: "absolute", left: 40, top: 40, width: 300, height: 200, borderRadius: 16, background: "linear-gradient(135deg,#FF4F9A,#8B6CFF)" }} />
            <div style={{ position: "absolute", left: 370, top: 40, width: 340, height: 200, borderRadius: 16, background: "linear-gradient(135deg,#1B2A4A,#4FE3FF)" }} />
            <div style={{ position: "absolute", left: 40, top: 270, width: 200, height: 170, borderRadius: 16, background: "#2A2A38" }} />
            <div style={{ position: "absolute", left: 270, top: 270, width: 440, height: 170, borderRadius: 16, background: "#1F1F2B" }}>
              <Bars rows={[70, 90, 55]} color="rgba(255,255,255,0.12)" />
            </div>
          </div>
        </Win>
        <Win x={930} y={210} w={460} h={480} title="Notes" light>
          <Bars rows={[60, 92, 86, 74, 90, 40, 82, 66]} color="rgba(0,0,0,0.09)" gap={16} />
        </Win>
      </>
    )}
    <MenuBar time={time} />
    <Dock />
    {children}
  </div>
);
