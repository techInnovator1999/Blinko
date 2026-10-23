import React from "react";
import { AbsoluteFill, Sequence, staticFile } from "remotion";
import { Audio } from "@remotion/media";
import { T } from "./timeline";
import { Grain } from "./components/Stage";
import { ColdOpen, Reveal, Music, Hud } from "./scenes/Opening";
import { Shelf, Calendar, Montage, Perf, End } from "./scenes/Features";

export const Promo: React.FC = () => (
  <AbsoluteFill style={{ background: "#000" }}>
    <Sequence from={T.cold.from} durationInFrames={T.cold.dur}><ColdOpen /></Sequence>
    <Sequence from={T.reveal.from} durationInFrames={T.reveal.dur}><Reveal /></Sequence>
    <Sequence from={T.music.from} durationInFrames={T.music.dur}><Music /></Sequence>
    <Sequence from={T.hud.from} durationInFrames={T.hud.dur}><Hud /></Sequence>
    <Sequence from={T.shelf.from} durationInFrames={T.shelf.dur}><Shelf /></Sequence>
    <Sequence from={T.calendar.from} durationInFrames={T.calendar.dur}><Calendar /></Sequence>
    <Sequence from={T.montage.from} durationInFrames={T.montage.dur}><Montage /></Sequence>
    <Sequence from={T.perf.from} durationInFrames={T.perf.dur}><Perf /></Sequence>
    <Sequence from={T.end.from} durationInFrames={T.end.dur}><End /></Sequence>
    <Grain opacity={0.06} />
    <Audio src={staticFile("audio/master.wav")} />
  </AbsoluteFill>
);
