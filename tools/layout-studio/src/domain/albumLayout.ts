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

/** Which edge of the slot `AlbumSlotGradientOverlay`'s dark gradient starts from and fades inward
 * toward — mirrors `Nizi/Features/AlbumLayout/Domain/AlbumLayoutSlot.swift`'s own
 * `AlbumGradientEdge` exactly. */
export type AlbumGradientEdge = "top" | "bottom" | "left" | "right";

export const ALBUM_GRADIENT_EDGES: AlbumGradientEdge[] = ["top", "bottom", "left", "right"];

/** § user request — "phần ảnh cho phép chọn option gradient đen trong suốt, mục đích làm nền cho
 * chữ ... Cho phép tuỳ chọn gradien từ trái phải trên dưới, độ % gradient ... Có thêm opacity của
 * gradien nữa": an optional dark gradient painted on top of a slot's photo, so a text block
 * sitting over part of it stays legible. `edge` is where the gradient is darkest; it fades to
 * fully transparent over `extentPercent` of that edge's own axis (height for top/bottom, width for
 * left/right) — e.g. `edge: "bottom", extentPercent: 30` means the gradient spans only the bottom
 * 30% of the slot's height, from black (at `opacity`) at the very bottom edge to fully transparent
 * at the 30%-from-bottom mark. `opacity` is a second, independent knob — the gradient's own
 * maximum alpha at `edge`, before it fades to 0. Mirrors `AlbumSlotGradientOverlay.swift` exactly. */
export interface AlbumSlotGradientOverlay {
  edge: AlbumGradientEdge;
  /** 0...100 */
  extentPercent: number;
  /** 0...1 */
  opacity: number;
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
  /** `undefined`/absent means no overlay is painted — every layout authored before this feature
   * existed has no `gradientOverlay` key at all. */
  gradientOverlay?: AlbumSlotGradientOverlay;
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
 * Italic-Bold" — later refined to "Regular, Italic, Bold, Underline" (§ user report: the
 * Bold-Italic icon didn't reliably render, and 4 simple, single-attribute options with correct
 * icons matter more than every permutation) — mirrors `Nizi/Features/AlbumLayout/Domain/
 * AlbumTextBlock.swift`'s own `AlbumTextFontStyle` exactly. `"underline"` is a text *decoration*,
 * not a font face at all (see `TextBlockElement.tsx`'s own handling). */
export type AlbumTextFontStyle = "regular" | "italic" | "bold" | "underline";

export const ALBUM_TEXT_FONT_STYLES: AlbumTextFontStyle[] = ["regular", "italic", "bold", "underline"];

/** § user request — "Phần text trong Layout studio cho phép chọn kiểu: Title/Sub-title/Paragraph.
 * Dùng để trang trí văn bản sau này": purely semantic, mirrors `AlbumLayoutSlotRole` exactly — the
 * renderer (both here and in `AlbumTextBlockView.swift`) doesn't read this to alter anything yet;
 * it's Studio-authored metadata for a future decorative-styling feature to key off of. */
export type AlbumTextBlockKind = "title" | "subtitle" | "paragraph";

export const ALBUM_TEXT_BLOCK_KINDS: AlbumTextBlockKind[] = ["title", "subtitle", "paragraph"];

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
  /** § user request — "còn cần chọn màu chữ": hex string (e.g. `"#FFFFFF"`), same shape
   * `AlbumLayoutBackground.value` already uses. Mirrors `AlbumTextBlock.swift`'s own `textColor`
   * exactly, including its `"#000000"` fallback for anything authored before this field existed. */
  textColor: string;
  kind: AlbumTextBlockKind;
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
