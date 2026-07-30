import { useState } from "react";
import type { StudioLayout } from "../domain/studioLayout";
import type { AlbumPageFormat } from "../domain/albumLayout";
import { useLayoutStudioStore } from "../store/layoutStudioStore";

const ALL_FORMATS: AlbumPageFormat[] = ["square", "portrait", "landscape"];

interface Props {
  studioLayout: StudioLayout;
}

/** § 14 (layout-level half) — id (rename), name, nameKey, photoCount (read-only, driven by slot
 * count), supportedFormats, referenceCanvas, background color, plus Studio-only notes. */
export function LayoutInspector({ studioLayout }: Props) {
  const { layout, meta } = studioLayout;
  const allLayouts = useLayoutStudioStore((s) => s.layouts);
  const renameLayoutId = useLayoutStudioStore((s) => s.renameLayoutId);
  const updateLayoutMeta = useLayoutStudioStore((s) => s.updateLayoutMeta);
  const addSlot = useLayoutStudioStore((s) => s.addSlot);
  const addTextBlock = useLayoutStudioStore((s) => s.addTextBlock);
  const setLayoutFormat = useLayoutStudioStore((s) => s.setLayoutFormat);
  const setLayoutBackgroundColor = useLayoutStudioStore((s) => s.setLayoutBackgroundColor);
  const [idDraft, setIdDraft] = useState(layout.id);

  function commitId() {
    const trimmed = idDraft.trim();
    if (trimmed && trimmed !== layout.id) renameLayoutId(studioLayout.key, trimmed);
    else setIdDraft(layout.id);
  }

  // Every store action already addresses this exact layout by its own stable `key`, never by
  // this id — so even while it's duplicated, editing/renaming *this* one specifically works and
  // never touches whichever other layout(s) share the text. This just makes the collision itself
  // visible right where the fix (typing a new id below) actually happens.
  const isDuplicateId = allLayouts.some((l) => l.key !== studioLayout.key && l.layout.id === layout.id);

  return (
    <div className="panel inspector-panel">
      <div className="panel-header"><h2>Layout</h2></div>

      <label>
        Layout ID
        <input value={idDraft} onChange={(e) => setIdDraft(e.target.value)} onBlur={commitId} />
      </label>
      {isDuplicateId && (
        <p className="field-warning">
          Another layout also uses id "{layout.id}" — production export requires every layout id to be unique. Type a
          different id above to fix just this one.
        </p>
      )}

      <div className="field-row">
        <span className="field-label">Photo count</span>
        <span className="field-value">{layout.photoCount} (= slot count)</span>
      </div>

      <label>
        Page format
        <select value={layout.supportedFormats[0] ?? "square"} onChange={(e) => setLayoutFormat(studioLayout.key, e.target.value as AlbumPageFormat)}>
          {ALL_FORMATS.map((format) => (
            <option key={format} value={format}>{format}</option>
          ))}
        </select>
      </label>
      <p className="field-hint">
        Reference canvas: {layout.referenceCanvas.width} × {layout.referenceCanvas.height} (set automatically from the format above —
        the app requires the canvas's own aspect ratio to match its declared format).
      </p>

      <label>
        Background color
        <input type="color" value={layout.background.value} onChange={(e) => setLayoutBackgroundColor(studioLayout.key, e.target.value)} />
      </label>

      <div className="inspector-actions">
        <button onClick={() => addSlot(studioLayout.key)}>+ Add Slot</button>
        <button onClick={() => addTextBlock(studioLayout.key)}>+ Add Text Block</button>
      </div>

      <label>
        Notes (Studio-only)
        <textarea value={meta.notes} onChange={(e) => updateLayoutMeta(studioLayout.key, { notes: e.target.value })} rows={3} />
      </label>
      <label className="checkbox-inline">
        <input type="checkbox" checked={meta.favorite} onChange={(e) => updateLayoutMeta(studioLayout.key, { favorite: e.target.checked })} />
        Favorite (Studio-only)
      </label>
    </div>
  );
}
