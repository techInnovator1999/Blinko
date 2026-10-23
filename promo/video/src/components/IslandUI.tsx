import React from "react";
import { C, sans, rounded } from "../theme";
import * as I from "./Icons";

export const NOTCH = { w: 185, h: 32 };
export const OPEN = { w: 700, h: 210 };

/** Original procedural "album art" for the fictional track. */
export const Artwork: React.FC<{ size: number; radius?: number }> = ({ size, radius = size * 0.14 }) => (
  <div style={{ width: size, height: size, borderRadius: radius, overflow: "hidden", position: "relative",
    background: "linear-gradient(145deg,#FF5E9A 0%,#A24BFF 55%,#3B2BB8 100%)", flexShrink: 0 }}>
    <div style={{ position: "absolute", left: "18%", top: "52%", width: "64%", height: "64%", borderRadius: "50%",
      background: "radial-gradient(circle at 50% 30%, #FFD3A1, #FF7A59 60%, transparent 61%)" }} />
    <div style={{ position: "absolute", left: 0, right: 0, top: "62%", height: "2%", background: "rgba(255,255,255,0.5)" }} />
    <div style={{ position: "absolute", left: 0, right: 0, top: "70%", height: "1.5%", background: "rgba(255,255,255,0.3)" }} />
    <div style={{ position: "absolute", inset: 0, background: "linear-gradient(180deg,transparent 60%,rgba(20,0,60,0.45))" }} />
  </div>
);

export const Visualizer: React.FC<{ frame: number; color?: string; h?: number; playing?: boolean }> = ({ frame, color = C.pink, h = 13, playing = true }) => (
  <div style={{ display: "flex", gap: 2.2, alignItems: "center", height: h }}>
    {[0, 1, 2, 3].map((i) => {
      const v = playing ? 0.3 + 0.7 * Math.abs(Math.sin(frame * (0.21 + i * 0.07) + i * 1.7)) : 0.25;
      return <div key={i} style={{ width: 2.6, height: h * v, borderRadius: 2, background: color }} />;
    })}
  </div>
);

/** Two wings either side of the hardware notch. */
export const Wings: React.FC<{ wing: number; left: React.ReactNode; right: React.ReactNode; opacity?: number }> = ({ wing, left, right, opacity = 1 }) => (
  <div style={{ position: "absolute", inset: 0, display: "flex", alignItems: "center", opacity }}>
    <div style={{ width: wing, display: "flex", justifyContent: "flex-start", paddingLeft: 12 }}>{left}</div>
    <div style={{ width: NOTCH.w }} />
    <div style={{ width: wing, display: "flex", justifyContent: "flex-end", paddingRight: 12 }}>{right}</div>
  </div>
);

const Bar: React.FC<{ value: number; color?: string; w?: number; h?: number }> = ({ value, color = "#fff", w = 64, h = 5 }) => (
  <div style={{ width: w, height: h, borderRadius: h, background: "rgba(255,255,255,0.16)", overflow: "hidden" }}>
    <div style={{ width: `${Math.max(0, Math.min(1, value)) * 100}%`, height: "100%", borderRadius: h, background: color }} />
  </div>
);

export const CompactMusic: React.FC<{ frame: number }> = ({ frame }) => (
  <Wings wing={42} left={<Artwork size={22} radius={5} />} right={<Visualizer frame={frame} />} />
);

export const CompactVolume: React.FC<{ level: number }> = ({ level }) => (
  <Wings wing={108} left={<I.Speaker size={17} waves={level > 0.66 ? 2 : 1} />} right={<Bar value={level} />} />
);

export const CompactCharging: React.FC<{ level: number }> = ({ level }) => (
  <Wings wing={92}
    left={<div style={{ display: "flex", gap: 5, alignItems: "center", fontFamily: sans, fontSize: 11, fontWeight: 600, color: "#fff" }}><I.Bolt size={13} color={C.green} />Charging</div>}
    right={<div style={{ display: "flex", gap: 5, alignItems: "center", fontFamily: sans, fontSize: 11, fontWeight: 600, color: "#fff" }}>{Math.round(level)}%
      <div style={{ width: 22, height: 11, borderRadius: 3, border: "1px solid rgba(255,255,255,0.45)", padding: 1.5 }}>
        <div style={{ width: `${level}%`, height: "100%", borderRadius: 1.5, background: C.green }} /></div></div>} />
);

export const CompactPods: React.FC = () => (
  <Wings wing={116}
    left={<div style={{ display: "flex", gap: 6, alignItems: "center", fontFamily: sans, fontSize: 11, fontWeight: 600, color: "#fff" }}><I.Pods size={14} />Nova's AirPods</div>}
    right={<span style={{ fontFamily: sans, fontSize: 11, color: C.dim, fontWeight: 500 }}>Connected</span>} />
);

const Header: React.FC<{ tab: number }> = ({ tab }) => {
  const icons = [I.Home, I.Tray, I.Clip, I.Gauge, I.TimerI];
  return (
    <div style={{ height: 32, display: "flex", alignItems: "center", padding: "2px 27px 0" }}>
      <div style={{ display: "flex", gap: 2, padding: 2, borderRadius: 14, background: "rgba(255,255,255,0.05)" }}>
        {icons.map((Ic, i) => (
          <div key={i} style={{ width: 30, height: 22, borderRadius: 11, display: "grid", placeItems: "center", background: i === tab ? "#fff" : "transparent" }}>
            <Ic size={12} color={i === tab ? "#000" : C.dim} stroke={2.2} />
          </div>
        ))}
      </div>
      <div style={{ flex: 1 }} />
      <span style={{ fontFamily: sans, fontSize: 11.5, fontWeight: 600, color: C.dim }}>9:41 AM</span>
    </div>
  );
};

const Credit = () => (
  <div style={{ position: "absolute", bottom: 7, left: 0, right: 0, textAlign: "center", fontFamily: sans, fontSize: 9, fontWeight: 600, letterSpacing: 0.2 }}>
    <span style={{ color: "rgba(255,255,255,0.5)" }}>Designed by </span><span style={{ color: "rgba(255,255,255,0.75)" }}>OptimaGeeks</span>
  </div>
);

export const Panel: React.FC<React.PropsWithChildren<{ tab: number; reveal: number }>> = ({ tab, reveal, children }) => (
  <div style={{ position: "absolute", left: 0, top: 0, width: OPEN.w, height: OPEN.h, opacity: reveal,
    filter: `blur(${(1 - reveal) * 5}px)`, scale: `${0.95 + 0.05 * reveal}`, transformOrigin: "50% 0%" }}>
    <Header tab={tab} />
    <div style={{ position: "absolute", left: 31, right: 31, top: 42, bottom: 22 }}>{children}</div>
    <Credit />
  </div>
);

export const PlayerPanel: React.FC<{ frame: number; progress: number; playing?: boolean }> = ({ frame, progress, playing = true }) => (
  <div style={{ display: "flex", gap: 14, height: "100%" }}>
    <div style={{ position: "relative", marginTop: 6 }}>
      <div style={{ position: "absolute", inset: -16, filter: "blur(18px)", opacity: 0.55 }}><Artwork size={144} /></div>
      <div style={{ position: "relative", boxShadow: "0 8px 18px rgba(0,0,0,0.45)", borderRadius: 16 }}><Artwork size={112} radius={16} /></div>
    </div>
    <div style={{ flex: 1, display: "flex", flexDirection: "column", marginTop: 8, fontFamily: sans }}>
      <div style={{ fontSize: 15, fontWeight: 600, color: "#fff" }}>Afterglow</div>
      <div style={{ fontSize: 12.5, fontWeight: 500, color: "#FF85BC", marginTop: 2 }}>Nova Kai</div>
      <div style={{ marginTop: 14 }}><Bar value={progress} color="#FF85BC" w={250} h={4} /></div>
      <div style={{ display: "flex", justifyContent: "space-between", width: 250, marginTop: 5, fontSize: 10, color: C.faint, fontWeight: 500 }}>
        <span>{fmt(progress * 214)}</span><span>-{fmt((1 - progress) * 214)}</span>
      </div>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", width: 250, marginTop: 8 }}>
        <I.Shuffle size={13} color={C.faint} /><I.Prev size={17} />{playing ? <I.Pause size={24} /> : <I.Play size={24} />}<I.Next size={17} /><I.Repeat size={13} color={C.faint} />
      </div>
    </div>
    <div style={{ width: 1, background: "rgba(255,255,255,0.08)", margin: "8px 0" }} />
    <div style={{ width: 180, fontFamily: sans, paddingTop: 4 }}>
      <div style={{ fontSize: 30, fontWeight: 600, color: "#fff", fontFamily: rounded, letterSpacing: -0.5 }}>9:41</div>
      <div style={{ fontSize: 11.5, fontWeight: 600 }}><span style={{ color: "#FF6B6B" }}>Thursday</span> <span style={{ color: C.dim }}>14 Nov</span></div>
      <Agenda frame={frame} compact />
    </div>
  </div>
);

export const Agenda: React.FC<{ frame: number; compact?: boolean; joinGlow?: number }> = ({ compact, joinGlow = 0 }) => (
  <div style={{ display: "flex", flexDirection: "column", gap: 6, marginTop: 8 }}>
    {[
      { t: "Design Review", s: "10:00 – 10:30", c: "#BF5AF2", join: true },
      { t: "Lunch with Ari", s: "12:30 – 13:30", c: "#30D158" },
    ].slice(0, compact ? 2 : 3).map((e) => (
      <div key={e.t} style={{ display: "flex", alignItems: "center", gap: 7 }}>
        <div style={{ width: 3, height: 24, borderRadius: 2, background: e.c }} />
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 11, fontWeight: 600, color: "#fff" }}>{e.t}</div>
          <div style={{ fontSize: 10, color: C.faint, fontWeight: 500 }}>{e.s}</div>
        </div>
        {e.join && (
          <div style={{ width: 22, height: 18, borderRadius: 9, background: C.green, display: "grid", placeItems: "center",
            boxShadow: `0 0 ${18 * joinGlow}px ${6 * joinGlow}px rgba(48,209,88,${0.6 * joinGlow})`, scale: `${1 + 0.15 * joinGlow}` }}>
            <I.Video size={10} />
          </div>
        )}
      </div>
    ))}
  </div>
);

export const ShelfPanel: React.FC<{ files: number; airdrop: number }> = ({ files, airdrop }) => (
  <div style={{ display: "flex", gap: 12, height: "100%" }}>
    <div style={{ flex: 1, borderRadius: 16, border: "1.5px dashed rgba(255,255,255,0.16)", display: "flex", alignItems: "center", gap: 6, padding: 12 }}>
      {[
        { n: "Launch-Brief.pdf", c: "#FF453A" },
        { n: "Hero-v3.png", c: "#64D2FF" },
        { n: "Pitch.key", c: "#FF9F0A" },
      ].slice(0, files).map((f) => <FileTile key={f.n} name={f.n} color={f.c} />)}
    </div>
    <div style={{ width: 96, borderRadius: 16, background: `rgba(10,132,255,${0.14 + 0.7 * airdrop})`, display: "flex", flexDirection: "column",
      alignItems: "center", justifyContent: "center", gap: 6, color: airdrop > 0.5 ? "#fff" : C.blue, fontFamily: sans, fontSize: 11, fontWeight: 600, position: "relative" }}>
      {airdrop > 0 && [0, 1].map((k) => {
        const p = (airdrop * 1.6 + k * 0.5) % 1;
        return <div key={k} style={{ position: "absolute", width: 40 + 90 * p, height: 40 + 90 * p, borderRadius: "50%", border: "2px solid rgba(255,255,255,0.6)", opacity: 1 - p }} />;
      })}
      <I.Airdrop size={22} color={airdrop > 0.5 ? "#fff" : C.blue} />AirDrop
    </div>
  </div>
);

export const FileTile: React.FC<{ name: string; color: string; size?: number }> = ({ name, color, size = 52 }) => (
  <div style={{ width: 76, display: "flex", flexDirection: "column", alignItems: "center", gap: 5 }}>
    <div style={{ width: size * 0.8, height: size, borderRadius: 6, background: "#F2F2F7", position: "relative", boxShadow: "0 3px 8px rgba(0,0,0,0.35)" }}>
      <div style={{ position: "absolute", left: 6, right: 6, top: 10, height: 4, borderRadius: 2, background: "rgba(0,0,0,0.12)" }} />
      <div style={{ position: "absolute", left: 6, right: 12, top: 18, height: 4, borderRadius: 2, background: "rgba(0,0,0,0.12)" }} />
      <div style={{ position: "absolute", left: 4, right: 4, bottom: 6, height: 13, borderRadius: 3, background: color }} />
    </div>
    <div style={{ fontFamily: sans, fontSize: 9.5, color: C.dim, fontWeight: 500, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis", maxWidth: 76 }}>{name}</div>
  </div>
);

export const FocusPanel: React.FC<{ progress: number }> = ({ progress }) => {
  const r = 56, c = 2 * Math.PI * r;
  const remaining = 25 * 60 * (1 - progress);
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 24, height: "100%" }}>
      <svg width={130} height={130} viewBox="0 0 130 130">
        <circle cx="65" cy="65" r={r} fill="none" stroke="rgba(255,159,46,0.22)" strokeWidth="6" />
        <circle cx="65" cy="65" r={r} fill="none" stroke={C.orange} strokeWidth="6" strokeLinecap="round"
          strokeDasharray={c} strokeDashoffset={c * progress} transform="rotate(-90 65 65)" />
        <text x="65" y="68" textAnchor="middle" fill="#fff" fontFamily={rounded} fontWeight={600} fontSize={26}>{fmt(remaining)}</text>
        <text x="65" y="88" textAnchor="middle" fill={C.orange} fontFamily={sans} fontWeight={600} fontSize={10}>Focus</text>
      </svg>
      <div style={{ fontFamily: sans }}>
        <div style={{ display: "flex", gap: 6 }}>{[1, 1, 0, 0].map((f, i) => <div key={i} style={{ width: 9, height: 9, borderRadius: 5, background: f ? C.orange : "rgba(255,255,255,0.15)" }} />)}</div>
        <div style={{ color: C.faint, fontSize: 11, marginTop: 10, fontWeight: 500 }}>25m focus · 5m break · 15m long</div>
      </div>
    </div>
  );
};

export const ClipboardPanel: React.FC = () => (
  <div style={{ display: "flex", gap: 8, height: "100%", alignItems: "flex-start" }}>
    {[
      { a: "Notes", t: "Ship the island on Friday ✦ polish hover + haptics" },
      { a: "Studio", t: "#FF4F9A" , swatch: true },
      { a: "Browser", t: "blinko.app/download" },
      { a: "Mail", t: "Looks incredible. Can we demo it Monday?" },
    ].map((c) => (
      <div key={c.a} style={{ width: 142, height: 126, borderRadius: 12, background: "rgba(255,255,255,0.07)", padding: 10, fontFamily: sans }}>
        <div style={{ fontSize: 9.5, fontWeight: 600, color: C.faint }}>{c.a}</div>
        {c.swatch ? <div style={{ marginTop: 10, height: 64, borderRadius: 8, background: "#FF4F9A" }} /> :
          <div style={{ marginTop: 6, fontSize: 12, fontWeight: 500, color: "#fff", lineHeight: 1.3 }}>{c.t}</div>}
      </div>
    ))}
  </div>
);

export const StatsPanel: React.FC<{ frame: number }> = ({ frame }) => {
  const card = (title: string, value: string, color: string, seed: number) => {
    const pts = Array.from({ length: 30 }, (_, i) => 0.35 + 0.3 * Math.sin((i + frame * 0.4) * 0.45 + seed) + 0.15 * Math.sin((i + frame * 0.4) * 1.3 + seed * 2));
    const d = pts.map((v, i) => `${i === 0 ? "M" : "L"}${(i / 29) * 120} ${40 - v * 40}`).join(" ");
    return (
      <div style={{ flex: 1, borderRadius: 14, background: "rgba(255,255,255,0.07)", padding: 10, fontFamily: sans }}>
        <div style={{ fontSize: 9.5, fontWeight: 700, letterSpacing: 0.6, color }}>{title}</div>
        <div style={{ fontSize: 15, fontWeight: 600, color: "#fff" }}>{value}</div>
        <svg width="120" height="44" style={{ marginTop: 14 }}><path d={d} fill="none" stroke={color} strokeWidth="1.6" /><path d={`${d} L120 44 L0 44 Z`} fill={color} opacity={0.18} /></svg>
      </div>
    );
  };
  return (
    <div style={{ display: "flex", gap: 10, height: "100%" }}>
      {card("CPU", "12%", C.cyan, 0)}{card("MEMORY", "11.4 GB", "#BF5AF2", 1.3)}{card("NETWORK", "↓ 2.4 MB/s", C.green, 2.1)}{card("BATTERY", "86%", C.yellow, 3)}
    </div>
  );
};

export const fmt = (s: number) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}`;
