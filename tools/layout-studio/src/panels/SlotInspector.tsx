import type { AlbumGradientEdge, AlbumLayoutSlot, AlbumSlotOrientation } from "../domain/albumLayout";
import { ALBUM_GRADIENT_EDGES, ALBUM_LAYOUT_SLOT_ROLES, ALBUM_SLOT_CONTENT_MODES, ALBUM_SLOT_ORIENTATIONS } from "../domain/albumLayout";
import { useLayoutStudioStore } from "../store/layoutStudioStore";
import { roundGeometry } from "../services/normalizeGeometry";

const DEFAULT_GRADIENT_EDGE: AlbumGradientEdge = "bottom";
const DEFAULT_GRADIENT_EXTENT_PERCENT = 30;
const DEFAULT_GRADIENT_OPACITY = 0.6;

interface Props {
  layoutKey: string;
  slot: AlbumLayoutSlot;
}

/** § 14 — Slot ID, X, Y, Width, Height, Preferred Orientation, all editable by hand with
 * validate/clamp/realtime-canvas-update (the numeric inputs call the exact same
 * `updateSlotFrame` action the canvas drag/resize handlers do, so both paths clamp identically). */
export function SlotInspector({ layoutKey, slot }: Props) {
  const updateSlotFrame = useLayoutStudioStore((s) => s.updateSlotFrame);
  const updateSlot = useLayoutStudioStore((s) => s.updateSlot);
  const deleteSlot = useLayoutStudioStore((s) => s.deleteSlot);
  const duplicateSlot = useLayoutStudioStore((s) => s.duplicateSlot);

  function setFrameField(field: keyof AlbumLayoutSlot["frame"], value: number) {
    if (Number.isNaN(value)) return;
    updateSlotFrame(layoutKey, slot.id, { ...slot.frame, [field]: value });
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
          onChange={(e) => updateSlot(layoutKey, slot.id, { preferredOrientation: e.target.value as AlbumSlotOrientation })}
        >
          {ALBUM_SLOT_ORIENTATIONS.map((orientation) => (
            <option key={orientation} value={orientation}>{orientation}</option>
          ))}
        </select>
      </label>

      <label>
        Role
        <select value={slot.role} onChange={(e) => updateSlot(layoutKey, slot.id, { role: e.target.value as AlbumLayoutSlot["role"] })}>
          {ALBUM_LAYOUT_SLOT_ROLES.map((role) => (
            <option key={role} value={role}>{role}</option>
          ))}
        </select>
      </label>

      <label>
        Content mode
        <select value={slot.contentMode} onChange={(e) => updateSlot(layoutKey, slot.id, { contentMode: e.target.value as AlbumLayoutSlot["contentMode"] })}>
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
            if (!Number.isNaN(value) && value >= 0) updateSlot(layoutKey, slot.id, { cornerRadius: value });
          }}
        />
      </label>

      {/* § user request — "phần ảnh cho phép chọn option gradient đen trong suốt, mục đích làm
       * nền cho chữ. Cho phép tuỳ chọn gradien từ trái phải trên dưới, độ % gradient ... Có thêm
       * opacity của gradien nữa": a dark gradient painted on top of this slot's photo, so a text
       * block over it stays legible. */}
      <label className="checkbox-inline">
        <input
          type="checkbox"
          checked={slot.gradientOverlay !== undefined}
          onChange={(e) =>
            updateSlot(layoutKey, slot.id, {
              gradientOverlay: e.target.checked
                ? { edge: DEFAULT_GRADIENT_EDGE, extentPercent: DEFAULT_GRADIENT_EXTENT_PERCENT, opacity: DEFAULT_GRADIENT_OPACITY }
                : undefined,
            })
          }
        />
        Gradient overlay (for text legibility)
      </label>

      {slot.gradientOverlay && (
        <>
          <label>
            Gradient edge
            <select
              value={slot.gradientOverlay.edge}
              onChange={(e) =>
                updateSlot(layoutKey, slot.id, {
                  gradientOverlay: { ...slot.gradientOverlay!, edge: e.target.value as AlbumGradientEdge },
                })
              }
            >
              {ALBUM_GRADIENT_EDGES.map((edge) => (
                <option key={edge} value={edge}>{edge}</option>
              ))}
            </select>
          </label>

          <div className="geometry-grid">
            <label>
              {/* § "Ví dụ 30%-Dưới thì khoảng gradien chuyển từ đen 100% về 0% trong 30% chiều
               * cao từ dưới lên": how much of the slot's own edge-to-edge dimension the fade
               * spans, starting at the chosen edge. */}
              Extent (%)
              <input
                type="number"
                min={0}
                max={100}
                value={roundGeometry(slot.gradientOverlay.extentPercent)}
                onChange={(e) => {
                  const value = Number(e.target.value);
                  if (!Number.isNaN(value)) {
                    updateSlot(layoutKey, slot.id, {
                      gradientOverlay: { ...slot.gradientOverlay!, extentPercent: Math.min(Math.max(value, 0), 100) },
                    });
                  }
                }}
              />
            </label>
            <label>
              Opacity (%)
              <input
                type="number"
                min={0}
                max={100}
                value={roundGeometry(slot.gradientOverlay.opacity * 100)}
                onChange={(e) => {
                  const value = Number(e.target.value);
                  if (!Number.isNaN(value)) {
                    updateSlot(layoutKey, slot.id, {
                      gradientOverlay: { ...slot.gradientOverlay!, opacity: Math.min(Math.max(value, 0), 100) / 100 },
                    });
                  }
                }}
              />
            </label>
          </div>
        </>
      )}

      <div className="inspector-actions">
        <button onClick={() => duplicateSlot(layoutKey, slot.id)}>Duplicate</button>
        <button className="danger" onClick={() => deleteSlot(layoutKey, slot.id)}>Delete</button>
      </div>
    </div>
  );
}
