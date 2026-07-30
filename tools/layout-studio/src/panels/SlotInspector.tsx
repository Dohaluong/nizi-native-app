import type { AlbumLayoutSlot, AlbumSlotOrientation } from "../domain/albumLayout";
import { ALBUM_LAYOUT_SLOT_ROLES, ALBUM_SLOT_CONTENT_MODES, ALBUM_SLOT_ORIENTATIONS } from "../domain/albumLayout";
import { useLayoutStudioStore } from "../store/layoutStudioStore";
import { roundGeometry } from "../services/normalizeGeometry";

interface Props {
  layoutId: string;
  slot: AlbumLayoutSlot;
}

/** § 14 — Slot ID, X, Y, Width, Height, Preferred Orientation, all editable by hand with
 * validate/clamp/realtime-canvas-update (the numeric inputs call the exact same
 * `updateSlotFrame` action the canvas drag/resize handlers do, so both paths clamp identically). */
export function SlotInspector({ layoutId, slot }: Props) {
  const updateSlotFrame = useLayoutStudioStore((s) => s.updateSlotFrame);
  const updateSlot = useLayoutStudioStore((s) => s.updateSlot);
  const deleteSlot = useLayoutStudioStore((s) => s.deleteSlot);
  const duplicateSlot = useLayoutStudioStore((s) => s.duplicateSlot);

  function setFrameField(field: keyof AlbumLayoutSlot["frame"], value: number) {
    if (Number.isNaN(value)) return;
    updateSlotFrame(layoutId, slot.id, { ...slot.frame, [field]: value });
  }

  return (
    <div className="panel inspector-panel">
      <div className="panel-header"><h2>Slot</h2></div>

      <div className="field-row">
        <span className="field-label">Slot ID</span>
        <span className="field-value">{slot.id}</span>
      </div>

      <div className="geometry-grid">
        <label>
          X
          <input type="number" value={roundGeometry(slot.frame.x)} onChange={(e) => setFrameField("x", Number(e.target.value))} />
        </label>
        <label>
          Y
          <input type="number" value={roundGeometry(slot.frame.y)} onChange={(e) => setFrameField("y", Number(e.target.value))} />
        </label>
        <label>
          Width
          <input type="number" value={roundGeometry(slot.frame.width)} onChange={(e) => setFrameField("width", Number(e.target.value))} />
        </label>
        <label>
          Height
          <input type="number" value={roundGeometry(slot.frame.height)} onChange={(e) => setFrameField("height", Number(e.target.value))} />
        </label>
      </div>

      <label>
        Preferred Orientation
        <select
          value={slot.preferredOrientation}
          onChange={(e) => updateSlot(layoutId, slot.id, { preferredOrientation: e.target.value as AlbumSlotOrientation })}
        >
          {ALBUM_SLOT_ORIENTATIONS.map((orientation) => (
            <option key={orientation} value={orientation}>{orientation}</option>
          ))}
        </select>
      </label>

      <label>
        Role
        <select value={slot.role} onChange={(e) => updateSlot(layoutId, slot.id, { role: e.target.value as AlbumLayoutSlot["role"] })}>
          {ALBUM_LAYOUT_SLOT_ROLES.map((role) => (
            <option key={role} value={role}>{role}</option>
          ))}
        </select>
      </label>

      <label>
        Content mode
        <select value={slot.contentMode} onChange={(e) => updateSlot(layoutId, slot.id, { contentMode: e.target.value as AlbumLayoutSlot["contentMode"] })}>
          {ALBUM_SLOT_CONTENT_MODES.map((mode) => (
            <option key={mode} value={mode}>{mode}</option>
          ))}
        </select>
      </label>

      <label>
        Corner radius
        <input
          type="number"
          min={0}
          value={roundGeometry(slot.cornerRadius)}
          onChange={(e) => {
            const value = Number(e.target.value);
            if (!Number.isNaN(value) && value >= 0) updateSlot(layoutId, slot.id, { cornerRadius: value });
          }}
        />
      </label>

      <div className="inspector-actions">
        <button onClick={() => duplicateSlot(layoutId, slot.id)}>Duplicate</button>
        <button className="danger" onClick={() => deleteSlot(layoutId, slot.id)}>Delete</button>
      </div>
    </div>
  );
}
