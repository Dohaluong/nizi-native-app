import type { AlbumLayoutFrame, AlbumReferenceCanvas } from "../domain/albumLayout";

/**
 * Geometry lives on-disk in `referenceCanvas` absolute units (e.g. `0...1000`), not normalized
 * `0...1` — see the unit note in `domain/albumLayout.ts`. These helpers convert between that and
 * whatever pixel size the Konva `<Stage>` is actually rendered at, treating `referenceCanvas.
 * width/height` as the scale factor (the spec's own § 5 assumed that factor was always 1; the
 * real schema's isn't).
 */

export function frameToPixels(
  frame: AlbumLayoutFrame,
  canvas: AlbumReferenceCanvas,
  stagePixelSize: { width: number; height: number },
): { x: number; y: number; width: number; height: number } {
  const scaleX = stagePixelSize.width / canvas.width;
  const scaleY = stagePixelSize.height / canvas.height;
  return {
    x: frame.x * scaleX,
    y: frame.y * scaleY,
    width: frame.width * scaleX,
    height: frame.height * scaleY,
  };
}

export function pixelsToFrame(
  pixels: { x: number; y: number; width: number; height: number },
  canvas: AlbumReferenceCanvas,
  stagePixelSize: { width: number; height: number },
): AlbumLayoutFrame {
  const scaleX = canvas.width / stagePixelSize.width;
  const scaleY = canvas.height / stagePixelSize.height;
  return {
    x: pixels.x * scaleX,
    y: pixels.y * scaleY,
    width: pixels.width * scaleX,
    height: pixels.height * scaleY,
  };
}

/** § 12 of the spec — a slot must never have non-positive size or sit fully/partially outside
 * the page. Clamps in reference-canvas units (not pixels), applied right after every drag/resize
 * and every manual Inspector edit. */
export function clampFrame(frame: AlbumLayoutFrame, canvas: AlbumReferenceCanvas): AlbumLayoutFrame {
  const width = Math.min(Math.max(frame.width, 1), canvas.width);
  const height = Math.min(Math.max(frame.height, 1), canvas.height);
  const x = Math.min(Math.max(frame.x, 0), canvas.width - width);
  const y = Math.min(Math.max(frame.y, 0), canvas.height - height);
  return { x, y, width, height };
}

/** § 13 — default snap increment is 1% of the page (`0.01` of `referenceCanvas`, not a fixed
 * pixel amount, so it stays meaningful regardless of a layout's own canvas size). */
export function snapValue(value: number, canvasDimension: number, snapEnabled: boolean): number {
  if (!snapEnabled) return value;
  const increment = canvasDimension * 0.01;
  return Math.round(value / increment) * increment;
}

export function snapFrame(frame: AlbumLayoutFrame, canvas: AlbumReferenceCanvas, snapEnabled: boolean): AlbumLayoutFrame {
  if (!snapEnabled) return frame;
  return {
    x: snapValue(frame.x, canvas.width, true),
    y: snapValue(frame.y, canvas.height, true),
    width: snapValue(frame.width, canvas.width, true),
    height: snapValue(frame.height, canvas.height, true),
  };
}

/** § 13 — round to at most 3 decimal places before export/display, so e.g. `103.72891234`
 * (float drift from repeated drag conversions) becomes a clean `103.729`, matching the real
 * `album-layouts.json`'s own whole-number style whenever the underlying value actually is one. */
export function roundGeometry(value: number): number {
  return Math.round(value * 1000) / 1000;
}

export function roundFrame(frame: AlbumLayoutFrame): AlbumLayoutFrame {
  return {
    x: roundGeometry(frame.x),
    y: roundGeometry(frame.y),
    width: roundGeometry(frame.width),
    height: roundGeometry(frame.height),
  };
}

/**
 * § user request — "1 trang ảnh vuông khi in ra thực tế sẽ tương đương 20x20cm, nên tôi cần cỡ
 * chữ thể hiện tương ứng": the one fixed physical anchor every `referenceCanvas` in this app
 * already implies (`DEFAULT_REFERENCE_CANVAS.square == 1000×1000`, portrait/landscape scale the
 * same canvas-units-per-cm ratio against their own longer edge) — `1000` canvas units along a
 * page's shorter edge is always `20`cm physically, regardless of format. `AlbumTextBlock.fontSize`
 * is stored/rendered in these same canvas units (same space as `frame`), which don't mean
 * anything on their own — the Studio's own Inspector and the iOS app's text-edit screen both show
 * this converted to real print points instead (1cm == 28.3465pt), so typing "24" means the same
 * actual 24pt caption on the printed page in both places.
 */
const CANVAS_UNITS_PER_CM = 1000 / 20;
const POINTS_PER_CM = 28.3465;
const CANVAS_UNITS_PER_POINT = CANVAS_UNITS_PER_CM / POINTS_PER_CM;

export function fontSizeToPoints(canvasUnits: number): number {
  return canvasUnits / CANVAS_UNITS_PER_POINT;
}

export function pointsToFontSize(points: number): number {
  return points * CANVAS_UNITS_PER_POINT;
}
