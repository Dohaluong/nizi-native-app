import { forwardRef } from "react";
import Konva from "konva";
import { Group, Rect, Text } from "react-konva";
import type { AlbumReferenceCanvas, AlbumTextBlock } from "../domain/albumLayout";
import { frameToPixels } from "../services/normalizeGeometry";

interface Props {
  textBlock: AlbumTextBlock;
  canvas: AlbumReferenceCanvas;
  stagePixelSize: { width: number; height: number };
  isSelected: boolean;
  onSelect: () => void;
  /** Same purpose as `LayoutSlot`'s own prop of the same name — see its doc comment. */
  onDragMove?: (node: Konva.Group) => void;
  onDragEnd: (pixelPosition: { x: number; y: number }) => void;
  onTransformEnd: (node: Konva.Group) => void;
}

const KONVA_HORIZONTAL_ALIGN: Record<AlbumTextBlock["horizontalAlignment"], string> = {
  left: "left",
  center: "center",
  right: "right",
};

const KONVA_VERTICAL_ALIGN: Record<AlbumTextBlock["verticalAlignment"], string> = {
  top: "top",
  center: "middle",
  bottom: "bottom",
};

/** § user request — "Regular, Italic, Bold, Underline": `"underline"` is a text *decoration*, not
 * a font style at all — Konva's own `<Text fontStyle>` only understands "normal"/"italic"/"bold"/
 * "italic bold", so underline goes through the separate `textDecoration` prop below instead. */
const KONVA_FONT_STYLE: Record<AlbumTextBlock["fontStyle"], string> = {
  regular: "normal",
  italic: "italic",
  bold: "bold",
  underline: "normal",
};

const KONVA_TEXT_DECORATION: Record<AlbumTextBlock["fontStyle"], string> = {
  regular: "",
  italic: "",
  bold: "",
  underline: "underline",
};

/** § user request — "sẽ có placeholder tương ứng: Toại title sẽ là: Title, loại subtitle sẽ là
 * Sub title, loại paragraph sẽ là Lorem ipsum...": mirrors `AlbumTextBlockKind.placeholderText`
 * (Swift side) exactly — deliberately fixed, unlocalized sample copy, not routed through i18n. */
const TEXT_KIND_PLACEHOLDER: Record<AlbumTextBlock["kind"], string> = {
  title: "Title",
  subtitle: "Sub title",
  paragraph: "Lorem ipsum dolor sit amet, consectetur adipiscing elit.",
};

/** § user request "Thêm chữ" — a text block's canvas presence, sibling to `LayoutSlot`. Always
 * previews `textBlock.kind`'s own placeholder — there's no per-Album text content yet, only the
 * layout template's own geometry/style (see `AlbumTextBlock`'s own doc comment, Swift side).
 * `fontFamily` is passed straight through as a CSS-ish font-family to Konva's `<Text>`, which is
 * only ever a *visual approximation* in this browser preview — the real, authoritative rendering
 * is `AlbumTextBlockView.swift`, resolved against actual iOS fonts via `UIFont`. */
export const TextBlockElement = forwardRef<Konva.Group, Props>(function TextBlockElement(
  { textBlock, canvas, stagePixelSize, isSelected, onSelect, onDragMove, onDragEnd, onTransformEnd },
  ref,
) {
  const pixels = frameToPixels(textBlock.frame, canvas, stagePixelSize);
  const fontSizePx = (textBlock.fontSize / canvas.width) * stagePixelSize.width;

  return (
    <Group
      ref={ref}
      id={textBlock.id}
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
      {/* § user request — "khung text giờ sẽ chỉ có khung là nét đứt, không có nền": dropped the
       * pale-yellow `fill` this used to have — just the dashed outline now, no visible background.
       * Still `fill="transparent"` (not omitted) rather than no fill at all: Konva only hit-tests
       * a shape's *interior* when it has a real fill, so dropping it entirely would leave only the
       * dashed line itself clickable/draggable instead of the whole box. */}
      <Rect
        width={pixels.width}
        height={pixels.height}
        fill="transparent"
        stroke={isSelected ? "#2f6fed" : "#ffffff80"}
        strokeWidth={isSelected ? 2.5 : 1}
        dash={[4, 3]}
      />
      <Text
        text={TEXT_KIND_PLACEHOLDER[textBlock.kind]}
        width={pixels.width}
        height={pixels.height}
        align={KONVA_HORIZONTAL_ALIGN[textBlock.horizontalAlignment]}
        verticalAlign={KONVA_VERTICAL_ALIGN[textBlock.verticalAlignment]}
        fontSize={fontSizePx}
        fontFamily={textBlock.fontFamily === "System" ? undefined : textBlock.fontFamily}
        fontStyle={KONVA_FONT_STYLE[textBlock.fontStyle]}
        textDecoration={KONVA_TEXT_DECORATION[textBlock.fontStyle]}
        fill={textBlock.textColor}
        padding={4}
        wrap="word"
        ellipsis
        listening={false}
      />
    </Group>
  );
});
