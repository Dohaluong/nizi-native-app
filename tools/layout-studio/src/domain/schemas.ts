import { z } from "zod";
import {
  ALBUM_GRADIENT_EDGES,
  ALBUM_LAYOUT_SLOT_ROLES,
  ALBUM_SLOT_CONTENT_MODES,
  ALBUM_SLOT_ORIENTATIONS,
  ALBUM_TEXT_BLOCK_KINDS,
  ALBUM_TEXT_FONT_FAMILIES,
  ALBUM_TEXT_FONT_STYLES,
  ALBUM_TEXT_HORIZONTAL_ALIGNMENTS,
  ALBUM_TEXT_VERTICAL_ALIGNMENTS,
} from "./albumLayout";

/**
 * Structural (per-field/per-type) validation only — mirrors the real Swift `Codable` shape
 * exactly (§ 20 of the spec). Cross-field / cross-layout rules that Zod can't express cleanly
 * (duplicate IDs across a whole library, `x + width <= canvas.width`, `photoCount ==
 * slots.length`, aspect-ratio-matches-format) live in `services/validateLayout.ts`'s semantic
 * pass instead — this schema only decides "is this even shaped like the real JSON at all."
 */

const nonEmptyString = z.string().min(1, "must not be empty");

export const albumPageFormatSchema = z.enum(["square", "portrait", "landscape"]);

export const albumReferenceCanvasSchema = z.object({
  width: z.number().positive(),
  height: z.number().positive(),
});

export const albumLayoutBackgroundSchema = z.object({
  type: z.literal("solid"),
  value: nonEmptyString,
});

export const albumSlotOrientationSchema = z.enum(
  ALBUM_SLOT_ORIENTATIONS as [string, ...string[]],
);

export const albumLayoutSlotRoleSchema = z.enum(ALBUM_LAYOUT_SLOT_ROLES as [string, ...string[]]);

export const albumSlotContentModeSchema = z.enum(
  ALBUM_SLOT_CONTENT_MODES as [string, ...string[]],
);

export const albumLayoutFrameSchema = z.object({
  x: z.number().min(0),
  y: z.number().min(0),
  width: z.number().positive(),
  height: z.number().positive(),
});

export const albumGradientEdgeSchema = z.enum(ALBUM_GRADIENT_EDGES as [string, ...string[]]);

// § user request — "phần ảnh cho phép chọn option gradient đen trong suốt ... Cho phép tuỳ chọn
// gradien từ trái phải trên dưới, độ % gradient ... Có thêm opacity của gradien nữa": mirrors
// `AlbumSlotGradientOverlay.swift` field-for-field.
export const albumSlotGradientOverlaySchema = z.object({
  edge: albumGradientEdgeSchema,
  extentPercent: z.number().min(0).max(100),
  opacity: z.number().min(0).max(1),
});

export const albumLayoutSlotSchema = z.object({
  id: nonEmptyString,
  order: z.number().int().min(0),
  role: albumLayoutSlotRoleSchema,
  preferredOrientation: albumSlotOrientationSchema,
  frame: albumLayoutFrameSchema,
  contentMode: albumSlotContentModeSchema,
  cornerRadius: z.number().min(0),
  // `.optional()` (not required) — every layout authored before this feature existed has no
  // `gradientOverlay` key at all, same backward-compatible posture `textBlocks.default([])` below
  // already uses for the same reason.
  gradientOverlay: albumSlotGradientOverlaySchema.optional(),
});

export const albumTextHorizontalAlignmentSchema = z.enum(
  ALBUM_TEXT_HORIZONTAL_ALIGNMENTS as [string, ...string[]],
);

export const albumTextVerticalAlignmentSchema = z.enum(
  ALBUM_TEXT_VERTICAL_ALIGNMENTS as [string, ...string[]],
);

export const albumTextFontFamilySchema = z.enum(ALBUM_TEXT_FONT_FAMILIES as [string, ...string[]]);

// § lesson learned from the iOS app's own "mất hết ảnh" bug (a schema evolution that made one
// stale field value fail decoding took down the *entire* layout library, not just the one text
// block): a plain `z.enum(...)` would reject an already-saved `"boldItalic"` value outright (that
// case existed only briefly, before being replaced with `"underline"`) and fail importing the
// *whole* file. `z.preprocess` remaps anything not in the current set to `"regular"` first, so an
// old file with that stale value still imports cleanly instead of blocking the whole import.
export const albumTextFontStyleSchema = z.preprocess(
  (value) => (typeof value === "string" && !(ALBUM_TEXT_FONT_STYLES as string[]).includes(value) ? "regular" : value),
  z.enum(ALBUM_TEXT_FONT_STYLES as [string, ...string[]]),
);

// § the real bundled `album-layouts.json` still has text blocks authored *before* `fontStyle`
// existed at all (e.g. `layouts[30].textBlocks[0]`, which only has a legacy `fontWeight` key and
// no `fontStyle` key whatsoever) — a *missing* key isn't something a per-field `z.preprocess` on
// `fontStyle` alone can rescue, since there's no sibling-field access at that level. This
// object-level preprocess mirrors `AlbumTextBlock.swift`'s own custom `init(from:)` exactly:
// legacy `fontWeight === "bold"` → `"bold"`, anything else (including missing entirely) →
// `"regular"`.
export const albumTextBlockSchema = z.preprocess((value) => {
  if (typeof value !== "object" || value === null) return value;
  const record = value as Record<string, unknown>;
  if (typeof record.fontStyle === "string" && (ALBUM_TEXT_FONT_STYLES as string[]).includes(record.fontStyle)) {
    return record;
  }
  const resolvedStyle = record.fontWeight === "bold" ? "bold" : "regular";
  return { ...record, fontStyle: resolvedStyle };
}, z.object({
  id: nonEmptyString,
  order: z.number().int().min(0),
  frame: albumLayoutFrameSchema,
  horizontalAlignment: albumTextHorizontalAlignmentSchema,
  verticalAlignment: albumTextVerticalAlignmentSchema,
  fontFamily: albumTextFontFamilySchema,
  fontSize: z.number().positive(),
  fontStyle: z.enum(ALBUM_TEXT_FONT_STYLES as [string, ...string[]]),
  // § user request — "còn cần chọn màu chữ": every text block authored before this field existed
  // has no `textColor` key at all (the same missing-key shape `fontStyle`/`fontWeight` had) —
  // `.catch(...)` substitutes the fallback for both a missing key and a malformed value, mirroring
  // `AlbumTextBlock.swift`'s own `"#000000"` default exactly.
  textColor: z.string().catch("#000000"),
  // § user request — "cho phép chọn kiểu: Title/Sub-title/Paragraph. Dùng để trang trí văn bản sau
  // này": same missing-key shape as `textColor` above (no existing text block has a `kind` key at
  // all) — `.catch("paragraph")` mirrors `AlbumTextBlock.swift`'s own `.paragraph` default.
  kind: z.enum(ALBUM_TEXT_BLOCK_KINDS as [string, ...string[]]).catch("paragraph"),
}));

export const albumPageLayoutSchema = z.object({
  id: nonEmptyString,
  name: nonEmptyString,
  nameKey: nonEmptyString,
  photoCount: z.number().int().min(1).max(4),
  supportedFormats: z.array(albumPageFormatSchema).min(1),
  referenceCanvas: albumReferenceCanvasSchema,
  background: albumLayoutBackgroundSchema,
  slots: z.array(albumLayoutSlotSchema),
  // § user request "Thêm chữ" — `.default([])` (not a plain required array) so any
  // `album-layouts.json` exported before this feature existed still imports cleanly, matching the
  // same backward-compatible posture `AlbumPageLayout.textBlocks` uses on the Swift side.
  textBlocks: z.array(albumTextBlockSchema).default([]),
});

export const albumLayoutLibrarySchema = z.object({
  schemaVersion: z.number().int(),
  layouts: z.array(albumPageLayoutSchema),
});

export type AlbumLayoutLibraryParsed = z.infer<typeof albumLayoutLibrarySchema>;
