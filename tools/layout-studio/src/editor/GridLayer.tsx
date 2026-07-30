import { Line } from "react-konva";

interface Props {
  width: number;
  height: number;
  columns?: number;
  rows?: number;
}

/** § 13 — design-time-only 20×20-ish grid, never exported (no grid metadata exists anywhere in
 * the real schema or the Studio project shape). */
export function GridLayer({ width, height, columns = 20, rows = 20 }: Props) {
  const lines = [];
  for (let i = 1; i < columns; i += 1) {
    const x = (width / columns) * i;
    lines.push(<Line key={`v-${i}`} points={[x, 0, x, height]} stroke="#00000010" strokeWidth={1} listening={false} />);
  }
  for (let i = 1; i < rows; i += 1) {
    const y = (height / rows) * i;
    lines.push(<Line key={`h-${i}`} points={[0, y, width, y]} stroke="#00000010" strokeWidth={1} listening={false} />);
  }
  return <>{lines}</>;
}
