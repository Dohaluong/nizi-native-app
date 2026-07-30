import { useState } from "react";
import type { AlbumPageFormat } from "../domain/albumLayout";
import { useLayoutStudioStore, slugify } from "../store/layoutStudioStore";

/** § 9/§ 10 — layouts grouped by `photoCount` (1/2/3/4 Photos), each with select/duplicate/
 * delete, plus a small "New Layout" form (photoCount + id, § 10). */
export function LayoutLibraryPanel() {
  const layouts = useLayoutStudioStore((s) => s.layouts);
  const selectedLayoutId = useLayoutStudioStore((s) => s.selectedLayoutId);
  const selectLayout = useLayoutStudioStore((s) => s.selectLayout);
  const duplicateLayout = useLayoutStudioStore((s) => s.duplicateLayout);
  const deleteLayout = useLayoutStudioStore((s) => s.deleteLayout);
  const createLayout = useLayoutStudioStore((s) => s.createLayout);

  const [isCreating, setIsCreating] = useState(false);
  const [newPhotoCount, setNewPhotoCount] = useState(1);
  const [newName, setNewName] = useState("");
  const [newFormat, setNewFormat] = useState<AlbumPageFormat>("square");
  const [pendingDeleteId, setPendingDeleteId] = useState<string | null>(null);

  const grouped = new Map<number, typeof layouts>();
  for (const studioLayout of layouts) {
    const count = studioLayout.layout.photoCount;
    if (!grouped.has(count)) grouped.set(count, []);
    grouped.get(count)!.push(studioLayout);
  }
  const sortedCounts = Array.from(grouped.keys()).sort((a, b) => a - b);
  const existingIds = new Set(layouts.map((l) => l.layout.id));

  function submitNewLayout() {
    const baseId = `${newFormat}.${newPhotoCount}.${slugify(newName || "untitled")}`;
    const id = existingIds.has(baseId) ? `${baseId}-${Date.now()}` : baseId;
    createLayout(newPhotoCount, id, newFormat);
    setIsCreating(false);
    setNewName("");
  }

  return (
    <div className="panel library-panel">
      <div className="panel-header">
        <h2>Layout Library</h2>
        <button onClick={() => setIsCreating((v) => !v)}>{isCreating ? "Cancel" : "+ New"}</button>
      </div>

      {isCreating && (
        <div className="new-layout-form">
          <label>
            Photo count
            <select value={newPhotoCount} onChange={(e) => setNewPhotoCount(Number(e.target.value))}>
              {[1, 2, 3, 4].map((n) => (
                <option key={n} value={n}>{n}</option>
              ))}
            </select>
          </label>
          <label>
            Format
            <select value={newFormat} onChange={(e) => setNewFormat(e.target.value as AlbumPageFormat)}>
              <option value="square">square</option>
              <option value="portrait">portrait</option>
              <option value="landscape">landscape</option>
            </select>
          </label>
          <label>
            Variant name
            <input value={newName} onChange={(e) => setNewName(e.target.value)} placeholder="e.g. editorial01" />
          </label>
          <button className="primary" onClick={submitNewLayout}>Create</button>
        </div>
      )}

      {layouts.length === 0 && <p className="empty-hint">Import an album-layouts.json or create a new layout to begin.</p>}

      {sortedCounts.map((count) => (
        <div key={count} className="library-group">
          <h3>{count} Photo{count === 1 ? "" : "s"}</h3>
          {grouped.get(count)!.map((studioLayout) => (
            <div
              key={studioLayout.layout.id}
              className={`library-item ${studioLayout.layout.id === selectedLayoutId ? "selected" : ""}`}
              onClick={() => selectLayout(studioLayout.layout.id)}
            >
              <div className="library-item-thumb">
                <LayoutThumbnail slots={studioLayout.layout.slots} canvas={studioLayout.layout.referenceCanvas} />
              </div>
              <div className="library-item-info">
                <span className="library-item-id">{studioLayout.layout.id}</span>
                <span className="library-item-count">{studioLayout.layout.slots.length} slots</span>
              </div>
              <div className="library-item-actions">
                <button title="Duplicate" onClick={(e) => { e.stopPropagation(); duplicateLayout(studioLayout.layout.id); }}>⧉</button>
                <button title="Delete" onClick={(e) => { e.stopPropagation(); setPendingDeleteId(studioLayout.layout.id); }}>✕</button>
              </div>
              {pendingDeleteId === studioLayout.layout.id && (
                <div className="confirm-delete" onClick={(e) => e.stopPropagation()}>
                  <span>Delete "{studioLayout.layout.id}"?</span>
                  <button
                    className="danger"
                    onClick={() => {
                      deleteLayout(studioLayout.layout.id);
                      setPendingDeleteId(null);
                    }}
                  >
                    Delete
                  </button>
                  <button onClick={() => setPendingDeleteId(null)}>Cancel</button>
                </div>
              )}
            </div>
          ))}
        </div>
      ))}
    </div>
  );
}

/** A simple geometry-only thumbnail (no photos) — just rectangles at their real relative
 * position/size, so the library list is scannable without rendering a full canvas per row. */
function LayoutThumbnail({ slots, canvas }: { slots: { frame: { x: number; y: number; width: number; height: number } }[]; canvas: { width: number; height: number } }) {
  const size = 40;
  return (
    <svg width={size} height={size} viewBox={`0 0 ${canvas.width} ${canvas.height}`}>
      <rect x={0} y={0} width={canvas.width} height={canvas.height} fill="#eef0f3" />
      {slots.map((slot, index) => (
        <rect
          key={index}
          x={slot.frame.x}
          y={slot.frame.y}
          width={slot.frame.width}
          height={slot.frame.height}
          fill="#9fb4e8"
          stroke="#ffffff"
          strokeWidth={canvas.width * 0.01}
        />
      ))}
    </svg>
  );
}
