import type { AlbumLayoutLibrary, AlbumPageLayout } from "../domain/albumLayout";
import { SUPPORTED_SCHEMA_VERSION } from "../domain/albumLayout";

/** § 21 of the spec — errors block export, warnings don't. */
export interface ValidationIssue {
  level: "error" | "warning";
  code: string;
  message: string;
  layoutId?: string;
  slotId?: string;
}

const ASPECT_RATIO_TOLERANCE = 0.05; // matches AlbumLayoutValidator.squareRatioTolerance exactly

function aspectRatioMatchesFormat(canvas: { width: number; height: number }, format: string): boolean {
  const ratio = canvas.width / canvas.height;
  switch (format) {
    case "square":
      return Math.abs(ratio - 1.0) <= ASPECT_RATIO_TOLERANCE;
    case "portrait":
      return ratio < 1.0 - ASPECT_RATIO_TOLERANCE;
    case "landscape":
      return ratio > 1.0 + ASPECT_RATIO_TOLERANCE;
    default:
      return false;
  }
}

/** One layout's own rules — mirrors `AlbumLayoutValidator.validate(_ layout:)` in
 * `Nizi/Features/AlbumLayout/Domain/AlbumLayoutValidator.swift` field-for-field, plus the
 * Studio-only warnings § 21 asks for (overlap, tiny slots, tight margins). */
export function validateLayout(layout: AlbumPageLayout): ValidationIssue[] {
  const issues: ValidationIssue[] = [];
  const { id: layoutId } = layout;

  if (layout.photoCount < 1 || layout.photoCount > 4) {
    issues.push({
      level: "error",
      code: "invalidPhotoCount",
      message: `photoCount must be 1-4 (got ${layout.photoCount}).`,
      layoutId,
    });
  }
  if (layout.slots.length !== layout.photoCount) {
    issues.push({
      level: "error",
      code: "slotCountMismatch",
      message: `photoCount (${layout.photoCount}) must equal the number of slots (${layout.slots.length}).`,
      layoutId,
    });
  }
  if (!(layout.referenceCanvas.width > 0) || !(layout.referenceCanvas.height > 0)) {
    issues.push({ level: "error", code: "invalidCanvas", message: "referenceCanvas width/height must be > 0.", layoutId });
  }
  if (layout.supportedFormats.length === 0) {
    issues.push({ level: "error", code: "unsupportedFormat", message: "A layout must support at least one page format.", layoutId });
  }

  const seenSlotIds = new Set<string>();
  const seenOrders = new Set<number>();
  for (const slot of layout.slots) {
    if (seenSlotIds.has(slot.id)) {
      issues.push({ level: "error", code: "duplicateSlotId", message: `Duplicate slot id "${slot.id}".`, layoutId, slotId: slot.id });
    }
    seenSlotIds.add(slot.id);

    if (seenOrders.has(slot.order)) {
      issues.push({ level: "error", code: "duplicateSlotOrder", message: `Duplicate slot order (${slot.order}).`, layoutId, slotId: slot.id });
    }
    seenOrders.add(slot.order);

    const { frame } = slot;
    if (!(frame.width > 0) || !(frame.height > 0) || frame.x < 0 || frame.y < 0 || slot.cornerRadius < 0) {
      issues.push({ level: "error", code: "invalidFrame", message: "Slot frame width/height must be > 0, x/y/cornerRadius >= 0.", layoutId, slotId: slot.id });
    }
    if (frame.x + frame.width > layout.referenceCanvas.width || frame.y + frame.height > layout.referenceCanvas.height) {
      issues.push({ level: "error", code: "slotOutsideCanvas", message: "Slot extends outside the page canvas.", layoutId, slotId: slot.id });
    }
    if (frame.width > 0 && frame.height > 0 && frame.width * frame.height < 0.01 * layout.referenceCanvas.width * layout.referenceCanvas.height) {
      issues.push({ level: "warning", code: "slotTooSmall", message: "Slot covers under 1% of the page — likely too small to be useful.", layoutId, slotId: slot.id });
    }
  }

  for (const format of layout.supportedFormats) {
    if (!aspectRatioMatchesFormat(layout.referenceCanvas, format)) {
      issues.push({
        level: "error",
        code: "aspectRatioMismatch",
        message: `referenceCanvas aspect ratio doesn't match declared format "${format}".`,
        layoutId,
      });
    }
  }

  // Overlap warning — pairwise rectangle intersection over the reference canvas.
  for (let i = 0; i < layout.slots.length; i += 1) {
    for (let j = i + 1; j < layout.slots.length; j += 1) {
      const a = layout.slots[i].frame;
      const b = layout.slots[j].frame;
      const overlapsX = a.x < b.x + b.width && b.x < a.x + a.width;
      const overlapsY = a.y < b.y + b.height && b.y < a.y + a.height;
      if (overlapsX && overlapsY) {
        issues.push({
          level: "warning",
          code: "slotOverlap",
          message: `Slots "${layout.slots[i].id}" and "${layout.slots[j].id}" overlap.`,
          layoutId,
        });
      }
    }
  }

  return issues;
}

/** Whole-library rules — mirrors `AlbumLayoutValidator.validate(_ library:)`: schema version and
 * cross-layout id uniqueness, then every layout's own rules via `validateLayout` above. */
export function validateLibrary(library: AlbumLayoutLibrary): ValidationIssue[] {
  const issues: ValidationIssue[] = [];

  if (library.schemaVersion !== SUPPORTED_SCHEMA_VERSION) {
    issues.push({
      level: "error",
      code: "unsupportedSchemaVersion",
      message: `schemaVersion ${library.schemaVersion} is not supported (expected ${SUPPORTED_SCHEMA_VERSION}).`,
    });
  }

  const seenLayoutIds = new Set<string>();
  for (const layout of library.layouts) {
    if (seenLayoutIds.has(layout.id)) {
      issues.push({ level: "error", code: "duplicateLayoutId", message: `Duplicate layout id "${layout.id}".`, layoutId: layout.id });
    }
    seenLayoutIds.add(layout.id);
  }

  for (const layout of library.layouts) {
    issues.push(...validateLayout(layout));
  }

  return issues;
}

export function hasErrors(issues: ValidationIssue[]): boolean {
  return issues.some((issue) => issue.level === "error");
}
