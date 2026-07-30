import type Konva from "konva";

/** § user request: "Trong konva có tính năng align theo object và stage" — Konva's own
 * "Objects Snapping" recipe (start/center/end of every other shape, plus the stage's own edges
 * and center), adapted to this app's per-slot `Konva.Group` nodes. Toggleable, independent of the
 * existing 1%-of-page grid `snapEnabled` — this snaps to *other slots' actual edges* live during
 * a drag, not to a fixed grid. */

export interface AlignmentGuide {
  orientation: "V" | "H";
  /** Pixel position of the guide line within the Stage. */
  position: number;
}

interface SnapStop {
  guide: number;
  offset: number;
}

const SNAP_THRESHOLD_PX = 6;

function stageStops(stageWidth: number, stageHeight: number): { vertical: number[]; horizontal: number[] } {
  return {
    vertical: [0, stageWidth / 2, stageWidth],
    horizontal: [0, stageHeight / 2, stageHeight],
  };
}

function otherNodeStops(nodes: Konva.Group[]): { vertical: number[]; horizontal: number[] } {
  const vertical: number[] = [];
  const horizontal: number[] = [];
  for (const node of nodes) {
    const box = node.getClientRect();
    vertical.push(box.x, box.x + box.width / 2, box.x + box.width);
    horizontal.push(box.y, box.y + box.height / 2, box.y + box.height);
  }
  return { vertical, horizontal };
}

function snapStopsForNode(node: Konva.Group): { vertical: SnapStop[]; horizontal: SnapStop[] } {
  const box = node.getClientRect();
  return {
    vertical: [
      { guide: box.x, offset: node.x() - box.x },
      { guide: box.x + box.width / 2, offset: node.x() - box.x - box.width / 2 },
      { guide: box.x + box.width, offset: node.x() - box.x - box.width },
    ],
    horizontal: [
      { guide: box.y, offset: node.y() - box.y },
      { guide: box.y + box.height / 2, offset: node.y() - box.y - box.height / 2 },
      { guide: box.y + box.height, offset: node.y() - box.y - box.height },
    ],
  };
}

function closestMatch(guideStops: number[], nodeStops: SnapStop[]): { guideValue: number; diff: number; offset: number } | undefined {
  let best: { guideValue: number; diff: number; offset: number } | undefined;
  for (const guideValue of guideStops) {
    for (const stop of nodeStops) {
      const diff = Math.abs(guideValue - stop.guide);
      if (diff < SNAP_THRESHOLD_PX && (!best || diff < best.diff)) {
        best = { guideValue, diff, offset: stop.offset };
      }
    }
  }
  return best;
}

/** Computes the nearest alignment guide (if any) on each axis for `draggingNode` against the
 * Stage's own bounds and every node in `otherNodes`, and the position that node should be pulled
 * to so it lands exactly on those guides. Call from a slot's `dragmove` handler and apply
 * `snappedPosition` to the node directly (the standard Konva snapping pattern — mutate position
 * live during the drag, not just at drag end). */
export function computeAlignmentGuides(
  draggingNode: Konva.Group,
  otherNodes: Konva.Group[],
  stageSize: { width: number; height: number },
): { guides: AlignmentGuide[]; snappedPosition: { x: number; y: number } } {
  const stage = stageStops(stageSize.width, stageSize.height);
  const others = otherNodeStops(otherNodes);
  const verticalStops = [...stage.vertical, ...others.vertical];
  const horizontalStops = [...stage.horizontal, ...others.horizontal];
  const nodeSnaps = snapStopsForNode(draggingNode);

  const bestV = closestMatch(verticalStops, nodeSnaps.vertical);
  const bestH = closestMatch(horizontalStops, nodeSnaps.horizontal);

  const guides: AlignmentGuide[] = [];
  const snappedPosition = { x: draggingNode.x(), y: draggingNode.y() };
  if (bestV) {
    guides.push({ orientation: "V", position: bestV.guideValue });
    snappedPosition.x = bestV.guideValue + bestV.offset;
  }
  if (bestH) {
    guides.push({ orientation: "H", position: bestH.guideValue });
    snappedPosition.y = bestH.guideValue + bestH.offset;
  }
  return { guides, snappedPosition };
}
