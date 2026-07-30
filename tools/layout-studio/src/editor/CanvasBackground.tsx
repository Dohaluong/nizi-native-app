import { Rect } from "react-konva";
import type { AlbumLayoutBackground } from "../domain/albumLayout";

interface Props {
  background: AlbumLayoutBackground;
  width: number;
  height: number;
}

/** Only `background.type === "solid"` exists in the real schema today (§ AlbumLayoutBackground.
 * swift) — rendered as a plain filled rect behind every slot. */
export function CanvasBackground({ background, width, height }: Props) {
  return <Rect x={0} y={0} width={width} height={height} fill={background.value} listening={false} />;
}
