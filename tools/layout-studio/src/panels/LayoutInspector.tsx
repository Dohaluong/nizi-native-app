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
  const [idDraft, setIdDraft] = useState(layout.id);

  function commitId() {
    const trimmed = idDraft.trim();
    if (trimmed && trimmed !== layout.id) renameLayoutId(layout.id, trimmed);
    else setIdDraft(layout.id);
  }

  function toggleFormat(format: AlbumPageFormat) {
    const layouts = useLayoutStudioStore.getState().layouts;
    const current = layouts.find((l) => l.layout.id === layout.id);
    if (!current) return;
    const has = current.layout.supportedFormats.includes(format);
    const next = has
      ? current.layout.supportedFormats.filter((f) => f !== format)
      : [...current.layout.supportedFormats, format];
    useLayoutStudioStore.setState({
      layouts: layouts.map((l) => (l.layout.id === layout.id ? { ...l, layout: { ...l.layout, supportedFormats: next } } : l)),
    });
    useLayoutStudioStore.getState().runValidation();
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

      <div className="field-row">
        <span className="field-label">Reference canvas</span>
        <span className="field-value">{layout.referenceCanvas.width} × {layout.referenceCanvas.height}</span>
      </div>

      <label>
        Supported formats
        <div className="format-checkboxes">
          {ALL_FORMATS.map((format) => (
            <label key={format} className="checkbox-inline">
              <input type="checkbox" checked={layout.supportedFormats.includes(format)} onChange={() => toggleFormat(format)} />
              {format}
            </label>
          ))}
        </div>
      </label>

      <label>
        Background color
        <input
          type="color"
          value={layout.background.value}
          onChange={(e) => {
            const layouts = useLayoutStudioStore.getState().layouts;
            useLayoutStudioStore.setState({
              layouts: layouts.map((l) =>
                l.layout.id === layout.id ? { ...l, layout: { ...l.layout, background: { type: "solid", value: e.target.value } } } : l,
              ),
            });
          }}
        />
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
