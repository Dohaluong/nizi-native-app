import type { AlbumSlotOrientation } from "../domain/albumLayout";

/** § 15 — L / P / S / A badge letters for the 4 real orientation values. */
export function orientationBadgeLetter(orientation: AlbumSlotOrientation): string {
  switch (orientation) {
    case "landscape":
      return "L";
    case "portrait":
      return "P";
    case "square":
      return "S";
    case "any":
      return "A";
  }
}

export function OrientationBadge({ orientation }: { orientation: AlbumSlotOrientation }) {
  return <span className="orientation-badge" title={orientation}>{orientationBadgeLetter(orientation)}</span>;
}
