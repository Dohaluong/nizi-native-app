# Photo Editor — Implementation Plan

Status: survey complete, no editor code written yet. Written against the spec in
[modules/photo-editor/PHOTO-EDITOR.md](photo-editor/PHOTO-EDITOR.md) and the codebase as of this
commit (`8da8eb8`).

This plan intentionally follows the user's 10-step rollout (khảo sát → foundation → rendering →
preset → adjust → auto enhance → persistence → Album/Event integration → collection style →
testing/perf), not the spec's own "Sprint 1–6" grouping — the two describe the same work, just
sliced differently; the 10-step order is more granular and is what was explicitly requested.

---

## 1. Codebase survey

### 1.1 Architecture pattern (confirmed, to be reused as-is)

Every feature under `Nizi/Features/*` follows the same four-layer split
(`docs/architecture/ARCHITECTURE.md` § 3):

```text
Features/<Name>/
├── Domain/          entities, protocols — zero framework imports (no Photos/SwiftUI/SwiftData)
├── Application/      use cases / orchestration, framework-light
├── Infrastructure/    PhotoKit, SwiftData, Vision — the only layer allowed to import them
└── Presentation/      SwiftUI views + view models
```

Examples: `Features/AlbumCreation`, `Features/AlbumPhotos`, `Features/AlbumViewer`,
`Features/MemoryDiscovery`, `Features/PhotoLocation`. Photo Editor will be
`Features/PhotoEditor/{Domain,Application,Infrastructure,Presentation}` — a new peer module, not a
subfolder of Album or Event. This matches ADR-MD-001 ("modules don't reach into each other's
infrastructure") and the spec's § 24 ("Photo Editor là một module độc lập").

**Important architectural observation**: the codebase already has *two* separate,
non-shared PHAsset-loading stacks — `Features/MemoryDiscovery/{Domain/PhotoAssetProvider.swift,
Infrastructure/PhotoKitAssetProvider.swift}` for Event/curation screens, and
`Features/AlbumPhotos/{Application/AlbumPhotoProviding.swift, Infrastructure/
ApplePhotosAlbumPhotoProvider.swift, Infrastructure/PHAssetRepository.swift}` for Album screens.
Neither reuses the other, and both independently do `PHAsset.fetchAssets(withLocalIdentifiers:)`
and drive `PHCachingImageManager` directly. This is the established precedent — **not** an
oversight to fix. Photo Editor follows the same precedent: its own small Infrastructure-layer
PHAsset loader, not a dependency on either existing stack's Infrastructure classes.

### 1.2 PHAsset / Photos access

- `Photos.PHAsset` is looked up by `localIdentifier` in three places today, all with the same
  one-line shape: `PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject`
  (`Features/AlbumPhotos/Infrastructure/PHAssetRepository.swift:18`,
  `Features/MemoryDiscovery/Infrastructure/PhotoKitAssetProvider.swift:123`).
- Every string photo ID in this app (`AlbumPhotoReference.sourceIdentifier`, `PhotoEvent.assetIDs`,
  `IndexedAsset.id`) **is** a `PHAsset.localIdentifier`. Photo Editor's `EditorContext.photoId` /
  `photoIds` follow the same convention — no new "photo identity" type needed.
- Thumbnail/preview requests go through `PHCachingImageManager.requestImage(for:targetSize:
  contentMode:options:)`, wrapped in `withCheckedThrowingContinuation` +
  `withTaskCancellationHandler` for proper cancellation
  (`PhotoKitAssetProvider.swift:145-180`). Photo Editor's render engine reuses this exact
  cancellation pattern for its own PHAsset fetches.
- Nothing in the codebase yet calls `requestImageDataAndOrientation` or reads
  `CGImagePropertyOrientation` — Core Image / orientation normalization is new territory (§ 1.4).
- `PHImageRequestOptions.version` is set to `.current` in `ApplePhotosAlbumPhotoProvider.swift:66`
  — i.e. the app already renders Apple Photos' current (edited) version, not the original, for
  Album photo display. Photo Editor should do the same for consistency (spec § 17.5 explicitly
  recommends this).
- Grep confirms **zero** existing use of `PHAssetChangeRequest` anywhere
  (`AlbumDraftRepository.swift:18` states this as a deliberate invariant: "no
  `PHAssetChangeRequest` anywhere in this app's edit/delete paths"). Photo Editor's non-destructive
  requirement is already the house style, not a new constraint to introduce.

### 1.3 Album and Event models

- `AlbumDraft` (`Features/AlbumCreation/Domain/AlbumDraft.swift`) — `id: String`, `spreads:
  [AlbumDraftSpread]` → each has `leftPage`/`rightPage: AlbumDraftPage` → each has `assignments:
  [AlbumPhotoAssignment]` (photo + slot). No per-photo or per-album "style"/edit-recipe field
  exists yet.
- `PhotoEvent` (`Features/MemoryDiscovery/Domain/PhotoEvent.swift`) — `id: UUID`, `assetIDs:
  [String]`. Also has no style field yet. Curated per-photo membership actually lives one level
  down, in `PhotoCurationItem`/`EventCurationResult` (`Features/MemoryDiscovery/Domain/
  PhotoCurationItem.swift`, `PhotoCurationGroup.swift`) — the full-screen Event viewer
  (`CurationPreviewView`) works off `[PhotoCurationItem]`, not `PhotoEvent` directly.
- Neither model needs a schema change to *identify* a collection — `AlbumDraft.id` (String) and
  `PhotoEvent.id.uuidString` are already stable, persisted keys. `CollectionEditStyle` (spec §
  13.2) can be stored keyed by `(collectionType, collectionId)` without touching `AlbumDraft` or
  `PhotoEvent` at all.

### 1.4 Persistence

- SwiftData, via `@ModelActor actor` repositories — `SwiftDataMemoryDiscoveryStore` (implements
  five Domain repository protocols at once) and `SwiftDataAlbumDraftStore` (one repository, one
  model). Both take `modelContainer:` in `init` and are constructed on demand from
  `modelContext.container` at call sites (never held as a singleton).
- Every `@Model` class lives in an `Infrastructure/` folder, is prefixed `MD*` (`MDLocalAsset`,
  `MDAlbumDraft`, `MDEventCandidate`, …), and follows the same shape: a few plain columns for
  cheap list-screen queries, sometimes a full `Data` blob of `JSONEncoder().encode(domainStruct)`
  for the rest (`MDAlbumDraft.encodedDraft`, `Features/AlbumCreation/Infrastructure/
  MDAlbumDraft.swift:41`). New optional columns default to a harmless value specifically so
  SwiftData's lightweight migration adds them to existing rows without data loss — documented
  explicitly in `MDAlbumDraft.swift:23-26` as a hard rule ("Không xóa dữ liệu Draft cũ một cách im
  lặng").
- All `@Model` types are registered in one place: `NiziApp.swift:31-35`,
  `.modelContainer(for: [MDLocalAsset.self, ..., MDAlbumDraft.self])`. Photo Editor's two new
  models (`MDPhotoEditRecipe`, `MDCollectionEditStyle`) are additive entries in that same array —
  this is the only required change to `NiziApp.swift`.
- `PhotoEditRecipe` is a small, flat `Codable` struct (per spec § 13.1) — it fits the
  "encode-to-`Data`-blob" pattern used for `AlbumDraft`, but is simple enough that plain columns
  (no blob) are actually cleaner here, since every field is a primitive or another small `Codable`
  struct (`PhotoAdjustments`). Plan: store `PhotoAdjustments` itself as an encoded `Data` blob
  (6 floats, trivial to encode/decode) alongside plain columns for `photoId`/`presetId`/
  `presetIntensity`/flags/timestamps — mirrors `MDAlbumDraft`'s "plain columns for queryable
  fields + blob for the nested structure" split at a smaller scale.

### 1.5 Photo Viewer (existing full-screen viewers)

There are **two** independent full-screen photo viewers today, not one shared component:

1. **Album**: `Features/AlbumViewer/Presentation/AlbumPhotoPreviewView.swift` — a
   `TabView(.page)` over `[AlbumPhotoAssignment]`, opened from `AlbumDetailView.swift:97-101`
   (`openPhotoPreview`) via `.fullScreenCover(item: $photoPreviewTarget)`
   (`AlbumDetailView.swift:159-164`). Its `PhotoPreviewTarget` (private struct, `AlbumDetailView.
   swift:47-51`) carries only `photos`/`startIndex` — **not** the album's `draft.id**, even though
   `draft` is in scope at the call site. Adding an `Edit` entry point requires threading
   `draft.id` through this struct (one new field, trivial).
2. **Event**: `CurationPreviewView` / `CurationPreviewPage`, private types inside
   `Features/MemoryDiscovery/Presentation/EventDetailView.swift` (lines ~662–1401), opened via
   `.fullScreenCover(item: $previewPresentation)` (`EventDetailView.swift:140-148`). Its
   `CurationPreviewPresentation` (`EventDetailView.swift:41-46`) carries `items:
   [PhotoCurationItem]` — likewise no `event.id`, though `event` is in scope in the owning view.
   Same one-field threading job.

Both viewers already have a documented three-tier image-loading strategy (`gridThumbnail` →
`viewerSeed` → `displayPreview`, capped at 1000×1000 — see `EventDetailView.swift:14-33`) and a
top-trailing/top-leading close button in a `ZStack`. The natural integration point for an `Edit`
button in both is the same toolbar/overlay area the close button already occupies.

Reusable pattern from both viewers worth carrying into the editor's own render engine: **task
ownership must live at the viewer level, not the page level** — `CurationPreviewView` explicitly
keeps `displayPreviewTasks: [String: Task<...>]` on the parent view
(`EventDetailView.swift:706-707`) specifically because SwiftUI recycles/tears down off-screen
`TabView` pages, which would otherwise cancel an in-flight image request every time a page scrolls
out of the live window (`EventDetailView.swift:698-705`, comment). Photo Editor's slider-driven
render requests need the identical ownership model (owned by `PhotoEditorViewModel`, not by
whatever preview `View` struct is on screen), or a fast slider drag will spuriously cancel/redo
renders exactly the way that bug used to happen here.

### 1.6 Photo/image services and repositories already available to build on

| Concern | Existing type | Reusable as-is? |
|---|---|---|
| PHAsset lookup by id | `PHAssetResolving` / `PHAssetRepository` (AlbumPhotos/Infrastructure) | Pattern only — new small copy in PhotoEditor/Infrastructure, not a cross-module dependency |
| Thumbnail request + cache | `PhotoAssetProvider` / `PhotoKitAssetProvider` (MemoryDiscovery) | Pattern only, same reasoning |
| In-memory image cache | `NSCache`-backed `AlbumImageCache` (AlbumPhotos/Infrastructure) | Pattern only — Photo Editor needs its own (different key shape: recipe hash, not just size/crop) |
| Platform image typealias | `PlatformImage = UIImage` (MemoryDiscovery/Domain/PlatformImage.swift) | **Yes, reuse directly** — already a shared, framework-neutral name |
| Logging | `NiziLogger.discovery` / `.general` (Core/Logging) | Add a new `NiziLogger.photoEditor` category, same pattern |
| Bundle-JSON-backed definitions | `BundleAlbumLayoutRepository` (AlbumLayout/Infrastructure) reading layout JSON from the app bundle | **Yes, same pattern** for `PresetRepository` reading `PresetDefinition` JSON |
| SwiftData repository shape | `@ModelActor actor ... : SomeRepositoryProtocol` | **Yes, same pattern** for `PhotoEditRepository`/`CollectionStyleRepository` |

### 1.7 Deployment target / Core Image availability

- `IPHONEOS_DEPLOYMENT_TARGET = 18.5`, `SWIFT_VERSION = 5.0` (`Nizi.xcodeproj/project.pbxproj`).
  This is a very recent minimum — every modern `CIFilter.xyz()` typed-property builtin (e.g.
  `CIFilter.colorControls()`, `CIFilter.exposureAdjust()`, `CIFilter.highlightShadowAdjust()`,
  `CIFilter.temperatureAndTint()`, `CIFilter.vibrance()`, `CIFilter.colorCubeWithColorSpace()`,
  `CIFilter.photoEffectMono()`, `CIFilter.vignette()`, `CIFilter.bloom()`, `CIFilter.
  photoEffectNoir()`), plus `CIImage.autoAdjustmentFilters()`, `CIContext` Metal-backed rendering,
  and `PHImageManager.requestImageDataAndOrientation` are all available with no fallback branches
  needed.
- **Core Image is entirely unused in the codebase today** (`grep -rn "CIContext\|CIFilter\|CIImage"` →
  zero hits outside this plan). Photo Editor's rendering layer is greenfield — no existing
  pipeline to be consistent with, only the general "Infrastructure is the only layer touching
  frameworks" rule to follow.

### 1.8 Tests

- `Testing` (Swift Testing, `struct ... { @Test ... }`), not XCTest —
  confirmed via `NiziTests/AlbumEditingSessionTests.swift:1-9` and every other file in
  `NiziTests/`. Naming convention: `<TypeUnderTest>Tests.swift`, one `struct` per file. Photo
  Editor's Domain-layer tests (`PhotoAdjustments`, `PhotoEditRecipe` codable/migration,
  `AutoEnhanceRules` heuristics, override-priority resolution) follow the same convention with
  zero Photos/SwiftData framework imports, matching how `AlbumEditingSessionTests` tests
  `AlbumEditingSession` purely at the struct level.

---

## 2. What can be reused vs. what must be built new

### Reused directly (no changes needed)
- `PlatformImage` typealias.
- The four-layer module structure and its placement conventions.
- The `@ModelActor` SwiftData repository pattern and additive-migration discipline.
- `NiziLogger` category pattern.
- Bundle-JSON-backed repository pattern (`BundleAlbumLayoutRepository`) for `PresetDefinition`.
- Swift Testing conventions for all new Domain-layer tests.
- The existing `.fullScreenCover(item:)` presentation idiom both viewers already use.

### Reused as a pattern, reimplemented locally (per § 1.1's "no cross-module infra" rule)
- PHAsset-by-localIdentifier lookup.
- PHCachingImageManager-backed request/cancel plumbing (continuation + `withTaskCancellationHandler`).
- Viewer-owned (not page-owned) task lifecycle for in-flight renders.

### Net new
- `Features/PhotoEditor/` — the whole module (Domain/Application/Infrastructure/Presentation).
- Core Image render engine (`PhotoRenderEngine`, reusable `CIContext`, preview vs. full-res APIs,
  orientation normalization).
- `PresetDefinition` catalog (JSON + bundle resource), `PresetRepository`/`BundlePresetRepository`,
  `LUTLoading`/`LUTCube`, `PresetRendering`, and a handful of Core-Image-only *prototype* preset
  implementations (no real LUT files yet, per spec § 7.1/Bước 4 and `photo-editor/ADDEDUM.md`).
  `docs/modules/PHOTO-EDITOR-PRESET-GUIDE.md` ships alongside this sprint.
- `AutoEnhanceService` + `ImageAnalyzer` (histogram/heuristic-based, on-device only).
- Two new `@Model` types (`MDPhotoEditRecipe`, `MDCollectionEditStyle`) + two repositories.
- One-field additions to `PhotoPreviewTarget` (Album) and `CurationPreviewPresentation` (Event) to
  carry the owning collection's id through to the editor.
- `Edit` entry points added to `AlbumPhotoPreviewView` and `CurationPreviewPage`'s toolbar.
- `SaveScopeSheet` (bottom sheet: "chỉ ảnh này" / "áp phong cách cho toàn bộ").
- New `Localizable.xcstrings` keys for every new user-facing string (editor UI, save-scope sheet,
  auto-enhance copy, screenshot warning) — required by `ARCHITECTURE.md` § 5's no-hardcoded-string
  guardrail.

---

## 3. Opening the editor from the existing Photo Viewer

Both viewers gain an `Edit` toolbar button next to their existing close button. Tapping it builds
an `EditorContext` from data already on screen and presents `PhotoEditorView` via
`.fullScreenCover(item:)` — the same idiom both viewers already use for their own presentation, so
no new presentation mechanism is introduced.

- **Album** (`AlbumPhotoPreviewView`): needs `albumId: String` added to its `init` (threaded from
  `AlbumDetailView`'s already-in-scope `draft.id` through `PhotoPreviewTarget`).
  `EditorContext(sourceType: .album, sourceId: albumId, photoId: assignment.photo.sourceIdentifier,
  photoIds: photos.map(\.photo.sourceIdentifier))`.
- **Event** (`CurationPreviewView`/`Page`): needs `eventId: String` added similarly (from
  `EventDetailView`'s `event.id.uuidString`, threaded through `CurationPreviewPresentation`).
  `EditorContext(sourceType: .event, sourceId: eventId, photoId: item.assetID, photoIds:
  items.map(\.assetID))`.
- **Standalone**: no existing single-photo entry point in the app yet (Search/Favorites/Photobook
  don't exist yet either, per spec § 4.4's "khả năng mở rộng" list — all future work). V1 adds a
  minimal SwiftUI preview/harness entry (in the same spirit as
  `AlbumDraftPreviewFactory`/`AlbumDraftPlanningPreview` used for design previews) so `.standalone`
  can be exercised and tested without needing a real Album or Event, satisfying "có thể mở độc lập
  với một ảnh" as a testable, demoable path even before a real caller exists.

Editor closes by returning a `PhotoEditorResult` (per spec § 21) through the same
`.fullScreenCover` dismissal callback shape both viewers already use for their own results (e.g.
`AlbumDetailView`'s `onUpdate`/`onDelete` closures). The calling viewer refreshes its own displayed
image for the edited `photoId` on non-nil `didSave`.

---

## 4. Album / Event integration

- Album and Event never gain edit logic themselves (spec § 24) — they only:
  1. Thread their id into the preview presentation payload (§ 3 above).
  2. Present `PhotoEditorView` with an `EditorContext`.
  3. On `PhotoEditorResult.collectionStyleChanged == true`, nothing else is required of them —
     `CollectionEditStyle` is looked up independently by Photo Editor itself at render time
     wherever a photo is displayed with "inherit collection style" set; Album/Event don't need to
     read or cache it.
- Applying a style to "the whole Album/Event" only ever writes `presetId` + `presetIntensity` to
  one `CollectionEditStyle` row (spec § 3.4/§ 11.4) — **not** N `PhotoEditRecipe` rows. Individual
  photos read the collection style at render time via the priority chain in § 6. This directly
  satisfies the "Không nhân bản recipe giống nhau cho mọi ảnh nếu có thể lưu style ở cấp
  Album/Event" requirement in the spec (§ 9) — there is deliberately no fan-out write across every
  photo in the collection.
- "Tự động cải thiện riêng từng ảnh" (optional, spec § 11.5), when checked, does fan out — but only
  as N independent `AutoEnhanceService.analyze(photoId:)` calls plus N `PhotoEditRecipe` writes
  with `autoEnhanceApplied = true` and `inheritsCollectionStyle = true` (so preset still comes from
  the collection style, only the per-photo correction values are individual). This runs off the
  main actor, batched, with a progress UI that doesn't block the app (spec § 19 last bullet) —
  same non-blocking pattern `EventDetailView.createAlbum()` already uses for its own
  `Task.detached(priority: .userInitiated)` planning work.

---

## 5. Persistence design

### 5.1 New SwiftData models (`Features/PhotoEditor/Infrastructure/`)

```swift
@Model
final class MDPhotoEditRecipe {
    @Attribute(.unique) var photoId: String
    var presetId: String?
    var presetIntensity: Float = 0
    var encodedAdjustments: Data          // JSONEncoder().encode(PhotoAdjustments)
    var autoEnhanceApplied: Bool = false
    var autoEnhanceVersion: String?
    var inheritsCollectionStyle: Bool = true
    var createdAt: Date
    var updatedAt: Date
}

@Model
final class MDCollectionEditStyle {
    @Attribute(.unique) var collectionKey: String   // "\(collectionType.rawValue):\(collectionId)"
    var collectionType: String
    var collectionId: String
    var presetId: String?
    var presetIntensity: Float = 0
    var autoEnhanceEachPhoto: Bool = false
    var createdAt: Date
    var updatedAt: Date
}
```

Both are pure additions to `NiziApp.swift`'s `.modelContainer(for: [...])` array — no existing
model is touched, so there is no destructive migration risk. New optional/defaulted columns follow
`MDAlbumDraft`'s own precedent for safe lightweight migration.

### 5.2 Repositories

`Features/PhotoEditor/Infrastructure/SwiftDataPhotoEditRepository.swift`:
```swift
@ModelActor
actor SwiftDataPhotoEditRepository: PhotoEditRepository, CollectionStyleRepository {
    // getRecipe / saveRecipe / deleteRecipe
    // getStyle(type:id:) / saveStyle
}
```
Same `@ModelActor` shape as `SwiftDataMemoryDiscoveryStore`/`SwiftDataAlbumDraftStore`; constructed
on demand from `modelContext.container` at call sites, never held as a singleton.

### 5.3 No migration of *existing* data required

`PhotoEditRecipe`/`CollectionEditStyle` are wholly new concepts — there is nothing in
`MDAlbumDraft` or `MDLocalAsset` to migrate *from*. "Migration safety" here means: the two new
`@Model` types must ship with sensible defaults on every field from day one (as drafted above) so
that adding further optional fields later (e.g. a V2 undo history) never breaks decoding of rows
written by this V1 — same discipline `MDAlbumDraft` already follows for its own future-proofing.

---

## 6. Collection style / override resolution (spec § 12.4)

Priority, evaluated at render time by `PhotoEditRepository`/`CollectionStyleRepository` together
(no persistence-level join — resolved in Application layer):

```text
1. PhotoEditRecipe exists AND inheritsCollectionStyle == false  → use recipe as-is (full override)
2. PhotoEditRecipe exists AND inheritsCollectionStyle == true   → recipe.adjustments (if any)
                                                                    + CollectionEditStyle's preset/intensity
3. No PhotoEditRecipe, CollectionEditStyle exists                → CollectionEditStyle preset/intensity only
4. Neither exists                                                → Original (no-op recipe)
```

This lives in a small pure-Domain resolver (`CollectionStyleResolver`, testable with plain structs,
no SwiftData import) — mirrors how `AlbumEditActionApplying`/`AlbumDraftValidator` keep Album's own
business rules in Domain/Application, framework-free.

---

## 7. Rendering pipeline (Core Image)

- One `CIContext` created once per `PhotoRenderEngine` instance (GPU-backed, no `options:
  [.useSoftwareRenderer: true]`), held for the editor session's lifetime — never recreated per
  render call (spec § 18.3, "Tái sử dụng `CIContext`").
- Two explicit entry points, matching spec § 20.2 / § 15:
  - `renderPreview(photoId:recipe:targetSize:) async throws -> CGImage` — capped at the same
    ~1000×1000 ceiling the existing viewers already use for `displayPreview`
    (`EventDetailView.swift:32`'s reasoning applies identically here: requesting at full device
    resolution was the actual cause of slow/failed iCloud loads elsewhere in this app).
  - `renderFullResolution(photoId:recipe:) async throws -> CGImage` — only called for
    export/share/save-a-copy/photobook, never for live preview.
- Orientation: use `PHImageManager.requestImageDataAndOrientation(for:options:resultHandler:)` to
  get raw data + `CGImagePropertyOrientation`, then `CIImage(data:).oriented(orientation)` once,
  immediately after load — this is the one supported way to "chuẩn hóa orientation" without ever
  baking a wrong rotation into a later CIFilter chain.
- Slider-driven re-renders are debounced and **owned by `PhotoEditorViewModel`**, not by whatever
  SwiftUI view is currently on screen — replaying the exact lesson from § 1.5 (`CurationPreviewView`
  already had to solve "TabView recycles pages mid-flight and cancels their in-flight task" once;
  Photo Editor must not relearn it). A new render request cancels the previous one via a single
  `Task` reference held on the view model, not a page-level `.task(id:)`.
- No `UIImage(cgImage:)`/`CIImage(image:)` round-trips inside the adjustment pipeline itself — load
  once to `CIImage`, apply the whole filter chain in `CIImage` space, convert to `CGImage` exactly
  once at the end via `CIContext.createCGImage(_:from:)`.

---

## 8. Preset model

Superseded/expanded by `docs/modules/photo-editor/ADDEDUM.md` ("BỔ SUNG — CÁCH XÂY DỰNG PRESET
CHO PHOTO EDITOR"), which arrived after this plan's first draft and is the authoritative preset
architecture for Bước 4. Summary of what it changes vs. this document's original § 8:

- `PresetDefinition` grows from the spec's 9-field version to a ~20-field struct (id, name,
  shortName, `lutResource`/`lutDimension`, per-channel tone offsets (`exposureOffset`,
  `contrastOffset`, `saturationOffset`, `warmthOffset`, `highlightsOffset`, `shadowsOffset`),
  texture params (`grainAmount`/`grainSize`, `bloomAmount`/`bloomRadius`,
  `vignetteAmount`/`vignetteRadius`), `protectSkinTones`, `isMonochrome`, `thumbnailAssetName`,
  `sortOrder`, `isActive`) — still `Codable, Identifiable, Equatable`, still bundle-JSON-backed
  (`Resources/Presets/presets.json`, plus one `.cube` file per LUT-based preset), still loaded
  through a `PresetRepository` abstraction (`BundlePresetRepository` implementation) — same
  "JSON + app bundle, decode once, no network" shape as `BundleAlbumLayoutRepository`, just a
  richer schema. `PresetRepository` validates on load (unique ids, intensity in 0...1, referenced
  LUT resource exists, `original` preset present with intensity 0) and drops — never crashes on —
  any single malformed preset entry, logging and continuing with the rest.
- A new `LUTLoading` protocol + `LUTCube` value type (dimension, raw `Data`, `CGColorSpace`) parses
  `.cube` files once and caches the parsed result — never reparsed on every slider drag. No LUT
  files exist yet in this repo and none may be fetched from the internet or embedded without a
  clear license (ADDEDUM § 3.1, § 14.11-12) — V1 ships **prototype presets only**, built purely
  from stock `CIFilter`s (`colorControls`, `temperatureAndTint`, `vignette`, `photoEffectMono`),
  each explicitly flagged `prototypePreset = true` in code and docs (ADDEDUM § 5, § 14.10). This is
  consistent with this plan's original call for "no real LUT files yet" — the addendum just gives
  the swap-in path (`lutResource` + `PresetRendering`'s ColorCube branch) far more precise shape.
- `PresetRendering.applyPreset(_:intensity:to:)` splits the pipeline into two blended groups (per
  ADDEDUM § 8): **color style** (LUT + tone/contrast/warmth/saturation/highlight-shadow), blended
  linearly against the input by `intensity`; and **texture style** (grain/bloom/vignette), blended
  by preset-defined *non-linear* coefficients of `intensity` (texture doesn't fade at the same rate
  color does — ADDEDUM § 8.2's worked example). The user still only ever sees one slider; the
  internal color-vs-texture split is invisible.
- Preset thumbnails are rendered from **the actual photo being edited**, not a fixed asset — resize
  the current image small, render every preset at its default intensity, cache by `photoId +
  presetId` for the session's lifetime only, cancel the batch if the editor closes mid-render
  (ADDEDUM § 11). This replaces this plan's original "small fixed-size thumbnail cache" framing
  with a concrete per-photo/per-preset cache key and an explicit cancellation requirement.
- A new required deliverable: `docs/modules/PHOTO-EDITOR-PRESET-GUIDE.md`, documenting how to add a
  preset, swap a LUT, tune default intensity/grain/bloom/vignette, test a LUT, disable a preset,
  and the color-space constraints — written at Bước 4, not before (nothing to document yet).

Everything else in this document's Bước 4 sprint scope (§ 10 below) is unchanged — this section
exists so Bước 4 doesn't need to be re-planned when it starts, since the addendum's shape is now
locked in.

---

## 9. Risks

| Risk | Mitigation |
|---|---|
| SwiftUI `TabView` page recycling cancels in-flight render tasks mid-slider-drag | Viewer/view-model-owned task lifecycle (§ 1.5, § 7) — a solved problem in this codebase already, just needs to be replicated |
| iCloud-only original not yet downloaded when Export/Save is tapped | Preview always works off whatever's locally available; full-res render surfaces a "downloading original" state rather than blocking the whole UI (spec § 15.3) — same asynchronous-upgrade posture the existing viewers already use for thumbnails |
| Large/high-megapixel photos spiking RAM during full-res render | `CIContext` GPU path + `autoreleasepool` around each full-res render call; full-res `CGImage` is never held longer than the export/share/save call that produced it |
| Threading `albumId`/`eventId` into two existing, actively-used views (`AlbumPhotoPreviewView`, `CurationPreviewView`) | Small, additive, non-breaking signature changes (one new `let` each) — verified both call sites already have the id in scope, just not passed down |
| Auto Enhance producing an opaque/unadjustable result | Kept strictly rule-based (histogram + brightness/highlight/shadow heuristics) and expressed as ordinary `PhotoAdjustments`, so it's just a pre-fill of the Adjust tab, not a hidden filter (spec § 9.3) |
| Screenshot / Live Photo / video assets reaching the editor | Gate the `Edit` entry point on `PHAsset.mediaType == .image` before showing it at all (spec § 17.2); Live Photo still resolves to its still image via the same `.current`-version request already used elsewhere, with a save-time notice that it becomes a static photo (spec § 17.3); screenshot shows a non-blocking inline notice, never a hard block (spec § 17.1) |
| New `@Model` types breaking `.modelContainer` schema resolution for existing users | Both new types are pure additions with defaulted columns — no existing `@Model` type or column is touched, so SwiftData's lightweight migration applies the same way `MDAlbumDraft`'s own additive history already has |
| Scope creep into masks/brush/HSL/etc. | Explicitly out of scope per the spec and the task instructions — not attempted at any sprint boundary below |

---

## 10. Sprint plan

Each sprint below ends with: build succeeds (build-only — the user tests on-device themselves, per
standing project preference), progress is reported (files created/changed, what's done/not done,
build result, risks, commit hash) — no sprint starts until the previous one builds clean.

1. ✅ **Editor foundation** (`94d1690`) — `EditorContext`, `PhotoEditorView`, `PhotoEditorViewModel`,
   `PhotoEditSession`, preview load from `PHAsset` (no presets/adjust yet), Cancel/Save, press-and-
   hold original, unsaved-changes detection, openable standalone via a small preview harness.
2. ✅ **Rendering foundation** (`16b326a`) — `PhotoRenderEngine`, one reusable `CIContext`, preview
   vs. full-res APIs, orientation normalization, render-request cancellation owned by the view
   model.
3. ✅ **Preset** (`2768ead`) — `PresetDefinition` + bundle JSON, 8 prototype presets on stock
   CIFilters (real `.cube` LUT loader built but unused — no licensed LUT embedded yet), intensity
   slider 0–100%, per-preset default intensity, thumbnail cache for the session, Reset to Original,
   `docs/modules/PHOTO-EDITOR-PRESET-GUIDE.md`.
4. ✅ **Adjust** (`4b5b19f`) — the six sliders (exposure/contrast/highlights/shadows/warmth/
   saturation), UI range -100…+100 mapped to each filter's native range via shared
   `PhotoToneAdjuster`, per-field reset, reset-all-Adjust, reset-all.
5. ✅ **Auto Enhance** (`1696a99`) — `ImageAnalyzer` (real pixel/histogram sampling) +
   `AutoEnhanceRules` (pure, unit-tested heuristics) → `PhotoAdjustments`, surfaced in the Adjust
   tab, undoable, no hidden filter.
6. ✅ **Persistence** (`40d72be`) — `MDPhotoEditRecipe`, `SwiftDataPhotoEditRepository`,
   `NiziApp.swift` model-container registration, recipe restore on reopen (standalone harness
   switched to the real repository so this is actually exercised, not simulated).
7. ✅ **Album/Event integration** (`5f310e9`) — `albumId`/`eventId` threaded through the two
   existing preview views, `Edit` entry points added, `SaveScopeSheet`, "apply to whole collection"
   write path (§ 4), `MDCollectionEditStyle`/`SwiftDataCollectionStyleRepository`.
8. ✅ **Collection style + override** (`e4789e4`) — `CollectionStyleResolver` priority chain (§ 6),
   editor pre-populates a photo's inherited style on open, save sets `inheritsCollectionStyle`
   correctly, small inheriting/custom indicator in the Preset tab.
9. 🔶 **Testing and performance hardening** — `docs/modules/PHOTO-EDITOR-TEST-CHECKLIST.md` written
   (the full on-device matrix: landscape/portrait, large files, iCloud-not-local, screenshot, Live
   Photo, Photos-app-edited, large Album/Event, rapid preset/slider changes, cancel-unsaved,
   reopen-saved-recipe, style changes, per-photo override, reset-to-original, plus RAM/main-thread/
   render-latency/cancellation/cache-lifecycle) — actual execution is manual, on-device, by the
   user. One concrete fix landed from a code-level self-audit: `PhotoRenderEngine.render(_:)` now
   wraps `CIContext.createCGImage` in `autoreleasepool` (§ 18.3), previously missing.

**Known, deliberately out-of-scope gap** (flagged at Bước 8 and Bước 9, not fixed in Bước 10):
Album's and Event's own photo *display* — `AlbumPhotoView`/`ApplePhotosAlbumPhotoProvider`,
`EventDetailView`'s `PhotoAssetProvider`-based thumbnails — does not render through
`PhotoRenderEngine`/`CollectionStyleResolver`. A saved edit is fully persisted and correctly
resolved, but has no visible effect outside the editor itself yet. Retrofitting those existing,
actively-used display pipelines to become recipe-aware is a substantial cross-cutting change
distinct from "add an Edit entry point" or "resolve which style applies" — it would need its own
scoped pass, not a silent expansion of Bước 8/9.

This is 9 build checkpoints rather than the spec's own 6 "Sprints," since it follows the more
granular Bước 2–10 breakdown given in the task instructions (Bước 1, this document, is done).

## 11. Follow-up — real LUTs replaced the prototype presets

After Bước 10, the user provided 13 of their own licensed "Presetpro" `.cube` LUT packs and asked
for them to become the real preset catalog, confirming commercial-app-distribution rights directly
(ADDEDUM § 3.1/§ 14's required license check). `presets.json`'s 8 Sprint-3 prototype color
presets (Core Image tone adjustments only, no LUT) were **replaced** — not appended to — with 13
real-LUT presets (`isPrototype: false`): `classic-film`, `bold-film`, `cine-grade`, `creatives`,
`chrome`, `retro-64`, `lomo`, `moody-aqua`, `nomad`, `palm-springs`, `santorini`, `brooklyn`,
`vintage-fox`. Three of the source pack's own literal names were renamed to avoid reusing a
camera/film-stock trademark (ADDEDUM § 14.14) — `Fuji Film` → `Classic Film`, `Elite Chrome` →
`Chrome`, `Kodachrome 64` → `Retro 64` — and `Lomography` shortened to `Lomo`. Two other source
packs were excluded outright: three Lightroom `.xmp` presets (wrong format — no `.cube` at all) and
a Fujifilm X100VI camera Log-conversion pack (built for grading flat log footage, not stills — see
`PHOTO-EDITOR-PRESET-GUIDE.md` § 9 for the full accounting). This intentionally exceeds V1's own
"dưới 10 preset" guidance (§ 452 above) — that cap was about not over-investing in hand-designed
prototype color, which no longer applies once the presets are real, already-graded, licensed LUTs.
`BundlePresetRepositoryTests`/`BundledLUTPresetsTests` were updated accordingly.

## 12. Follow-up — intensity amplification and a LUT management screen

Two more pieces of direct user feedback after trying the real LUTs on-device:

1. "Áp dụng LUTs đã có hiệu quả nhưng khác biệt chưa rõ. Tôi cần tăng độ khác biệt lên khoảng 150%"
   — a plain 1:1 LUT application read as too subtle. `PresetRenderer`'s color blend now amplifies
   by `colorIntensityAmplification = 1.5` (100% UI intensity → 150% of a single LUT application,
   extrapolated past the raw result rather than capped at it). Required rewriting the blend
   formula itself (RGB-channel scaling + `CIAdditionCompositing` instead of alpha-scaling +
   `over`-compositing, since alpha can't exceed `1.0` — see `PHOTO-EDITOR-PRESET-GUIDE.md`'s Update
   2). Texture (grain/bloom/vignette) is deliberately not amplified the same way.

2. "Tôi cần 1 màn hình quản lý LUTs (thêm bớt, active, đặt tên cho các LUTs)" — a LUT Manager screen
   (`Home → Diagnostics → Photo Editor → LUT Manager`). Since an installed app can never rewrite
   its own bundle, this is a *runtime* customization layer, not a `presets.json` editor:
   `MDPresetOverride` (active/name overrides for a bundled preset) and `MDCustomPreset` (fully
   user-imported presets, `.cube` copied into `Documents/CustomLUTs/`) are new SwiftData models;
   `CustomizablePresetRepository` merges bundled + overrides + custom and implements both the
   existing `PresetRepository` (unchanged signature — every render call site keeps working
   untouched) and a new `PresetManaging` protocol (the CRUD surface, used only by the management
   screen). Every real call site (Album, Event, standalone) now constructs
   `CustomizablePresetRepository` instead of `BundlePresetRepository` directly, so a customization
   actually affects what the editor shows — see `PHOTO-EDITOR-PRESET-GUIDE.md` § 10 for the full
   design. `CustomizablePresetRepositoryTests` covers the merge/override/import/remove logic.
