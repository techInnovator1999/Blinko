import { Easing } from "remotion";
import { loadFont as loadSerif } from "@remotion/google-fonts/InstrumentSerif";

export const serif = loadSerif("italic", { weights: ["400"], subsets: ["latin"] }).fontFamily;
export const sans = `-apple-system, "SF Pro Display", "SF Pro Text", system-ui, sans-serif`;
export const rounded = `"SF Pro Rounded", -apple-system, system-ui, sans-serif`;

export const FPS = 30;
export const W = 1920;
export const H = 1080;

// Motion curves
export const easeOut = Easing.bezier(0.16, 1, 0.3, 1);
export const easeInOut = Easing.bezier(0.65, 0, 0.35, 1);
export const easeIn = Easing.bezier(0.55, 0, 1, 0.45);
export const overshoot = Easing.bezier(0.34, 1.56, 0.64, 1);

export const C = {
  ink: "#05050A",
  stage: "#07070D",
  white: "#FFFFFF",
  dim: "rgba(255,255,255,0.62)",
  faint: "rgba(255,255,255,0.38)",
  pink: "#FF4F9A",
  violet: "#8B6CFF",
  cyan: "#4FE3FF",
  orange: "#FF9F2E",
  green: "#30D158",
  yellow: "#FFD60A",
  blue: "#0A84FF",
};

/** Clamp-by-default interpolate helper. */
import { interpolate } from "remotion";
export const lerp = (
  frame: number,
  input: number[],
  output: number[],
  easing: (t: number) => number = easeOut,
) => interpolate(frame, input, output, { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing });
