import { useRef } from "react";
import { loadPreviewPhotos } from "../preview/LocalPhotoProvider";
import { useLayoutStudioStore } from "../store/layoutStudioStore";

/** § 16 — local-only photo picker (`URL.createObjectURL`, never uploaded), plus Shuffle/Clear.
 * Assignment into slots itself happens in `LayoutCanvas` (§ 17's orientation-preferring helper). */
export function PhotoPreviewPanel() {
  const previewPhotos = useLayoutStudioStore((s) => s.previewPhotos);
  const setPreviewPhotos = useLayoutStudioStore((s) => s.setPreviewPhotos);
  const clearPreviewPhotos = useLayoutStudioStore((s) => s.clearPreviewPhotos);
  const shufflePreview = useLayoutStudioStore((s) => s.shufflePreview);
  const inputRef = useRef<HTMLInputElement>(null);

  async function onFilesPicked(files: FileList | null) {
    if (!files || files.length === 0) return;
    const photos = await loadPreviewPhotos(files);
    setPreviewPhotos(photos);
  }

  return (
    <div className="photo-preview-panel">
      <input
        ref={inputRef}
        type="file"
        accept="image/*"
        multiple
        style={{ display: "none" }}
        onChange={(e) => onFilesPicked(e.target.files)}
      />
      <button onClick={() => inputRef.current?.click()}>Select Photos…</button>
      <button onClick={shufflePreview} disabled={previewPhotos.length === 0}>Shuffle Preview</button>
      <button onClick={clearPreviewPhotos} disabled={previewPhotos.length === 0}>Clear Photos</button>
      <span className="photo-count-hint">{previewPhotos.length} photo{previewPhotos.length === 1 ? "" : "s"} loaded (local only)</span>
    </div>
  );
}
