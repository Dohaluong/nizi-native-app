import { useEffect, useMemo, useRef, useState } from "react";
import Konva from "konva";
import { Layer, Stage } from "react-konva";
import type { StudioLayout } from "../domain/studioLayout";
import { frameToPixels, pixelsToFrame, snapFrame } from "../services/normalizeGeometry";
import { assignPreviewPhotos } from "../preview/LocalPhotoProvider";
import { useLayoutStudioStore } from "../store/layoutStudioStore";
import { CanvasBackground } from "./CanvasBackground";
import { GridLayer } from "./GridLayer";
import { LayoutSlot } from "./LayoutSlot";
import { SlotTransformer } from "./SlotTransformer";

const MAX_STAGE_SIZE = 640;

interface Props {
  studioLayout: StudioLayout;
  showGrid: boolean;
}

/** § 11 — the Page canvas. Scales to fit the editor area while keeping `referenceCanvas`'s own
 * aspect ratio (never a hardcoded square — § 11: "Nếu schema hiện tại có page aspect ratio thì
 * lấy từ schema thật"). */
export function LayoutCanvas({ studioLayout, showGrid }: Props) {
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

  const nodeRefs = useRef<Record<string, Konva.Group | null>>({});
  const [, forceRerender] = useState(0);
  const selectedNode = selectedSlotId ? nodeRefs.current[selectedSlotId] ?? null : null;

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
        deleteSlot(layout.id, selectedSlotId);
      } else if (event.key === "Escape") {
        selectSlot(null);
      } else if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "d") {
        event.preventDefault();
        duplicateSlot(layout.id, selectedSlotId);
      } else if (event.key.startsWith("Arrow")) {
        event.preventDefault();
        const step = event.shiftKey ? 5 : 1;
        const dx = event.key === "ArrowLeft" ? -step : event.key === "ArrowRight" ? step : 0;
        const dy = event.key === "ArrowUp" ? -step : event.key === "ArrowDown" ? step : 0;
        nudgeSlot(layout.id, selectedSlotId, dx, dy);
      }
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [selectedSlotId, layout.id, deleteSlot, duplicateSlot, nudgeSlot, selectSlot]);

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
              ref={(node) => {
                nodeRefs.current[slot.id] = node;
                forceRerender((n) => n + 1);
              }}
              slot={slot}
              canvas={layout.referenceCanvas}
              stagePixelSize={stagePixelSize}
              isSelected={slot.id === selectedSlotId}
              previewPhoto={photoAssignment.get(slot.id)}
              onSelect={() => selectSlot(slot.id)}
              onDragEnd={(pixelPosition) => {
                const currentPixels = frameToPixels(slot.frame, layout.referenceCanvas, stagePixelSize);
                const rawFrame = pixelsToFrame(
                  { x: pixelPosition.x, y: pixelPosition.y, width: currentPixels.width, height: currentPixels.height },
                  layout.referenceCanvas,
                  stagePixelSize,
                );
                updateSlotFrame(layout.id, slot.id, snapFrame(rawFrame, layout.referenceCanvas, snapEnabled));
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
                updateSlotFrame(layout.id, slot.id, snapFrame(rawFrame, layout.referenceCanvas, snapEnabled));
              }}
            />
          ))}
          <SlotTransformer selectedNode={selectedNode} />
        </Layer>
      </Stage>
    </div>
  );
}
