/**
 * Mirrors the real production schema exactly, as discovered from the iOS app (not invented):
 *
 *  - Nizi/Features/AlbumLayout/Domain/AlbumPageLayout.swift  (AlbumPageLayout, AlbumLayoutLibrary)
 *  - Nizi/Features/AlbumLayout/Domain/AlbumLayoutSlot.swift  (AlbumLayoutSlot, AlbumLayoutFrame,
 *    AlbumLayoutSlotRole, AlbumSlotContentMode, AlbumSlotOrientation)
 *  - Nizi/Features/AlbumLayout/Domain/AlbumPageFormat.swift  (AlbumPageFormat, AlbumReferenceCanvas)
 *  - Nizi/Features/AlbumLayout/Domain/AlbumLayoutBackground.swift (AlbumLayoutBackground)
 *  - Nizi/Features/AlbumLayout/Infrastructure/album-layouts.json (the real resource file)
 *
 * IMPORTANT — geometry unit: `AlbumLayoutFrame.x/y/width/height` are **not** normalized 0...1.
 * They're absolute units against that layout's own `referenceCanvas` (e.g. 1000x1000 for every
 * `square` layout shipped today — see `AlbumPageFormat.referenceSize`). The Studio's canvas/
 * geometry math (`services/normalizeGeometry.ts`) treats `referenceCanvas.width/height` as the
 * scale factor instead of assuming it's always 1, specifically because the real schema isn't
 * normalized the way the spec's own illustrative example assumed.
 *
 * Every field here is required (no optionals) — the real Swift `Codable` structs have no
 * `decodeIfPresent` anywhere in this model, so a Studio-authored export must supply all of them.
 */

export type AlbumPageFormat = "square" | "portrait" | "landscape";

export interface AlbumReferenceCanvas {
  width: number;
  height: number;
}

/** `AlbumPageFormat.referenceSize` in `AlbumPageFormat.swift` — used only to seed a *new*
 * layout's canvas with a sensible default; existing layouts keep whatever `referenceCanvas`
 * they were authored/imported with. */
export const DEFAULT_REFERENCE_CANVAS: Record<AlbumPageFormat, AlbumReferenceCanvas> = {
  square: { width: 1000, height: 1000 },
  portrait: { width: 1000, height: 1400 },
  landscape: { width: 1400, height: 1000 },
};

export type AlbumLayoutBackgroundType = "solid";

export interface AlbumLayoutBackground {
  type: AlbumLayoutBackgroundType;
  /** Hex color string, e.g. `"#FFFFFF"`. */
  value: string;
}

/** Exactly the 4 values `AlbumSlotOrientation` supports — never invent `horizontal`/`vertical`/
 * `auto` (§ 14 of the spec explicitly calls this out). */
export type AlbumSlotOrientation = "landscape" | "portrait" | "square" | "any";

export const ALBUM_SLOT_ORIENTATIONS: AlbumSlotOrientation[] = [
  "landscape",
  "portrait",
  "square",
  "any",
];

/** `AlbumLayoutSlotRole` — semantic only, never alters a slot's frame. */
export type AlbumLayoutSlotRole = "hero" | "supporting";

export const ALBUM_LAYOUT_SLOT_ROLES: AlbumLayoutSlotRole[] = ["hero", "supporting"];

/** `AlbumSlotContentMode` — `fill` (scale-to-fill/crop) or `fit` (scale-to-fit/letterbox). The
 * renderer always clips to the slot frame regardless of which one is chosen. */
export type AlbumSlotContentMode = "fill" | "fit";

export const ALBUM_SLOT_CONTENT_MODES: AlbumSlotContentMode[] = ["fill", "fit"];

export interface AlbumLayoutFrame {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface AlbumLayoutSlot {
  id: string;
  /** Must be unique within its own layout (not globally) — `AlbumLayoutValidator.
   * duplicateSlotOrder`. The Studio auto-assigns this from array position; it's not user-edited
   * directly. */
  order: number;
  role: AlbumLayoutSlotRole;
  preferredOrientation: AlbumSlotOrientation;
  frame: AlbumLayoutFrame;
  contentMode: AlbumSlotContentMode;
  cornerRadius: number;
}

/** § user request "Thêm chữ" — mirrors `Nizi/Features/AlbumLayout/Domain/AlbumTextBlock.swift`
 * exactly, the same "mirror the real Swift Codable shape" convention every other type in this file
 * follows. Never counted toward `photoCount`/`slots.length` — a separate, decorative collection. */
export type AlbumTextHorizontalAlignment = "left" | "center" | "right";

export const ALBUM_TEXT_HORIZONTAL_ALIGNMENTS: AlbumTextHorizontalAlignment[] = ["left", "center", "right"];

export type AlbumTextVerticalAlignment = "top" | "center" | "bottom";

export const ALBUM_TEXT_VERTICAL_ALIGNMENTS: AlbumTextVerticalAlignment[] = ["top", "center", "bottom"];

/** Raw values are the *exact* iOS family names `AlbumTextBlockView.swift` looks up via
 * `UIFont.fontNames(forFamilyName:)` — see that Swift enum's own doc comment for why this is a
 * curated subset, not iOS's full Font Book list. */
export type AlbumTextFontFamily =
  | "System"
  | "Helvetica Neue"
  | "Avenir"
  | "Avenir Next"
  | "Georgia"
  | "Baskerville"
  | "Didot"
  | "Futura"
  | "Gill Sans"
  | "Optima"
  | "Palatino"
  | "Times New Roman"
  | "American Typewriter"
  | "Noteworthy"
  | "Snell Roundhand"
  | "Marker Felt"
  | "Papyrus";

export const ALBUM_TEXT_FONT_FAMILIES: AlbumTextFontFamily[] = [
  "System",
  "Helvetica Neue",
  "Avenir",
  "Avenir Next",
  "Georgia",
  "Baskerville",
  "Didot",
  "Futura",
  "Gill Sans",
  "Optima",
  "Palatino",
  "Times New Roman",
  "American Typewriter",
  "Noteworthy",
  "Snell Roundhand",
  "Marker Felt",
  "Papyrus",
];

/** § user request — "font-weight sẽ thay bằng các định dạng cơ bản: Regular, Italic, Bold,
 * Italic-Bold": the 4 basic style permutations most fonts actually ship as distinct named faces —
 * mirrors `Nizi/Features/AlbumLayout/Domain/AlbumTextBlock.swift`'s own `AlbumTextFontStyle`
 * exactly (this replaced an earlier `AlbumTextFontWeight` thickness scale — medium/semibold rarely
 * resolved to a visibly different face for most of the curated families above anyway). */
export type AlbumTextFontStyle = "regular" | "italic" | "bold" | "boldItalic";

export const ALBUM_TEXT_FONT_STYLES: AlbumTextFontStyle[] = ["regular", "italic", "bold", "boldItalic"];

export interface AlbumTextBlock {
  id: string;
  /** Must be unique within its own layout (not globally) — mirrors `AlbumLayoutSlot.order`. */
  order: number;
  frame: AlbumLayoutFrame;
  horizontalAlignment: AlbumTextHorizontalAlignment;
  verticalAlignment: AlbumTextVerticalAlignment;
  fontFamily: AlbumTextFontFamily;
  fontSize: number;
  fontStyle: AlbumTextFontStyle;
}

export interface AlbumPageLayout {
  /** Persistent, `{format}.{photoCount}.{variant}`-shaped (e.g. `"square.3.hero-top"`) — once an
   * Album page references it, it must never change or be reused for a different layout. */
  id: string;
  /** English development name (debug/log/fallback) — not localized. */
  name: string;
  /** Localization key for the user-facing name, e.g. `"album.layout.square.3.hero_top"`. The
   * Studio only ever generates a plausible key from `id`; it does not (and cannot) add the
   * actual translated strings to the iOS app's `Localizable.xcstrings`. */
  nameKey: string;
  photoCount: number;
  supportedFormats: AlbumPageFormat[];
  referenceCanvas: AlbumReferenceCanvas;
  background: AlbumLayoutBackground;
  slots: AlbumLayoutSlot[];
  textBlocks: AlbumTextBlock[];
}

export interface AlbumLayoutLibrary {
  schemaVersion: number;
  layouts: AlbumPageLayout[];
}

/** The only schema version the real app currently understands (`AlbumLayoutValidator.
 * validate(_:supportedSchemaVersion:)`'s own default). */
export const SUPPORTED_SCHEMA_VERSION = 1;
