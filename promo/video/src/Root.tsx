import React from "react";
import { Composition } from "remotion";
import { Promo } from "./Promo";
import { T } from "./timeline";

export const RemotionRoot: React.FC = () => (
  <Composition id="BlinkoPromo" component={Promo} durationInFrames={T.total} fps={30} width={1920} height={1080} />
);
