import { useEffect, useState } from "react";
import { Toolbar } from "./components/Toolbar";
import { ValidationPanel } from "./components/ValidationPanel";
import { LayoutLibraryPanel } from "./panels/LayoutLibraryPanel";
import { LayoutInspector } from "./panels/LayoutInspector";
import { SlotInspector } from "./panels/SlotInspector";
import { PhotoPreviewPanel } from "./panels/PhotoPreviewPanel";
import { LayoutCanvas } from "./editor/LayoutCanvas";
import { useLayoutStudioStore } from "./store/layoutStudioStore";

/** § 8 — desktop-first, 3-column: Layout Library | Canvas Editor | Inspector. */
export default function App() {
  const loadAutosaveIfAny = useLayoutStudioStore((s) => s.loadAutosaveIfAny);
  const selectedLayout = useLayoutStudioStore((s) => s.selectedLayout());
  const selectedSlotId = useLayoutStudioStore((s) => s.selectedSlotId);
  const [showGrid, setShowGrid] = useState(true);
  const [alignEnabled, setAlignEnabled] = useState(true);

  useEffect(() => {
    loadAutosaveIfAny();
    // Runs once on mount only — re-running on every render would clobber in-progress edits with
    // whatever was last autosaved.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const selectedSlot = selectedLayout?.layout.slots.find((slot) => slot.id === selectedSlotId);

  return (
    <div className="app">
      <header className="app-title-bar">
        <h1>Nizi Layout Studio</h1>
        <span className="app-subtitle">Internal authoring tool — not part of the iOS app runtime.</span>
      </header>

      <Toolbar
        showGrid={showGrid}
        onToggleGrid={() => setShowGrid((v) => !v)}
        alignEnabled={alignEnabled}
        onToggleAlign={() => setAlignEnabled((v) => !v)}
      />

      <div className="app-body">
        <LayoutLibraryPanel />

        <div className="canvas-column">
          {selectedLayout ? (
            <>
              <LayoutCanvas studioLayout={selectedLayout} showGrid={showGrid} alignEnabled={alignEnabled} />
              <PhotoPreviewPanel />
              <ValidationPanel />
            </>
          ) : (
            <div className="canvas-empty-state">
              <p>Select a layout from the library, or import/create one to get started.</p>
            </div>
          )}
        </div>

        <div className="inspector-column">
          {selectedLayout ? (
            <>
              <LayoutInspector studioLayout={selectedLayout} />
              {selectedSlot && <SlotInspector layoutId={selectedLayout.layout.id} slot={selectedSlot} />}
            </>
          ) : (
            <div className="panel inspector-panel inspector-empty">No layout selected.</div>
          )}
        </div>
      </div>
    </div>
  );
}
