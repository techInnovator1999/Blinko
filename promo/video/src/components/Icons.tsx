import React from "react";

type P = { size?: number; color?: string; stroke?: number; style?: React.CSSProperties };
const S: React.FC<React.PropsWithChildren<P & { fill?: boolean }>> = ({ size = 24, color = "#fff", stroke = 2, fill, style, children }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" style={style}
    fill={fill ? color : "none"} stroke={fill ? "none" : color} strokeWidth={stroke}
    strokeLinecap="round" strokeLinejoin="round">{children}</svg>
);

export const Play = (p: P) => <S {...p} fill><path d="M7 4.8v14.4a1 1 0 0 0 1.5.86l11.6-7.2a1 1 0 0 0 0-1.72L8.5 3.94A1 1 0 0 0 7 4.8z" /></S>;
export const Pause = (p: P) => <S {...p} fill><rect x="5.5" y="4" width="4.6" height="16" rx="1.4" /><rect x="13.9" y="4" width="4.6" height="16" rx="1.4" /></S>;
export const Next = (p: P) => <S {...p} fill><path d="M3 6.2v11.6a.8.8 0 0 0 1.2.68L12 13.4v4.4a.8.8 0 0 0 1.2.68l8.6-5.8a.8.8 0 0 0 0-1.36L13.2 5.52a.8.8 0 0 0-1.2.68v4.4L4.2 5.52A.8.8 0 0 0 3 6.2z" /></S>;
export const Prev = (p: P) => <S {...p} style={{ ...p.style, transform: "scaleX(-1)" }} fill><path d="M3 6.2v11.6a.8.8 0 0 0 1.2.68L12 13.4v4.4a.8.8 0 0 0 1.2.68l8.6-5.8a.8.8 0 0 0 0-1.36L13.2 5.52a.8.8 0 0 0-1.2.68v4.4L4.2 5.52A.8.8 0 0 0 3 6.2z" /></S>;
export const Speaker = (p: P & { waves?: number }) => (
  <S {...p}>
    <path d="M4 9.5h3.2L12 5.5v13l-4.8-4H4z" fill={p.color ?? "#fff"} stroke="none" />
    {(p.waves ?? 3) > 0 && <path d="M15.5 9.2a4 4 0 0 1 0 5.6" />}
    {(p.waves ?? 3) > 1 && <path d="M18 7a7.2 7.2 0 0 1 0 10" />}
  </S>
);
export const Sun = (p: P) => (
  <S {...p}><circle cx="12" cy="12" r="4" fill={p.color ?? "#fff"} stroke="none" />
    {[0, 45, 90, 135, 180, 225, 270, 315].map((a) => (
      <line key={a} x1={12 + Math.cos((a * Math.PI) / 180) * 7} y1={12 + Math.sin((a * Math.PI) / 180) * 7}
        x2={12 + Math.cos((a * Math.PI) / 180) * 9.4} y2={12 + Math.sin((a * Math.PI) / 180) * 9.4} />
    ))}</S>
);
export const Bolt = (p: P) => <S {...p} fill><path d="M13.2 2.5 4.8 13.4h6.1l-1.2 8.1 8.5-11h-6.2z" /></S>;
export const Tray = (p: P) => <S {...p}><path d="M3.5 13.5 6 5.5h12l2.5 8v5a1 1 0 0 1-1 1h-15a1 1 0 0 1-1-1z" /><path d="M3.5 13.5h4.5l1.5 2.5h5l1.5-2.5h4.5" /></S>;
export const Calendar = (p: P) => <S {...p}><rect x="3.5" y="5" width="17" height="15" rx="3" /><path d="M3.5 9.5h17M8 3v4M16 3v4" /></S>;
export const Video = (p: P) => <S {...p} fill><rect x="2.5" y="6.5" width="13" height="11" rx="2.5" /><path d="M16.5 10.6 21.5 7.5v9l-5-3.1z" /></S>;
export const Home = (p: P) => <S {...p} fill><path d="M12 3.2 2.8 11h2.7v9.3h5v-6h3v6h5V11h2.7z" /></S>;
export const Clip = (p: P) => <S {...p}><rect x="5.5" y="4.5" width="13" height="16" rx="2.5" /><path d="M9 4.5V3.5h6v1M9 10h6M9 14h6" /></S>;
export const Gauge = (p: P) => <S {...p}><path d="M4 17a8.5 8.5 0 1 1 16 0" /><path d="M12 13l4-4" /><circle cx="12" cy="13" r="1.4" fill={p.color ?? "#fff"} /></S>;
export const TimerI = (p: P) => <S {...p}><circle cx="12" cy="13.5" r="7.5" /><path d="M12 13.5V9.5M9.5 2.8h5" /></S>;
export const Pods = (p: P) => (
  <S {...p} fill>
    <path d="M7 3.5a3.2 3.2 0 0 0-3.2 3.3c0 1.9 1.3 3.2 3 3.4v8.3a1.3 1.3 0 0 0 2.6 0V6.8A3.3 3.3 0 0 0 7 3.5z" />
    <path d="M17 3.5a3.2 3.2 0 0 1 3.2 3.3c0 1.9-1.3 3.2-3 3.4v8.3a1.3 1.3 0 0 1-2.6 0V6.8A3.3 3.3 0 0 1 17 3.5z" />
  </S>
);
export const Brain = (p: P) => <S {...p}><path d="M9 4.5a3 3 0 0 0-3 3 3 3 0 0 0-2 5.2 3 3 0 0 0 2.5 4.8A3 3 0 0 0 12 18V6.2A2.7 2.7 0 0 0 9 4.5zM15 4.5a3 3 0 0 1 3 3 3 3 0 0 1 2 5.2 3 3 0 0 1-2.5 4.8A3 3 0 0 1 12 18" /></S>;
export const Shuffle = (p: P) => <S {...p}><path d="M3.5 7h3.2c2 0 3.2 1 4.3 2.8l2 3.4c1.1 1.8 2.3 2.8 4.3 2.8h3.2M3.5 17h3.2c1.4 0 2.3-.5 3.1-1.3M14 8.3c.8-.8 1.7-1.3 3.1-1.3h3.4M18 4.5 20.5 7 18 9.5M18 14.5l2.5 2.5-2.5 2.5" /></S>;
export const Repeat = (p: P) => <S {...p}><path d="M4 11V9.5A2.5 2.5 0 0 1 6.5 7H19M16.5 4.5 19 7l-2.5 2.5M20 13v1.5a2.5 2.5 0 0 1-2.5 2.5H5M7.5 19.5 5 17l2.5-2.5" /></S>;
export const Airdrop = (p: P) => <S {...p}><circle cx="12" cy="12" r="1.8" fill={p.color ?? "#fff"} /><path d="M8.2 15.8a5.4 5.4 0 1 1 7.6 0M5.4 18.6a9.4 9.4 0 1 1 13.2 0" /></S>;
export const Cursor = ({ size = 28 }: { size?: number }) => (
  <svg width={size} height={size} viewBox="0 0 28 28">
    <path d="M6 3.5v19.2l5.2-5 3.4 8 3.3-1.4-3.4-7.9h7.2z" fill="#000" stroke="#fff" strokeWidth="1.6" strokeLinejoin="round" />
  </svg>
);
