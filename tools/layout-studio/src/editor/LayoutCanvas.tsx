import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import Konva from "konva";
import { Layer, Line, Stage } from "react-konva";
import type { StudioLayout } from "../domain/studioLayout";
import { frameToPixels, pixelsToFrame, snapFrame } from "../services/normalizeGeometry";
import { assignPreviewPhotos } from "../preview/LocalPhotoProvider";
import { useLayoutStudioStore } from "../store/layoutStudioStore";
import { CanvasBackground } from "./CanvasBackground";
import { GridLayer } from "./GridLayer";
import { LayoutSlot } from "./LayoutSlot";
import { SlotTransformer } from "./SlotTransformer";
import { computeAlignmentGuides, type AlignmentGuide } from "./alignmentGuides";

const MAX_STAGE_SIZE = 640;

interface Props {
  studioLayout: StudioLayout;
  showGrid: boolean;
  alignEnabled: boolean;
}

/** § 11 — the Page canvas. Scales to fit the editor area while keeping `referenceCanvas`'s own
 * aspect ratio (never a hardcoded square — § 11: "Nếu schema hiện tại có page aspect ratio thì
 * lấy từ schema thật"). */
export function LayoutCanvas({ studioLayout, showGrid, alignEnabled }: Props) {
  const { layout } = studioLayout;
  const selectedSlotId = useLayoutStudioStore((s) => s.selectedSlotId);
  const snapEnabled = useLayoutStudioStore((s) => s.snapEnabled);
  const previewPhotos = useLayoutStudioStore((s) => s.previewPhotos);
  const selectSlot = useLayoutStudioStore((s) => s.selectSlot);
  const updateSlotFrame = useLayoutStudioStore((s) => s.updateSlotFrame);
  const deleteSlot = useLayoutStudioStore((s) => s.deleteSlot);
  const duplicateSlot = useLayoutStudioStore((s) => s.duplicateSlot);
  const nudgeSlot = useLayoutStudioStore((s) => s.nudgeSlot);

  const aspect = layout.referenceCanvas.width / layout.referenceCanvas.height;
  const stageWidth = aspect >= 1 ? MAX_STAGE_SIZE : MAX_STAGE_SIZE * aspect;
  const stageHeight = aspect >= 1 ? MAX_STAGE_SIZE / aspect : MAX_STAGE_SIZE;
  const stagePixelSize = { width: stageWidth, height: stageHeight };

  // A plain mutable map (never a `useState`) — Konva node identity doesn't need React to
  // re-render on every attach/detach, only `SlotTransformer` needs to know about it, and only
  // when the *selection* changes. `setNodeRef` is memoized per slot id so its identity stays
  // stable across renders; an inline `ref={(node) => ...}` closure is re-created every render,
  // which made React treat it as a *different* ref each time and re-invoke it in a loop the
  // moment that callback itself called `setState` (the bug this replaces — "Maximum update depth
  // exceeded" at mount).
  const nodeRefs = useRef<Record<string, Konva.Group | null>>({});
  const setNodeRefCallbacks = useRef<Record<string, (node: Konva.Group | null) => void>>({});
  const setNodeRef = useCallback((slotId: string) => {
    if (!setNodeRefCallbacks.current[slotId]) {
      setNodeRefCallbacks.current[slotId] = (node) => {
        nodeRefs.current[slotId] = node;
      };
    }
    return setNodeRefCallbacks.current[slotId];
  }, []);

  const [selectedNode, setSelectedNode] = useState<Konva.Group | null>(null);
  useEffect(() => {
    setSelectedNode(selectedSlotId ? nodeRefs.current[selectedSlotId] ?? null : null);
  }, [selectedSlotId, layout.slots]);

  // § user request: "Konva có tính năng align theo object và stage. Cho phép bật để align" —
  // live snap-to-other-slots/snap-to-stage guides during drag, independent of the 1%-grid
  // `snapEnabled` above (that snaps to a fixed grid; this snaps to whatever's actually on the
  // page). `guidesActiveRef` tracks whether a guide was engaged for the drag currently in
  // progress, read (not just `alignmentGuides` state, which is cleared before `onDragEnd` fires)
  // so `onDragEnd` can skip the grid-percent snap when the alignment snap already placed the slot
  // exactly where it needs to be — stacking both would nudge it off the guide by a pixel or two.
  const [alignmentGuides, setAlignmentGuides] = useState<AlignmentGuide[]>([]);
  const guidesActiveRef = useRef(false);

  const handleDragMove = useCallback(
    (slotId: string, node: Konva.Group) => {
      const others = Object.entries(nodeRefs.current)
        .filter(([id, otherNode]) => id !== slotId && otherNode !== null)
        .map(([, otherNode]) => otherNode as Konva.Group);
      const { guides, snappedPosition } = computeAlignmentGuides(node, others, stagePixelSize);
      node.position(snappedPosition);
      guidesActiveRef.current = guides.length > 0;
      setAlignmentGuides(guides);
    },
    [stagePixelSize],
  );

  const photoAssignment = useMemo(
    () =>
      assignPreviewPhotos(
        layout.slots.map((s) => ({ id: s.id, preferredOrientation: s.preferredOrientation })),
        previewPhotos,
      ),
    [layout.slots, previewPhotos],
  );

  // § 26 — keyboard basics: Delete, Cmd/Ctrl+D duplicate, arrow nudge (Shift = bigger step), Esc
  // deselect. Ignored while typing in an Inspector text field.
  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      const target = event.target as HTMLElement | null;
      if (target && (target.tagName === "INPUT" || target.tagName === "TEXTAREA")) return;
      if (!selectedSlotId) return;

      if (event.key === "Delete" || event.key === "Backspace") {
        event.preventDefault();
        deleteSlot(studioLayout.key, selectedSlotId);
      } else if (event.key === "Escape") {
        selectSlot(null);
      } else if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "d") {
        event.preventDefault();
        duplicateSlot(studioLayout.key, selectedSlotId);
      } else if (event.key.startsWith("Arrow")) {
        event.preventDefault();
        const step = event.shiftKey ? 5 : 1;
        const dx = event.key === "ArrowLeft" ? -step : event.key === "ArrowRight" ? step : 0;
        const dy = event.key === "ArrowUp" ? -step : event.key === "ArrowDown" ? step : 0;
        nudgeSlot(studioLayout.key, selectedSlotId, dx, dy);
      }
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [selectedSlotId, studioLayout.key, deleteSlot, duplicateSlot, nudgeSlot, selectSlot]);

  return (
    <div className="canvas-wrapper">
      <Stage
        width={stageWidth}
        height={stageHeight}
        onMouseDown={(e) => {
          if (e.target === e.target.getStage()) selectSlot(null);
        }}
      >
        <Layer>
          <CanvasBackground background={layout.background} width={stageWidth} height={stageHeight} />
          {showGrid && <GridLayer width={stageWidth} height={stageHeight} />}
          {layout.slots.map((slot) => (
            <LayoutSlot
              key={slot.id}
              ref={setNodeRef(slot.id)}
              slot={slot}
              canvas={layout.referenceCanvas}
              stagePixelSize={stagePixelSize}
              isSelected={slot.id === selectedSlotId}
              previewPhoto={photoAssignment.get(slot.id)}
              onSelect={() => selectSlot(slot.id)}
              onDragMove={alignEnabled ? (node) => handleDragMove(slot.id, node) : undefined}
              onDragEnd={(pixelPosition) => {
                const currentPixels = frameToPixels(slot.frame, layout.referenceCanvas, stagePixelSize);
                const rawFrame = pixelsToFrame(
                  { x: pixelPosition.x, y: pixelPosition.y, width: currentPixels.width, height: currentPixels.height },
                  layout.referenceCanvas,
                  stagePixelSize,
                );
                // An active alignment guide already placed this slot exactly on another slot's/
                // the stage's edge — layering the 1%-grid snap on top of that could nudge it back
                // off by a pixel or two, so it's skipped for this drag when a guide was engaged.
                const wasGuideSnapped = alignEnabled && guidesActiveRef.current;
                updateSlotFrame(studioLayout.key, slot.id, wasGuideSnapped ? rawFrame : snapFrame(rawFrame, layout.referenceCanvas, snapEnabled));
                guidesActiveRef.current = false;
                setAlignmentGuides([]);
              }}
              onTransformEnd={(node) => {
                const scaleX = node.scaleX();
                const scaleY = node.scaleY();
                const newWidth = Math.max(8, node.width() * scaleX);
                const newHeight = Math.max(8, node.height() * scaleY);
                // § 5 — never persist Konva's own scale; bake it into width/height and reset to 1.
                node.scaleX(1);
                node.scaleY(1);
                node.width(newWidth);
                node.height(newHeight);
                const rawFrame = pixelsToFrame(
                  { x: node.x(), y: node.y(), width: newWidth, height: newHeight },
                  layout.referenceCanvas,
                  stagePixelSize,
                );
                updateSlotFrame(studioLayout.key, slot.id, snapFrame(rawFrame, layout.referenceCanvas, snapEnabled));
              }}
            />
          ))}
          <SlotTransformer selectedNode={selectedNode} />
          {alignEnabled &&
            alignmentGuides.map((guide, index) => (
              <Line
                key={index}
                points={
                  guide.orientation === "V"
                    ? [guide.position, 0, guide.position, stageHeight]
                    : [0, guide.position, stageWidth, guide.position]
                }
                stroke="#ff3d81"
                strokeWidth={1}
                dash={[4, 6]}
                listening={false}
              />
            ))}
        </Layer>
      </Stage>
    </div>
  );
}
