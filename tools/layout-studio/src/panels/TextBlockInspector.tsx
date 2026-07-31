import type { AlbumTextBlock } from "../domain/albumLayout";
import {
  ALBUM_TEXT_BLOCK_KINDS,
  ALBUM_TEXT_FONT_FAMILIES,
  ALBUM_TEXT_FONT_STYLES,
  ALBUM_TEXT_HORIZONTAL_ALIGNMENTS,
  ALBUM_TEXT_VERTICAL_ALIGNMENTS,
} from "../domain/albumLayout";
import { useLayoutStudioStore } from "../store/layoutStudioStore";
import { fontSizeToPoints, pointsToFontSize, roundGeometry } from "../services/normalizeGeometry";

interface Props {
  layoutKey: string;
  textBlock: AlbumTextBlock;
}

/** § user request "Thêm chữ" — mirrors `SlotInspector`'s own layout exactly (same X/Y/Width/Height
 * `geometry-grid`, same numeric-input-calls-the-same-action-the-canvas-uses pattern), swapping the
 * slot-specific fields (orientation/role/contentMode/cornerRadius) for the text block's own
 * (horizontal/vertical alignment, font family, size, style). */
export function TextBlockInspector({ layoutKey, textBlock }: Props) {
  const updateTextBlockFrame = useLayoutStudioStore((s) => s.updateTextBlockFrame);
  const updateTextBlock = useLayoutStudioStore((s) => s.updateTextBlock);
  const deleteTextBlock = useLayoutStudioStore((s) => s.deleteTextBlock);
  const duplicateTextBlock = useLayoutStudioStore((s) => s.duplicateTextBlock);

  function setFrameField(field: keyof AlbumTextBlock["frame"], value: number) {
    if (Number.isNaN(value)) return;
    updateTextBlockFrame(layoutKey, textBlock.id, { ...textBlock.frame, [field]: value });
  }

  return (
    <div className="panel inspector-panel">
      <div className="panel-header"><h2>Text Block</h2></div>

      <div className="field-row">
        <span className="field-label">Text Block ID</span>
        <span className="field-value">{textBlock.id}</span>
      </div>

      <div className="geometry-grid">
        <label>
          X
          <input type="number" value={roundGeometry(textBlock.frame.x)} onChange={(e) => setFrameField("x", Number(e.target.value))} />
        </label>
        <label>
          Y
          <input type="number" value={roundGeometry(textBlock.frame.y)} onChange={(e) => setFrameField("y", Number(e.target.value))} />
        </label>
        <label>
          Width
          <input type="number" value={roundGeometry(textBlock.frame.width)} onChange={(e) => setFrameField("width", Number(e.target.value))} />
        </label>
        <label>
          Height
          <input type="number" value={roundGeometry(textBlock.frame.height)} onChange={(e) => setFrameField("height", Number(e.target.value))} />
        </label>
      </div>

      {/* § user request — "cho phép chọn kiểu: Title/Sub-title/Paragraph. Dùng để trang trí văn
       * bản sau này": purely semantic for now (mirrors `SlotInspector`'s own `role` field) — not
       * wired up to any automatic font/size/weight preset yet. */}
      <label>
        Kind
        <select
          value={textBlock.kind}
          onChange={(e) => updateTextBlock(layoutKey, textBlock.id, { kind: e.target.value as AlbumTextBlock["kind"] })}
        >
          {ALBUM_TEXT_BLOCK_KINDS.map((kind) => (
            <option key={kind} value={kind}>{kind}</option>
          ))}
        </select>
      </label>

      <label>
        Horizontal alignment
        <select
          value={textBlock.horizontalAlignment}
          onChange={(e) => updateTextBlock(layoutKey, textBlock.id, { horizontalAlignment: e.target.value as AlbumTextBlock["horizontalAlignment"] })}
        >
          {ALBUM_TEXT_HORIZONTAL_ALIGNMENTS.map((alignment) => (
            <option key={alignment} value={alignment}>{alignment}</option>
          ))}
        </select>
      </label>

      <label>
        Vertical alignment
        <select
          value={textBlock.verticalAlignment}
          onChange={(e) => updateTextBlock(layoutKey, textBlock.id, { verticalAlignment: e.target.value as AlbumTextBlock["verticalAlignment"] })}
        >
          {ALBUM_TEXT_VERTICAL_ALIGNMENTS.map((alignment) => (
            <option key={alignment} value={alignment}>{alignment}</option>
          ))}
        </select>
      </label>

      <label>
        Font family
        <select
          value={textBlock.fontFamily}
          onChange={(e) => updateTextBlock(layoutKey, textBlock.id, { fontFamily: e.target.value as AlbumTextBlock["fontFamily"] })}
        >
          {ALBUM_TEXT_FONT_FAMILIES.map((family) => (
            <option key={family} value={family}>{family}</option>
          ))}
        </select>
      </label>

      <label>
        {/* § user request — "1 trang ảnh vuông khi in ra thực tế sẽ tương đương 20x20cm, nên tôi
         * cần cỡ chữ thể hiện tương ứng": shows/accepts real print points (see
         * `fontSizeToPoints`/`pointsToFontSize`'s own doc comment) rather than the raw
         * `referenceCanvas` unit `fontSize` is actually stored in — same conversion the iOS app's
         * own text-edit screen uses, so a value typed here means the same real-world size there. */}
        Font size (pt)
        <input
          type="number"
          min={1}
          value={roundGeometry(fontSizeToPoints(textBlock.fontSize))}
          onChange={(e) => {
            const value = Number(e.target.value);
            if (!Number.isNaN(value) && value > 0) updateTextBlock(layoutKey, textBlock.id, { fontSize: pointsToFontSize(value) });
          }}
        />
      </label>

      <label>
        Font style
        <select
          value={textBlock.fontStyle}
          onChange={(e) => updateTextBlock(layoutKey, textBlock.id, { fontStyle: e.target.value as AlbumTextBlock["fontStyle"] })}
        >
          {ALBUM_TEXT_FONT_STYLES.map((style) => (
            <option key={style} value={style}>{style}</option>
          ))}
        </select>
      </label>

      {/* § user request — "còn cần chọn màu chữ" */}
      <label>
        Text color
        <input
          type="color"
          value={textBlock.textColor}
          onChange={(e) => updateTextBlock(layoutKey, textBlock.id, { textColor: e.target.value })}
        />
      </label>

      <div className="inspector-actions">
        <button onClick={() => duplicateTextBlock(layoutKey, textBlock.id)}>Duplicate</button>
        <button className="danger" onClick={() => deleteTextBlock(layoutKey, textBlock.id)}>Delete</button>
      </div>
    </div>
  );
}
