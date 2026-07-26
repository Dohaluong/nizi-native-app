# Album Layout System

A standalone layout engine for Album pages: layout templates are described as data (JSON), not
hardcoded per-photo-count SwiftUI. One generic renderer displays any layout. This is
infrastructure only — there is no Layout Editor, drag/drop, or AI layout generation in this
sprint. See `docs/specs/SPEC-ALBUM-LAYOUT-ENGINE.md` for the full originating spec.

## 1. Architecture

```text
Layout JSON Library (album-layouts.json)
        ↓
Layout Domain Models (Features/AlbumLayout/Domain)
        ↓
Layout Repository (Features/AlbumLayout/Infrastructure)
        ↓
Generic Page Renderer (Features/AlbumLayout/Presentation)
```

Module layout, adapted to this project's existing Domain/Infrastructure/Presentation layering
(see `docs/architecture/ARCHITECTURE.md` § 3) rather than the spec's generic `Data`/`Rendering`/
`Preview` folder names:

```text
Features/AlbumLayout/
├── Domain/
│   ├── AlbumPageFormat.swift          — AlbumPageFormat, AlbumReferenceCanvas
│   ├── AlbumLayoutSlot.swift          — AlbumLayoutFrame, AlbumLayoutSlotRole, AlbumSlotContentMode, AlbumLayoutSlot
│   ├── AlbumLayoutBackground.swift    — AlbumLayoutBackgroundType, AlbumLayoutBackground
│   ├── AlbumPageLayout.swift          — AlbumPageLayout, AlbumLayoutLibrary
│   ├── AlbumPageContent.swift         — AlbumPhotoAssignment, AlbumPageContent
│   ├── AlbumLayoutError.swift
│   ├── AlbumLayoutValidator.swift
│   ├── AlbumLayoutRepository.swift    — protocol
│   └── AlbumLayoutSelecting.swift     — protocol + DefaultAlbumLayoutSelector
├── Infrastructure/
│   ├── album-layouts.json
│   └── BundleAlbumLayoutRepository.swift
└── Presentation/
    ├── AlbumPhotoProviding.swift      — protocol + PlaceholderAlbumPhotoProvider
    ├── AlbumPhotoSlotView.swift
    ├── AlbumPageRenderer.swift
    ├── AlbumLayoutGalleryPreview.swift
    └── AlbumPagesPreview.swift
```

Two data kinds are kept strictly separate:

- **Layout template** (`AlbumPageLayout`): canvas size, page-format compatibility, slots, each
  slot's frame/role/content-mode/corner-radius. Contains no photo IDs.
- **Album page content** (`AlbumPageContent`): which layout a page uses and which photo fills
  which slot (`AlbumPhotoAssignment`, keyed by `slotId` — never implicit array position). Contains
  no coordinates.

`AlbumPhotoProviding` (Presentation) is why the renderer never imports `Photos`/`PHAsset`: it's a
`View`-returning abstraction, so it can't live in Domain (which stays free of UI-framework
imports — see `docs/architecture/ARCHITECTURE.md` § 3) but keeps the renderer itself decoupled
from where a photo's pixels come from. `PlaceholderAlbumPhotoProvider` and
`NumberedPlaceholderPhotoProvider` (the latter in `AlbumLayoutGalleryPreview.swift`) are the only
implementations this sprint — a production implementation backed by the existing PhotoKit
thumbnail pipeline is future work, not built here.

## 2. Coordinate system

Every layout's slots are authored against a `referenceCanvas` (e.g. `1000 × 1000` for square),
never against actual on-screen points:

```json
"referenceCanvas": { "width": 1000, "height": 1000 },
"slots": [{ "frame": { "x": 60, "y": 60, "width": 880, "height": 880 } }]
```

`AlbumPageRenderer` scales at render time from whatever size a `GeometryReader` actually gives it:

```text
scaleX = actualCanvasWidth / referenceCanvasWidth
scaleY = actualCanvasHeight / referenceCanvasHeight

actualX      = frame.x × scaleX
actualY      = frame.y × scaleY
actualWidth  = frame.width × scaleX
actualHeight = frame.height × scaleY
```

This makes layouts resolution-independent, but **not** aspect-ratio-independent — see § 3.

## 3. Page format

```swift
enum AlbumPageFormat: String, Codable, CaseIterable {
    case square, portrait, landscape
}
```

Reference sizes: `square` 1000×1000, `portrait` 1000×1400, `landscape` 1400×1000
(`AlbumPageFormat.referenceSize`).

Every layout declares which format(s) it's actually designed for (`supportedFormats`) — a square
layout is not assumed to look good stretched into portrait or landscape just because the
renderer *can* scale it. `AlbumLayoutRepository.layouts(photoCount:format:)` filters on this;
`AlbumLayoutValidator` rejects a layout whose `referenceCanvas` aspect ratio doesn't actually
match every format it claims to support (± 5% tolerance for `square`).

This sprint's sample library is `square`-only (matching the current Album UI), but every model
and the renderer itself support all three formats.

## 4. JSON schema

File: `Features/AlbumLayout/Infrastructure/album-layouts.json`.

```json
{
  "schemaVersion": 1,
  "layouts": [
    {
      "id": "square.3.hero-top",
      "name": "Hero Top",
      "nameKey": "album.layout.square.3.hero_top",
      "photoCount": 3,
      "supportedFormats": ["square"],
      "referenceCanvas": { "width": 1000, "height": 1000 },
      "background": { "type": "solid", "value": "#FFFFFF" },
      "slots": [
        {
          "id": "photo-1",
          "order": 0,
          "role": "hero",
          "frame": { "x": 60, "y": 60, "width": 880, "height": 560 },
          "contentMode": "fill",
          "cornerRadius": 0
        }
      ]
    }
  ]
}
```

`name` is an English development-only label (debug/log/fallback). `nameKey` is what the UI
localizes — see § 8.

## 5. Renderer

`AlbumPageRenderer<Provider: AlbumPhotoProviding>`:

```swift
struct AlbumPageRenderer<Provider: AlbumPhotoProviding>: View {
    let layout: AlbumPageLayout
    let assignments: [AlbumPhotoAssignment]
    let photoProvider: Provider
    var showsDebugSlotIds: Bool = false
}
```

What it does, and only this:

1. One `GeometryReader` at the canvas level (never nested per-slot) computes `scaleX`/`scaleY`.
2. Renders `layout.background` (`solid` only this sprint).
3. Builds `[slotId: AlbumPhotoAssignment]` once per render pass (not re-searched per slot).
4. Renders each slot, sorted by `order`, inside a `ZStack(alignment: .topLeading)`, sized and
   placed with `.frame(width:height:).position(x:y:)` — not nested `HStack`/`VStack`.
5. Shows the assigned photo (via `photoProvider.photoView(photoId:contentMode:)`) or a
   placeholder (`Color(.secondarySystemFill)` + a `photo` SF Symbol) if the slot has no
   assignment — never crashes on a missing assignment.
6. Clips to the slot's (scaled) corner radius.

It never decides which layout to use (`AlbumLayoutSelecting`'s job), never assigns/reorders
photos, never loads JSON (`AlbumLayoutRepository`'s job), and never contains Album business
logic. The container always owns the size: an image's own intrinsic size can never push a slot
or the canvas larger.

## 6. Repository

```swift
protocol AlbumLayoutRepository {
    func loadLibrary() throws -> AlbumLayoutLibrary
    func layout(id: String) throws -> AlbumPageLayout
    func layouts(photoCount: Int, format: AlbumPageFormat) throws -> [AlbumPageLayout]
}
```

`BundleAlbumLayoutRepository` (Infrastructure) is the only implementation: reads
`album-layouts.json` from a `Bundle` (defaults to `.main`), decodes with `JSONDecoder`, validates
once via `AlbumLayoutValidator`, and caches the result in memory. A library that fails validation
is never cached — every subsequent call re-throws the same failure rather than silently falling
back to something partially valid.

## 7. Validation

`AlbumLayoutValidator.validate(_:)` runs once, right after decoding, before a library is ever
cached or handed to a renderer:

- `schemaVersion` must be supported (currently `1`).
- No duplicate layout IDs across the library.
- `photoCount` must be 1–4.
- `slots.count == photoCount`.
- No duplicate slot IDs or duplicate `order` values within a layout.
- Canvas width/height > 0.
- Every slot: `width`/`height` > 0, `x`/`y` ≥ 0, `cornerRadius` ≥ 0.
- Every slot fully inside its canvas (`x + width ≤ canvasWidth`, `y + height ≤ canvasHeight`).
- `supportedFormats` non-empty.
- Canvas aspect ratio actually matches every declared format (§ 3), ± 5% for `square`.

`AlbumLayoutValidator.validateAssignments(_:layout:)` is a second, separate check for
`AlbumPageContent` against the `AlbumPageLayout` it claims to use: every assignment's `slotId`
must exist on that layout, and no two assignments may claim the same slot. A slot with **no**
assignment is not an error — that's exactly the "renderer shows a placeholder" case.

Every failure is a specific `AlbumLayoutError` case (never a generic error), so a validation
failure is diagnosable from the error alone — see `AlbumLayoutError.swift` for the full list.
No `fatalError` anywhere in the loader.

## 8. Localization

Model/code identifiers stay English. User-facing strings go through the existing
`Localizable.xcstrings` system (see `docs/LOCALIZATION.md`) — no custom localization manager.

Fixed UI chrome:

```text
album.layout.gallery.title
album.layout.photo_count
album.layout.page
album.layout.format.square / .portrait / .landscape
album.layout.photo_number                              (accessibility fallback, "Photo N")
album.layout.gallery.thumbnail_accessibility
album.layout.pages_preview.title / .subtitle
```

Per-layout display names are **not** hardcoded strings in the JSON — each layout carries a
`nameKey` (e.g. `"album.layout.square.3.hero_top"`) instead of relying on `name` for display.
Because `nameKey` is a runtime `String` (data-driven, not a compile-time literal),
`Text(layout.nameKey)` would render it *verbatim* instead of resolving it — SwiftUI only performs
key lookup for `LocalizedStringKey` string-literal arguments. The correct call is:

```swift
localizedString(dynamicKey: layout.nameKey, defaultValue: layout.name)
```

(`Core/Localization/LocalizedString.swift`) — this also honors the Diagnostics screen's debug
language override, same as every other string in the app.

## 9. Adding a new layout

1. Pick an ID: `{format}.{photoCount}.{variant}`, lowercase, hyphenated, e.g.
   `"square.2.diagonal"`. This ID is a **persistent identifier** — once any Album page
   references it, never change or reuse it for a different layout.
2. Add a `nameKey` following the same shape with underscores:
   `"album.layout.square.2.diagonal"`. Add its `en`/`vi` values to `Localizable.xcstrings`.
3. Design slot frames against the format's reference canvas (§ 3). Recommended conventions
   (not enforced by validation, just what the sample library uses): outer margin 50–70pt
   (default 60), gap between slots 12–24pt (default 16), no unnecessary decimals.
4. Append the layout object to `Features/AlbumLayout/Infrastructure/album-layouts.json`.
5. Run `AlbumLayoutDecodingTests`/`AlbumLayoutValidationTests` (or just open
   `AlbumLayoutGalleryPreview` in an Xcode Preview) to confirm it decodes, validates, and looks
   right before it's used anywhere real.
6. If it should be a `DefaultAlbumLayoutSelector` default for its photo count, update
   `DefaultAlbumLayoutSelector.defaultLayoutIds`.

## 10. Current layout library

12 layouts, all `square`, `referenceCanvas` 1000×1000:

| ID | Photos | Name |
|---|---|---|
| `square.1.full-bleed` | 1 | Full Bleed |
| `square.1.inset` | 1 | Inset |
| `square.1.landscape-center` | 1 | Landscape Center |
| `square.2.vertical-split` | 2 | Vertical Split |
| `square.2.horizontal-split` | 2 | Horizontal Split |
| `square.2.hero-top` | 2 | Hero Top |
| `square.3.hero-top` | 3 | Hero Top |
| `square.3.hero-left` | 3 | Hero Left |
| `square.3.equal-columns` | 3 | Equal Columns |
| `square.4.grid` | 4 | Grid |
| `square.4.hero-top` | 4 | Hero Top |
| `square.4.hero-left` | 4 | Hero Left |

`DefaultAlbumLayoutSelector`'s deterministic default per photo count: `square.1.inset`,
`square.2.vertical-split`, `square.3.hero-top`, `square.4.grid`.

## 11. Preview screens

- **`AlbumLayoutGalleryPreview`** — every layout in the library, grouped by photo count, each
  rendered through `AlbumPageRenderer` with numbered (`1`/`2`/`3`/`4`) placeholders so slot order
  is visible at a glance. Tap a layout to open a larger preview. No Photos Library access, no
  network, works fully offline in an Xcode Preview.
- **`AlbumPagesPreview`** — a hero cover plus a horizontally-paged run of demo pages, each
  resolved from the repository via `DefaultAlbumLayoutSelector` and rendered through
  `AlbumPageRenderer` — never a hardcoded per-page SwiftUI layout. Shows current page / total
  pages / current layout ID. This is a standalone acceptance/demo screen for the layout engine;
  it does not modify the existing, already-approved `AlbumDetailDesignPreview` hero or page
  carousel.

Neither screen is wired into the app's real navigation yet (no entry point from `HomeView` or
`AlbumDetailDesignPreview`) — that integration is future work, once a production
`AlbumPhotoProviding` implementation exists.

## 12. Extension points for a future Layout Designer

Not built this sprint (no editor UI, drag handles, resize, snap grid, JSON export, authoring
tools) — but the system is already shaped to support one later without a rewrite:

- Every model is `Codable` both ways (decode *and* encode), so an editor could serialize what it
  produces back into the same JSON shape.
- Layout IDs are persistent identifiers by convention (§ 9) — a designer must preserve this.
- Frames are always canvas-relative (§ 2), never raw on-screen points, so an editor's coordinate
  space and the renderer's agree without translation.
- `AlbumLayoutRepository` is a protocol — nothing outside `BundleAlbumLayoutRepository` assumes
  the library comes from the app bundle, so a designer-backed or server-synced repository is a
  new conformance, not a change to any caller.
- `AlbumPageRenderer` doesn't know or care where a `AlbumPageLayout` came from.
- `AlbumLayoutValidator` is reusable as-is for validating designer output before it's saved.
- `schemaVersion` exists in the JSON specifically so a future format change can be
  version-gated.

## 13. Known limitations

- No production `AlbumPhotoProviding` implementation — both preview screens use placeholder
  photo providers only.
- Neither preview screen has a real navigation entry point in the app yet.
- `AlbumLayoutSelecting.alternativeLayouts` exists (for a future "change this page's template"
  UI) but nothing calls it yet.
- Only `square` layouts exist in the sample library; `portrait`/`landscape` are modeled and
  render correctly but have no sample layouts to exercise them beyond the validator's own unit
  tests.
- Slot overlap is not rejected at the validator level (by design — a future creative layout may
  need it), only visually avoided in the 12 sample layouts.
