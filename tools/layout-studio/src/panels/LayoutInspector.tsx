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
  const renameLayoutId = useLayoutStudioStore((s) => s.renameLayoutId);
  const updateLayoutMeta = useLayoutStudioStore((s) => s.updateLayoutMeta);
  const addSlot = useLayoutStudioStore((s) => s.addSlot);
  const setLayoutFormat = useLayoutStudioStore((s) => s.setLayoutFormat);
  const setLayoutBackgroundColor = useLayoutStudioStore((s) => s.setLayoutBackgroundColor);
  const [idDraft, setIdDraft] = useState(layout.id);

  function commitId() {
    const trimmed = idDraft.trim();
    if (trimmed && trimmed !== layout.id) renameLayoutId(layout.id, trimmed);
    else setIdDraft(layout.id);
  }

  return (
    <div className="panel inspector-panel">
      <div className="panel-header"><h2>Layout</h2></div>

      <label>
        Layout ID
        <input value={idDraft} onChange={(e) => setIdDraft(e.target.value)} onBlur={commitId} />
      </label>

      <div className="field-row">
        <span className="field-label">Photo count</span>
        <span className="field-value">{layout.photoCount} (= slot count)</span>
      </div>

      <label>
        Page format
        <select value={layout.supportedFormats[0] ?? "square"} onChange={(e) => setLayoutFormat(layout.id, e.target.value as AlbumPageFormat)}>
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
        <input type="color" value={layout.background.value} onChange={(e) => setLayoutBackgroundColor(layout.id, e.target.value)} />
      </label>

      <button onClick={() => addSlot(layout.id)}>+ Add Slot</button>

      <label>
        Notes (Studio-only)
        <textarea value={meta.notes} onChange={(e) => updateLayoutMeta(layout.id, { notes: e.target.value })} rows={3} />
      </label>
      <label className="checkbox-inline">
        <input type="checkbox" checked={meta.favorite} onChange={(e) => updateLayoutMeta(layout.id, { favorite: e.target.checked })} />
        Favorite (Studio-only)
      </label>
    </div>
  );
}
