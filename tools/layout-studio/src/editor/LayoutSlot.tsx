import { forwardRef, useEffect, useState } from "react";
import Konva from "konva";
import { Group, Image as KonvaImage, Rect, Text } from "react-konva";
import type { AlbumLayoutSlot, AlbumReferenceCanvas, AlbumSlotGradientOverlay } from "../domain/albumLayout";
import { frameToPixels } from "../services/normalizeGeometry";
import type { PreviewPhoto } from "../preview/LocalPhotoProvider";
import { orientationBadgeLetter } from "../components/OrientationBadge";

/** § user request — "phần ảnh cho phép chọn option gradient đen trong suốt, mục đích làm nền cho
 * chữ. Cho phép tuỳ chọn gradien từ trái phải trên dưới, độ % gradient ... Có thêm opacity của
 * gradien nữa": mirrors `AlbumPhotoSlotView.swift`'s own `gradientStops`/edge math exactly — Konva
 * just wants pixel start/end points (establishing the gradient's own axis) plus a flat
 * `[fraction, color, fraction, color, ...]` stop list, rather than SwiftUI's `UnitPoint`/
 * `Gradient.Stop` types. */
function gradientLinePoints(overlay: AlbumSlotGradientOverlay, width: number, height: number) {
  switch (overlay.edge) {
    case "top":
    case "bottom":
      return { start: { x: 0, y: 0 }, end: { x: 0, y: height } };
    case "left":
    case "right":
      return { start: { x: 0, y: 0 }, end: { x: width, y: 0 } };
  }
}

function gradientColorStops(overlay: AlbumSlotGradientOverlay): (number | string)[] {
  const extent = Math.min(Math.max(overlay.extentPercent / 100, 0), 1);
  const dark = `rgba(0, 0, 0, ${Math.min(Math.max(overlay.opacity, 0), 1)})`;
  const clear = "rgba(0, 0, 0, 0)";
  switch (overlay.edge) {
    case "top":
    case "left":
      return [0, dark, extent, clear, 1, clear];
    case "bottom":
    case "right":
      return [0, clear, 1 - extent, clear, 1, dark];
  }
}

/** Loads a plain `HTMLImageElement` from a blob URL for `<Image>` (react-konva doesn't ship its
 * own image-loading hook, and the spec's dependency list (§ 3) doesn't include the common
 * `use-image` helper package, so this is a small local equivalent). */
function useHtmlImage(url: string | undefined): HTMLImageElement | undefined {
  const [image, setImage] = useState<HTMLImageElement | undefined>(undefined);
  useEffect(() => {
    if (!url) {
      setImage(undefined);
      return;
    }
    const img = new window.Image();
    img.src = url;
    img.onload = () => setImage(img);
    return () => setImage(undefined);
  }, [url]);
  return image;
}

interface Props {
  slot: AlbumLayoutSlot;
  canvas: AlbumReferenceCanvas;
  stagePixelSize: { width: number; height: number };
  isSelected: boolean;
  previewPhoto?: PreviewPhoto;
  onSelect: () => void;
  /** Fires continuously while dragging, before `onDragEnd` — only wired up when alignment guides
   * are enabled (`LayoutCanvas` passes `undefined` otherwise), since it's the hook that lets the
   * parent snap this node's live position to other slots'/the stage's edges. */
  onDragMove?: (node: Konva.Group) => void;
  onDragEnd: (pixelPosition: { x: number; y: number }) => void;
  onTransformEnd: (node: Konva.Group) => void;
}

export const LayoutSlot = forwardRef<Konva.Group, Props>(function LayoutSlot(
  { slot, canvas, stagePixelSize, isSelected, previewPhoto, onSelect, onDragMove, onDragEnd, onTransformEnd },
  ref,
) {
  const pixels = frameToPixels(slot.frame, canvas, stagePixelSize);
  const image = useHtmlImage(previewPhoto?.url);
  const cornerRadiusPx = (slot.cornerRadius / canvas.width) * stagePixelSize.width;
  const gradientLine = slot.gradientOverlay ? gradientLinePoints(slot.gradientOverlay, pixels.width, pixels.height) : null;

  // `contentMode: "fill"` (cover) vs `"fit"` (contain) — the same crop-vs-letterbox distinction
  // AlbumSlotContentMode.swift documents, computed against the slot's own pixel size so a
  // preview photo never distorts.
  const imageDraw = (() => {
    if (!image) return null;
    const slotRatio = pixels.width / pixels.height;
    const imageRatio = image.width / image.height;
    let drawWidth = pixels.width;
    let drawHeight = pixels.height;
    if (slot.contentMode === "fill" ? imageRatio > slotRatio : imageRatio < slotRatio) {
      drawHeight = pixels.height;
      drawWidth = pixels.height * imageRatio;
    } else {
      drawWidth = pixels.width;
      drawHeight = pixels.width / imageRatio;
    }
    return { width: drawWidth, height: drawHeight, x: (pixels.width - drawWidth) / 2, y: (pixels.height - drawHeight) / 2 };
  })();

  return (
    <Group
      ref={ref}
      id={slot.id}
      x={pixels.x}
      y={pixels.y}
      width={pixels.width}
      height={pixels.height}
      draggable
      onClick={onSelect}
      onTap={onSelect}
      onDragMove={onDragMove ? (e) => onDragMove(e.target as Konva.Group) : undefined}
      onDragEnd={(e) => onDragEnd({ x: e.target.x(), y: e.target.y() })}
      onTransformEnd={(e) => onTransformEnd(e.target as Konva.Group)}
    >
      <Rect width={pixels.width} height={pixels.height} fill={image ? undefined : "#d9dde3"} cornerRadius={cornerRadiusPx} />
      {image && imageDraw && (
        <Group
          clipFunc={(ctx: Konva.Context) => {
            const r = Math.min(cornerRadiusPx, pixels.width / 2, pixels.height / 2);
            ctx.beginPath();
            ctx.moveTo(r, 0);
            ctx.arcTo(pixels.width, 0, pixels.width, pixels.height, r);
            ctx.arcTo(pixels.width, pixels.height, 0, pixels.height, r);
            ctx.arcTo(0, pixels.height, 0, 0, r);
            ctx.arcTo(0, 0, pixels.width, 0, r);
            ctx.closePath();
          }}
        >
          <KonvaImage image={image} x={imageDraw.x} y={imageDraw.y} width={imageDraw.width} height={imageDraw.height} />
        </Group>
      )}
      {slot.gradientOverlay && gradientLine && (
        <Rect
          width={pixels.width}
          height={pixels.height}
          cornerRadius={cornerRadiusPx}
          listening={false}
          fillLinearGradientStartPoint={gradientLine.start}
          fillLinearGradientEndPoint={gradientLine.end}
          fillLinearGradientColorStops={gradientColorStops(slot.gradientOverlay)}
        />
      )}
      <Rect
        width={pixels.width}
        height={pixels.height}
        cornerRadius={cornerRadiusPx}
        stroke={isSelected ? "#2f6fed" : "#ffffff80"}
        strokeWidth={isSelected ? 2.5 : 1}
      />
      <Group x={6} y={6} listening={false}>
        <Rect width={20} height={18} fill="#00000099" cornerRadius={4} />
        <Text text={orientationBadgeLetter(slot.preferredOrientation)} width={20} height={18} align="center" verticalAlign="middle" fontSize={11} fontStyle="bold" fill="#ffffff" />
      </Group>
    </Group>
  );
});
