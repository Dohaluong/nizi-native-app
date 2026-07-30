import { useRef, useState } from "react";
import { useLayoutStudioStore } from "../store/layoutStudioStore";
import { exportLayoutLibrary } from "../services/exportLayoutLibrary";
import { downloadJson } from "../services/downloadJson";
import { PRODUCTION_EXPORT_FILENAME, STUDIO_PROJECT_FILENAME, type StudioProject } from "../domain/studioLayout";

interface Props {
  showGrid: boolean;
  onToggleGrid: () => void;
  alignEnabled: boolean;
  onToggleAlign: () => void;
}

/** § 8 toolbar actions: Import JSON, Validate, Export JSON, plus Snap/Grid/Align toggles and
 * Studio project Save/Open/Reset (§ 22/§ 23/§ 24). "New Layout"/"Duplicate"/"Delete"/"Add Slot"
 * live on `LayoutLibraryPanel`/`LayoutInspector` instead, next to the layout they act on. */
export function Toolbar({ showGrid, onToggleGrid, alignEnabled, onToggleAlign }: Props) {
  const snapEnabled = useLayoutStudioStore((s) => s.snapEnabled);
  const toggleSnap = useLayoutStudioStore((s) => s.toggleSnap);
  const layouts = useLayoutStudioStore((s) => s.layouts);
  const issues = useLayoutStudioStore((s) => s.issues);
  const importError = useLayoutStudioStore((s) => s.importError);
  const importLibraryFromText = useLayoutStudioStore((s) => s.importLibraryFromText);
  const runValidation = useLayoutStudioStore((s) => s.runValidation);
  const saveStudioProject = useLayoutStudioStore((s) => s.saveStudioProject);
  const openStudioProject = useLayoutStudioStore((s) => s.openStudioProject);
  const resetStudio = useLayoutStudioStore((s) => s.resetStudio);

  const importJsonRef = useRef<HTMLInputElement>(null);
  const openProjectRef = useRef<HTMLInputElement>(null);
  const [exportMessage, setExportMessage] = useState<string | null>(null);
  const [showResetConfirm, setShowResetConfirm] = useState(false);

  const hasErrors = issues.some((issue) => issue.level === "error");

  async function handleImportFile(file: File | undefined) {
    if (!file) return;
    const text = await file.text();
    importLibraryFromText(text);
  }

  async function handleOpenProjectFile(file: File | undefined) {
    if (!file) return;
    const text = await file.text();
    try {
      const project = JSON.parse(text) as StudioProject;
      openStudioProject(project);
    } catch (error) {
      setExportMessage(`Could not open Studio project: ${(error as Error).message}`);
    }
  }

  function handleExport() {
    const result = exportLayoutLibrary(layouts);
    if (result.blocked || !result.library) {
      setExportMessage(`Export blocked — fix ${result.issues.filter((i) => i.level === "error").length} error(s) first.`);
      return;
    }
    downloadJson(PRODUCTION_EXPORT_FILENAME, result.library);
    setExportMessage(`Exported ${result.library.layouts.length} layout(s) to ${PRODUCTION_EXPORT_FILENAME}.`);
  }

  function handleSaveProject() {
    downloadJson(STUDIO_PROJECT_FILENAME, saveStudioProject());
  }

  return (
    <div className="toolbar">
      <div className="toolbar-group">
        <button onClick={() => importJsonRef.current?.click()}>Import App JSON</button>
        <input ref={importJsonRef} type="file" accept="application/json,.json" style={{ display: "none" }} onChange={(e) => handleImportFile(e.target.files?.[0])} />

        <button onClick={runValidation}>Validate</button>

        <button className="primary" disabled={hasErrors || layouts.length === 0} onClick={handleExport} title={hasErrors ? "Fix all errors before exporting" : undefined}>
          Export App JSON
        </button>
      </div>

      <div className="toolbar-group">
        <label className="checkbox-inline">
          <input type="checkbox" checked={snapEnabled} onChange={toggleSnap} /> Snap
        </label>
        <label className="checkbox-inline">
          <input type="checkbox" checked={showGrid} onChange={onToggleGrid} /> Grid
        </label>
        <label className="checkbox-inline" title="Snap to other slots' edges/centers and the page's edges/center while dragging">
          <input type="checkbox" checked={alignEnabled} onChange={onToggleAlign} /> Align
        </label>
      </div>

      <div className="toolbar-group">
        <button onClick={handleSaveProject}>Save Studio Project</button>
        <button onClick={() => openProjectRef.current?.click()}>Open Studio Project</button>
        <input ref={openProjectRef} type="file" accept="application/json,.json" style={{ display: "none" }} onChange={(e) => handleOpenProjectFile(e.target.files?.[0])} />
        <button className="danger" onClick={() => setShowResetConfirm(true)}>Reset Studio</button>
      </div>

      {showResetConfirm && (
        <div className="toolbar-confirm">
          <span>Reset Studio? This clears every layout (production files you've already exported are unaffected).</span>
          <button
            className="danger"
            onClick={() => {
              resetStudio();
              setShowResetConfirm(false);
            }}
          >
            Reset
          </button>
          <button onClick={() => setShowResetConfirm(false)}>Cancel</button>
        </div>
      )}

      {(exportMessage || importError) && (
        <div className="toolbar-message">
          {importError ?? exportMessage}
        </div>
      )}
    </div>
  );
}
