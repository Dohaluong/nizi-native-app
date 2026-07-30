import type { AlbumSlotOrientation } from "../domain/albumLayout";
import { classifyOrientationFromSize } from "../services/classifyOrientation";

/** A locally-picked preview photo — `url` is a `URL.createObjectURL(file)` blob URL, never
 * uploaded anywhere (§ 16) and never persisted to localStorage (§ 24: "Không autosave ảnh local
 * dạng blob"). Lives only for this browser tab's session. */
export interface PreviewPhoto {
  id: string;
  url: string;
  naturalWidth: number;
  naturalHeight: number;
  orientation: "landscape" | "portrait" | "square";
}

/** Reads `naturalWidth`/`naturalHeight` off a real `<img>` load — the only reliable way to get
 * pixel dimensions from a `File` in the browser without a server round-trip. */
function loadImageDimensions(url: string): Promise<{ width: number; height: number }> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve({ width: img.naturalWidth, height: img.naturalHeight });
    img.onerror = () => reject(new Error("Could not read image dimensions"));
    img.src = url;
  });
}

export async function loadPreviewPhotos(files: FileList | File[]): Promise<PreviewPhoto[]> {
  const list = Array.from(files).filter((file) => file.type.startsWith("image/"));
  const results: PreviewPhoto[] = [];
  for (const file of list) {
    const url = URL.createObjectURL(file);
    try {
      const { width, height } = await loadImageDimensions(url);
      results.push({
        id: `${file.name}-${file.lastModified}-${width}x${height}`,
        url,
        naturalWidth: width,
        naturalHeight: height,
        orientation: classifyOrientationFromSize(width, height),
      });
    } catch {
      URL.revokeObjectURL(url);
    }
  }
  return results;
}

export function revokePreviewPhotos(photos: PreviewPhoto[]): void {
  for (const photo of photos) URL.revokeObjectURL(photo.url);
}

/** § 17 — assigns photos to slots preferring an orientation match, never re-implementing the
 * real Album Planner's scoring (that stays Swift-only, per § 17/§ 28: "Không đưa Planner scoring
 * từ Swift sang TypeScript"). This is a one-photo-per-slot preview helper, nothing more:
 *  - landscape slot → prefers a landscape photo
 *  - portrait slot → prefers a portrait photo
 *  - square slot → prefers square, then falls back to landscape/portrait
 *  - any slot → whatever's left
 * Each photo is used at most once across the whole layout (falls back to placeholder slots once
 * photos run out — the caller renders `undefined` as an empty slot). */
export function assignPreviewPhotos(
  slots: { id: string; preferredOrientation: AlbumSlotOrientation }[],
  photos: PreviewPhoto[],
): Map<string, PreviewPhoto> {
  const remaining = [...photos];
  const assignment = new Map<string, PreviewPhoto>();

  const takeMatching = (predicate: (photo: PreviewPhoto) => boolean): PreviewPhoto | undefined => {
    const index = remaining.findIndex(predicate);
    if (index === -1) return undefined;
    return remaining.splice(index, 1)[0];
  };

  for (const slot of slots) {
    let photo: PreviewPhoto | undefined;
    switch (slot.preferredOrientation) {
      case "landscape":
        photo = takeMatching((p) => p.orientation === "landscape") ?? takeMatching(() => true);
        break;
      case "portrait":
        photo = takeMatching((p) => p.orientation === "portrait") ?? takeMatching(() => true);
        break;
      case "square":
        photo =
          takeMatching((p) => p.orientation === "square") ??
          takeMatching((p) => p.orientation === "landscape") ??
          takeMatching((p) => p.orientation === "portrait");
        break;
      case "any":
      default:
        photo = takeMatching(() => true);
        break;
    }
    if (photo) assignment.set(slot.id, photo);
  }

  return assignment;
}
