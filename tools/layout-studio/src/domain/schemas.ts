import { z } from "zod";
import {
  ALBUM_LAYOUT_SLOT_ROLES,
  ALBUM_SLOT_CONTENT_MODES,
  ALBUM_SLOT_ORIENTATIONS,
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

export const albumLayoutSlotSchema = z.object({
  id: nonEmptyString,
  order: z.number().int().min(0),
  role: albumLayoutSlotRoleSchema,
  preferredOrientation: albumSlotOrientationSchema,
  frame: albumLayoutFrameSchema,
  contentMode: albumSlotContentModeSchema,
  cornerRadius: z.number().min(0),
});

export const albumTextHorizontalAlignmentSchema = z.enum(
  ALBUM_TEXT_HORIZONTAL_ALIGNMENTS as [string, ...string[]],
);

export const albumTextVerticalAlignmentSchema = z.enum(
  ALBUM_TEXT_VERTICAL_ALIGNMENTS as [string, ...string[]],
);

export const albumTextFontFamilySchema = z.enum(ALBUM_TEXT_FONT_FAMILIES as [string, ...string[]]);

export const albumTextFontStyleSchema = z.enum(ALBUM_TEXT_FONT_STYLES as [string, ...string[]]);

export const albumTextBlockSchema = z.object({
  id: nonEmptyString,
  order: z.number().int().min(0),
  frame: albumLayoutFrameSchema,
  horizontalAlignment: albumTextHorizontalAlignmentSchema,
  verticalAlignment: albumTextVerticalAlignmentSchema,
  fontFamily: albumTextFontFamilySchema,
  fontSize: z.number().positive(),
  fontStyle: albumTextFontStyleSchema,
});

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
