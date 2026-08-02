# SURVEY — Photo Pipeline & UI Performance

**Status:** Survey only. No code was modified while producing this document.
**Scope:** ~105,000-photo library; screens covered: Home, Event (list/detail/grid/viewer), Memory (detail/gallery), Trip (detail/gallery), Album (list/detail/viewer), Photo Editor.
**Method:** Direct source reading + `grep` across `Nizi/`. Every claim below cites `file:line`. Where something could not be verified from the code read during this pass, it is marked **"not verified in this pass"** rather than guessed.

---

## 1. Summary (read this first)

The app does not have **one** photo pipeline — it has at least **three architecturally different ones** that evolved independently and never got reconciled:

| Pipeline | Screens | Manager instance | Cache | Concurrency bound | Progressive tiers |
|---|---|---|---|---|---|
| **MemoryDiscovery** | Home, Event list/grid, Memory, Trip cards | `PhotoKitAssetProvider` (own `PHCachingImageManager`) | 1 `static` `NSCache`, shared app-wide | Only when routed through `PhotoThumbnailRequestLoader` (not all call sites are) | Ad hoc per screen (2-tier in some, none in others) |
| **CurationPreviewView** (Event/Trip full-screen viewer) | Event Detail's grid+viewer, Trip Detail's viewer | same `PhotoKitAssetProvider` as above, via `assetProvider` param | same shared `NSCache` | `ViewerSeedThrottle` actor, `maxConcurrent: 3` | Real 3-tier: `gridThumbnail`(160)→`viewerSeed`(400)→`displayPreview`(1000) |
| **AlbumPhotos** | Album list/detail/viewer, Album crop sheet | **fresh `PHCachingImageManager` per `ApplePhotosAlbumPhotoProvider()` instance** — 9 separate construction sites | **fresh `NSCache` per instance too** (`AlbumImageCache`) | none | PhotoKit's own `.opportunistic` degraded→final, not an explicit tier list |

This split is the root of most findings below: the CurationPreviewView pipeline (§9, §11) is genuinely well-engineered with real cancellation, dedup, and a documented history of two prior bug fixes (black-screen, native-resolution-too-slow). The plain grid/card cells used everywhere else (§3, §7) mostly bypass that machinery and call PhotoKit directly on whatever actor happens to be running, which is the main thread for every SwiftUI `.task`.

---

## 2. Architecture Survey — the flow from UI to pixel

There is no single flow; there are three, matching §1.

### 2a. MemoryDiscovery pipeline (Home / Event grid cells / rail cards)

```
View (.task)
  ↓
PhotoAssetProvider protocol   — Nizi/Features/MemoryDiscovery/Domain/PhotoAssetProvider.swift:13
  ↓
PhotoKitAssetProvider         — Nizi/Features/MemoryDiscovery/Infrastructure/PhotoKitAssetProvider.swift:13
  (owns PHCachingImageManager, PHAsset.fetchAssets, NSCache)
  ↓
PHImageManager.requestImage() — PhotoKitAssetProvider.swift:155
  ↓
UIImage (PlatformImage)       — delivered straight to callback, no separate decode step in app code
  ↓
@State image                  — set directly in the SwiftUI View that made the call
  ↓
SwiftUI Image(uiImage:)       — rendered
```
Some call sites (not all — see §3) go through an extra hop:
```
View (.task) → PhotoThumbnailRequestLoader (actor) → PhotoKitAssetProvider → PHImageManager
```
`PhotoThumbnailRequestLoader` — `Nizi/Features/MemoryDiscovery/Presentation/TripMiniCard.swift:107-154` (despite the filename, this actor is now shared: it's referenced from `HomeView.swift`, `MemoryDetailView.swift`, and `TripDetailView.swift` too).

### 2b. CurationPreviewView pipeline (Event/Trip full-screen viewer)

```
EventDetailView / TripDetailView
  ↓ (tap a grid cell)
CurationPreviewPresentation (Identifiable struct) — EventDetailView.swift:41
  ↓
CurationPreviewView            — EventDetailView.swift:769
  ├─ seedTasks / seedThrottle (actor, maxConcurrent 3)   — EventDetailView.swift:812-817, 1215
  ├─ displayPreviewTasks (viewer-owned, not page-owned)  — EventDetailView.swift:829
  ↓
CurationPreviewPage            — EventDetailView.swift:1265
  ↓
PhotoAssetProvider.requestThumbnail (same provider as §2a)
```

### 2c. AlbumPhotos pipeline (Album list/detail/viewer/crop)

```
AlbumPhotoView                 — Nizi/Features/AlbumPhotos/Presentation/AlbumPhotoView.swift:24
  ↓ (.task(id: requestKey))
AlbumPhotoProviding protocol (environment-injected)
  ↓
ApplePhotosAlbumPhotoProvider  — Nizi/Features/AlbumPhotos/Infrastructure/ApplePhotosAlbumPhotoProvider.swift:13
  (owns its own PHCachingImageManager + its own AlbumImageCache)
  ↓
PHImageManager.requestImage()  — ApplePhotosAlbumPhotoProvider.swift:75
  ↓
AsyncStream<AlbumPhotoLoadState> (.loading / .degraded / .success / .missing / .failure)
  ↓
AlbumPhotoView body switch     — AlbumPhotoView.swift:74-87
```

### 2d. Photo Editor pipeline (separate again)

```
PhotoEditorViewModel (@MainActor)  — Nizi/Features/PhotoEditor/Presentation/PhotoEditorViewModel.swift:42
  ↓
PhotoRenderEngine                  — Nizi/Features/PhotoEditor/Infrastructure/PhotoRenderEngine.swift:22
  (its own PHCachingImageManager, CIContext; deliberately never touches UIImage — CGImage/CIImage only)
  ↓
PHImageManager.requestImage() / requestImageDataAndOrientation()
  ↓
CGImage (preview) / raw Data (full-res export)
```

---

## 3. Photo Request Pipeline — every `PHImageManager`/`PHCachingImageManager` call site

| # | File:line | Screen(s) | targetSize | contentMode | deliveryMode | resizeMode | sync? | networkAccessAllowed |
|---|---|---|---|---|---|---|---|---|
| 1 | `PhotoKitAssetProvider.swift:155` | Home rails, Event grid, Memory/Trip covers — the shared low-level provider used by almost everything in §2a/2b | caller-supplied | caller-supplied | caller: `.fastFormat` or `.highQualityFormat` (`.swift:143`) | `.fast` (`:144`) | `isSynchronous = false` (`:146`) | caller-supplied |
| 2 | `PhotoRenderEngine.swift:133` (`requestBoundedImage`) | Photo Editor preview render | caller-supplied | `.aspectFit` (`:134`) | `.highQualityFormat` (`:122`) | `.fast` (`:123`) | `false` (`:125`) | `true` (`:124`) |
| 3 | `PhotoRenderEngine.swift:171` (`requestImageDataAndOrientation`) | Photo Editor full-res export path | n/a (full data) | n/a | n/a (data request has no delivery mode) | n/a | `false` (`:163`) | `true` (`:162`) |
| 4 | `AutoEnhanceService.swift:56` | Photo Editor auto-enhance analysis | not read in this pass | not read in this pass | not read in this pass | not read in this pass | not read in this pass | not read in this pass |
| 5 | `PhotoAssetExporter.swift:58` | Photo Editor "save as new asset" export | n/a (data request) | n/a | n/a | n/a | not read in this pass | not read in this pass |
| 6 | `ApplePhotosAlbumPhotoProvider.swift:75` | Album list, Album detail, Album viewer, Crop sheet | caller-supplied (`request.targetPixelSize`) | `.aspectFill`/`.aspectFit` from `request.contentMode` (`:73`) | `.opportunistic`/`.fastFormat`/`.highQualityFormat` mapped from `AlbumPhotoDeliveryMode` (`:117-123`); **`AlbumPhotoView.load` always passes `.opportunistic`** (`AlbumPhotoView.swift:177`) | `.fast` (`:64`) | `false` (implicit default; not set to `true` anywhere) | `true`, hardcoded (`:63`, comment: "required for iCloud-only assets") |

Note on row 6: `.opportunistic` delivery can invoke its completion handler **twice** (a degraded pass, then the final image) — this is used intentionally here (`AlbumPhotoLoadState.degraded`/`.success`, `ApplePhotosAlbumPhotoProvider.swift:90-98`). This is the opposite choice from row 1's caller comment at `PhotoKitAssetProvider.swift:138-142`, which explicitly avoids `.opportunistic` "since that can call the completion handler twice and would break the single-resume `withCheckedThrowingContinuation`." Both are internally consistent with their own call site, but the two pipelines made **opposite architectural decisions** about the same PhotoKit option.

### Callers of row 1 (`PhotoKitAssetProvider.requestThumbnail`) — where targetSize/deliveryMode actually come from

| Caller | File:line | targetSize | deliveryMode | networkAccessAllowed | Routed through `PhotoThumbnailRequestLoader`? |
|---|---|---|---|---|---|
| `LovedMemoryCard` (Home hero+rail) | `HomeView.swift` (`.task(id: event.coverAssetID)` block, `LovedMemoryCard` struct) | card size × 2 | placeholder: `.fast`; final: `.highQuality` | placeholder: `false`; final: `true` | Yes |
| `LatestMemoryCard` (Home "your latest memory") | `HomeView.swift` (`LatestMemoryCard` struct) | `size * 2` where `size = UIScreen.main.bounds.width - 48` | placeholder `.fast` / final `.highQuality` | placeholder `false` / final `true` | Yes |
| `TripMiniCard` (Home Trip rail) | `TripMiniCard.swift:82-99` | `cardWidth*2 × cardHeight*2` = 480×720 | `.fast`→`.highQuality` via loader | `false`→`true` | Yes |
| `PhotobookThumbnail` (Home Album rail) | `HomeView.swift` (`PhotobookThumbnail` struct) | 400×400 (constant passed by `AlbumMiniCard`) | `.highQuality` | `true` | Yes |
| `TripListRow` (Trips List) | `TripsListView.swift:175-186` | 60×60 (`thumbnailSize`) | `.fast` | `false` | **No** — calls `assetProvider.requestThumbnail` directly |
| `EventArchiveRow` (Events List) | `EventListView.swift:643-673` | 120×120 (`thumbnailPixelSize`) | `.fast` | `false` | **No** — direct call |
| `EventPhotoCell` (Event Detail grid) | `EventDetailView.swift:741-749` | 160×160 (`ImageSizing.gridThumbnail`) | `.highQuality` | `false` | **No** — direct call |
| `TripPhotoImage` (Trip Detail hero+gallery) | `TripDetailView.swift` (`TripPhotoImage` struct) | placeholder 40×40, final caller-supplied (1400×2100 for hero) | `.fast`→ caller-supplied for final | `false`→`true` | Yes |
| `MemoryDetailImage` (Memory Detail hero+gallery) | `MemoryDetailView.swift` (`MemoryDetailImage` struct) | placeholder 40×40, final 480×480 (gallery) / 1400×2100 (hero) | `.fast`→`.highQuality` | `false`→`true` | Yes |
| `SelectionThumbnailCell` (Memory selection editor) | `MemorySelectionEditView.swift:96-131` | 200×200 (`targetSize`) | `.fast` | `false` | **No** — direct call, and see §12 for a duplicate-request note |
| `CurationPreviewPage`/seed logic | `EventDetailView.swift:1074-1188, 1539-1560` | 400×400 (`viewerSeed`) / 1000×1000 (`displayPreview`) | `.highQuality` | `true` | No (uses its own `ViewerSeedThrottle` actor instead, §2b) |

---

## 4. Thumbnail Strategy — target size per screen

| Screen | Requested pixel size | File:line |
|---|---|---|
| Home — Loved Memories rail (non-hero) | `132pt × 172pt × 2` device scale (`cardWidth`/`cardHeight` in `LovedMemoryCard`) | `HomeView.swift` |
| Home — Loved Memories Hero | `UIScreen.main.bounds.width × (height * 700/874) × 2` | `HomeView.swift` |
| Home — "Your latest memory" square | `(screenWidth-48) × 2` both axes | `HomeView.swift` |
| Home — Trip rail | 480 × 720 (240×360 card × 2) | `TripMiniCard.swift:19` |
| Home — Album rail | 400 × 400 (constant, not tied to the 128pt on-screen tile size) | `HomeView.swift` (`AlbumMiniCard.coverImage`, comment: "match Memory/Trip's quality-first display tier") |
| Trips List row | 120 × 120 for a 60pt on-screen thumbnail (2×) | `TripsListView.swift:136` |
| Events List row | 120 × 120 for a 60pt on-screen thumbnail (2×) | `EventListView.swift:571` |
| Event Detail grid cell | 160 × 160, fixed regardless of actual on-screen cell size (3-column grid, cell size varies by device width) | `EventDetailView.swift:16` |
| Memory Detail gallery | 480 × 480 (`galleryThumbnailSize`, recently reduced from 600×600) | `MemoryDetailView.swift` |
| Trip Detail gallery | caller-supplied per cell in the waterfall layout (not a single fixed constant — sized per row's computed height) | `TripDetailView.swift` |
| Memory selection editor cell | 200 × 200 for a 92pt on-screen cell (~2.17×) | `MemorySelectionEditView.swift:102, 113` |
| Curation/Full-screen viewer | 400×400 seed → 1000×1000 preview | `EventDetailView.swift:25, 32` |
| Album grid/detail/viewer | measured via `GeometryReader` × `UIScreen.main.scale` when no explicit `targetSize` is given | `AlbumPhotoView.swift:58-59` |

**Is anything requested too large?** Two things stand out:
- Event Detail grid (row §3) requests `.highQuality` at 160×160 with `networkAccessAllowed: false` — quality tier for a fixed small size is unusual (row-1 quality tiers elsewhere use `.fast` for grid-sized requests), though the size itself is not oversized.
- The old native-screen-resolution request for the full-screen viewer was already identified and fixed per the comment at `EventDetailView.swift:26-29` — capped at 1000×1000 specifically because "requesting at full screen resolution... was the actual cause of 'ảnh đầu tiên mất rất lâu hoặc không mở được'" (documented, not speculative — this is a comment describing a prior fix, still in the code).

---

## 5. Progressive Loading

Only **one** of the three pipelines has an explicit, named multi-tier design:

- **CurationPreviewView**: `gridThumbnail` (160) → `viewerSeed` (400, "guaranteed floor tier") → `displayPreview` (1000) → *(reserved, unimplemented)* `zoomDetail`. Documented at `EventDetailView.swift:14-33`. The `viewerSeed` tier exists specifically because `startCachingImages` alone was found to be "only a best-effort hint, not a guarantee" (`:18-24`) — i.e., an earlier, thumbnail→original-only design produced a real black-screen bug, and this 3-tier design is the fix.

- **Home rail cards / Memory·Trip Detail galleries** (`LovedMemoryCard`, `LatestMemoryCard`, `TripPhotoImage`, `MemoryDetailImage`): a 2-tier design — 40×40 local-only placeholder (`networkAccessAllowed: false`), then the real target size (`networkAccessAllowed: true`). No named "preview" middle tier; jumps straight from a 40px placeholder to full target size.

- **Trips List / Events List rows, Event Detail grid cells, Memory selection editor**: **single-tier, no progressive loading**. One `requestThumbnail` call at the final target size; nothing shown before it resolves except a flat color (`Color.secondary.opacity(0.15)` / `Color.white.opacity(0.09)`).

- **Album pipeline**: not an explicit tier list, but functionally 2-stage via PhotoKit's own `.opportunistic` delivery (`.degraded` then `.success`, `AlbumPhotoView.swift:77-81`) — this is PhotoKit's built-in progressive behavior, not an app-authored tier.

- **Photo Editor**: no progressive loading — `requestBoundedImage` requests one size for the live preview; there is no lower-quality placeholder shown while that resolves (not verified whether `PhotoEditorViewModel` shows *anything* — a spinner or the pre-edit thumbnail — while `refreshPreview()` is in flight; not traced in this pass).

---

## 6. Layout Stability

Findings, cause of "giao diện bị vỡ":

- **Event Detail grid cell** deliberately avoids a real layout-stability bug: the comment at `EventDetailView.swift:688-691` explicitly documents that driving the square size off the `Image`/`ZStack` directly (rather than off `Color.clear.aspectRatio(1, contentMode: .fit)`) "is what caused cells to overlap/overflow" — a bug that was found and fixed. The current code is layout-stable for this cell: only the bitmap changes, not the frame.

- **`AlbumPhotoView.imageView`** (`AlbumPhotoView.swift:96-142`) computes `baseFillSize` from the *loaded image's own pixel size* (`Self.aspectSize(imageSize: image.size, ...)`, `:110`). Before an image has loaded, this code path isn't reached at all (`content(pixelSize:)` switches to `loadingView` while `.idle`/`.loading`, `:74-76`) — so there's no mid-flight frame jump for a single load, but every *new* load (`.task(id: requestKey(pixelSize:))`, `:54`) that changes `requestKey` re-enters `.loading` state first (`load(pixelSize:)`, `:176`), which swaps the content to `loadingView` (a flat `ProgressView`) before the new image arrives — a visible flash back to a placeholder, not a stable in-place bitmap swap. `requestKey` includes the pixel size (`:68-70`), so this can be retriggered by geometry changes, not just asset-ID changes.

- **The `.scaleEffect`/hit-test mismatch bug** (already found and fixed earlier, not re-introduced): `AlbumPhotoView.swift:98-109`'s own comment documents that an earlier version used `.scaleEffect(crop.scale)` — a pure render transform that enlarges the drawn pixels without shrinking the view's hit-test bounds to match — causing tap targets to bleed into neighboring UI. The current code replaces the transform with a real `.frame()` size (`:113`) specifically to make hit-test bounds and rendered bounds the same value, closing that gap. This exact bug class (hit-test area not matching the visually-clipped image) also caused a Home-rail tap-bleed regression this session, fixed the same way (`.contentShape(Rectangle())` pinned to the card's own frame — see `TripMiniCard.swift:55` and `HomeView.swift`'s card call sites).

- **Aspect-ratio-driven layout in Memory/Trip Detail**: both `MemoryDetailView` and `TripDetailView` build a justified-row waterfall gallery from `imageAspects: [String: CGFloat]`, populated by an `onAspectAvailable` callback fired only once the image finishes loading (`MemoryDetailImage`/`TripPhotoImage`'s `.task`). This means a row's height is not known until its photos' aspect ratios have loaded — rows below an in-flight row can shift down once it resolves. This is a real, structural (not a bug — it's how the justified layout works) source of vertical content shift while scrolling through not-yet-loaded rows.

---

## 7. Thread Analysis

| Step | Actor / thread | Evidence |
|---|---|---|
| `PhotoKitAssetProvider.requestThumbnail` — synchronous prefix (`PHAsset.fetchAssets(withLocalIdentifiers:)`) | **Whatever actor the caller is on.** `PhotoKitAssetProvider` is a plain `final class` (`PhotoKitAssetProvider.swift:13`), not an `actor`, not `@MainActor`-annotated. A SwiftUI `.task {}` closure runs on `@MainActor` by default. | `PhotoKitAssetProvider.swift:131` (`PHAsset.fetchAssets(...).firstObject`) — this line executes before the first `await` in the function, so it runs synchronously in the caller's actor context. |
| Same synchronous PHAsset lookup, routed through `PhotoThumbnailRequestLoader` | **Off Main** — `PhotoThumbnailRequestLoader` is a real `actor` (`TripMiniCard.swift:107`), so calling `.thumbnail(...)` from a `.task` hops onto that actor's own executor before reaching `PhotoKitAssetProvider`'s synchronous code. | `TripMiniCard.swift:107, 125-132` |
| Same synchronous PHAsset lookup, called **directly** (not via the loader) | **Main Actor** — confirmed direct call sites: `TripsListView.swift:180` (`TripListRow.loadCover`), `EventListView.swift:656` (`EventArchiveRow.startThumbnailLoad`, itself started from a plain `Task {}` at `:652`, which inherits the enclosing `@MainActor` SwiftUI context), `EventDetailView.swift:742` (`EventPhotoCell`'s `.task`), `MemorySelectionEditView.swift:126` (`SelectionThumbnailCell`'s `.task`). | listed file:lines |
| `PhotoRenderEngine.fetchAsset` (`PHAsset.fetchAssets(withLocalIdentifiers:)`) | **Main Actor** — `PhotoRenderEngine` is a plain class (`PhotoRenderEngine.swift:22`), called from `PhotoEditorViewModel`, which is `@MainActor` (`PhotoEditorViewModel.swift:42`). No actor hop exists between the two. | `PhotoRenderEngine.swift:118-119, 158-159, 196-199`; `PhotoEditorViewModel.swift:42` |
| `ApplePhotosAlbumPhotoProvider.loadImage` | Called from inside a plain `Task { ... }` (`ApplePhotosAlbumPhotoProvider.swift:47`), not an actor-isolated method — inherits whatever context `AlbumPhotoView.load(pixelSize:)`'s `.task` runs on, i.e. Main Actor (`AlbumPhotoView.swift:54-56, 174-190`). `assetResolver.asset(localIdentifier:)` is `await`ed (`:52`) — its own actor isolation was not traced in this pass. | `ApplePhotosAlbumPhotoProvider.swift:47-52`; `AlbumPhotoView.swift:174` |
| `PHImageManager.requestImage`'s **completion callback** (all pipelines) | PhotoKit's own documented behavior: delivered on an arbitrary background queue, not guaranteed Main. Every call site wraps this in `withCheckedThrowingContinuation`/`withCheckedContinuation` and resumes a `Task`, so the `await`ing caller resumes on its own actor — this part is standard/correct everywhere it was checked (`PhotoKitAssetProvider.swift:154-185`, `PhotoRenderEngine.swift:131-155`, `ApplePhotosAlbumPhotoProvider.swift:75-99`). | as cited |
| Decode of the returned `UIImage` | Not separately visible in app code anywhere — `PHImageManager.requestImage` hands back an already-decoded, ready-to-draw `UIImage`. No manual `UIGraphicsImageRenderer`/`CGImageSourceCreateThumbnailAtIndex`/`.preparingForDisplay()` call was found anywhere in `Nizi/Features/` (see §8). | grep, no matches |
| Vision analysis (face/quality/duplicate scoring) | `Task`/`withTaskGroup` inside `VisionEventPhotoAnalyzer` (`VisionEventPhotoAnalyzer.swift:114-136`) — this runs only during the **background scan/discovery pipeline**, not in response to any live UI screen opening a photo. No call site in a `Presentation/` file was found. | `VisionEventPhotoAnalyzer.swift`; no reverse references from `Presentation/` |

**Summary — confirmed Main-Actor-blocking call sites** (synchronous `PHAsset.fetchAssets` executing before any `await`, in a context reachable directly from a SwiftUI `.task`, i.e., Main Actor):
1. `TripsListView.swift:180` (via `PhotoKitAssetProvider.swift:131`)
2. `EventListView.swift:656` (via `PhotoKitAssetProvider.swift:131`)
3. `EventDetailView.swift:742` (via `PhotoKitAssetProvider.swift:131`) — **this is the Event Detail grid, i.e., the screen named first in the user's own report**
4. `MemorySelectionEditView.swift:126` (via `PhotoKitAssetProvider.swift:131`)
5. `PhotoRenderEngine.swift:119` and `:159` (via `PhotoEditorViewModel`'s `@MainActor` context)

---

## 8. Decode Pipeline

- **No manual decode step exists in app code.** Every image-producing call in `Nizi/Features/` terminates at a `PHImageManager` completion handler that already hands back a `UIImage` (`PhotoKitAssetProvider.swift:172-183`) or a `CGImage` (`PhotoRenderEngine.swift:145-149`, via `.cgImage` on the `UIImage` PhotoKit returns) or raw `Data` (`PhotoAssetExporter.swift:58`, `PhotoRenderEngine.swift:171-188`). PhotoKit performs the actual JPEG/HEIC decode internally before invoking the callback; this app never calls `CGImageSourceCreateThumbnailAtIndex`, `UIGraphicsImageRenderer`, or `.preparingForDisplay()`/`.preparingForDisplay(completionHandler:)` anywhere (confirmed via `grep -rn "preparingForDisplay\|CGImageSourceCreateThumbnail\|UIGraphicsImageRenderer" Nizi/` — no matches).
- **No decode-on-Main is possible in the sense of "this app decodes JPEG on Main"** — because it never manually decodes at all. The Main-Actor risk documented in §7 is PhotoKit's own **asset lookup** (`PHAsset.fetchAssets`) running synchronously before the async request is even issued, not image decoding itself. Whatever internal decode cost `PHImageManager.requestImage` has is on whatever thread PhotoKit itself chooses (undocumented, Apple-internal, not inspectable from this codebase).
- **Multiple `UIImage` creation for the same asset**: yes, structurally — e.g., a photo can be requested independently at 132×172 (Home rail), 120×120 (list row), 160×160 (Event grid), 400×400 (viewer seed), 1000×1000 (viewer display), and again via a *completely separate* `PHCachingImageManager` instance if it's ever opened through the Album pipeline (§10) — each of these is a distinct PhotoKit request producing a distinct decoded `UIImage`, cached (or not, §10) under a distinct size-keyed cache entry.

---

## 9. Cancellation

Scenario: user opens photo A, before it finishes opens B, then C.

- **CurationPreviewView / CurationPreviewPage** (the full-screen viewer): explicitly engineered for this. `displayPreviewTasks: [String: Task<PlatformImage?, Never>]` is keyed by `assetID` and lives on the *viewer*, not the page (`EventDetailView.swift:821-829`) — the doc comment explains this directly: a page disappearing (which `TabView` does aggressively for off-screen pages) used to cancel that page's in-flight request via `withTaskCancellationHandler`, "wasting real progress and forcing a full re-fetch... if the user swiped back." The current design has a page *await* an already-registered `Task` instead of owning one, and notes "awaiting a `Task`'s `.value` does not cancel that task if the awaiting context is cancelled" (`:826-828`). `seedTasks` (`:812`) is similarly tracked, with a window (`seedWindowAssetIDs`, `:813`) so `updateSeedPreheatWindow` "can skip assets already requested and cancel ones that fall out of... window" (`:809`). **This means A's request, if outside the new window after jumping to C, is cancelled; if still inside the window, it is intentionally left running and reused rather than cancelled** — a deliberate, documented choice, not an oversight.

- **Grid cells / rail cards using `.task(id:)`**: SwiftUI's own `.task(id:)` modifier automatically cancels the previous task when the `id` changes and the view identity is preserved. This applies to `EventPhotoCell` (`EventDetailView.swift:741`), `TripMiniCard`/`LovedMemoryCard`/etc. — but this only cancels a request if the *same cell* is reused for a new asset ID (e.g., in a recycled Lazy container), not the "user opens A, then B, then C in a viewer" scenario, which is a different code path entirely (§ above).

- **`EventArchiveRow`**: explicit manual cancellation, not relying on `.task(id:)` alone — `thumbnailTask: Task<Void, Never>?` is stored, cancelled in `.onDisappear` (`EventListView.swift:606-609`) and again pre-emptively in `.onChange(of: event.coverAssetID)` (`:610-614`) before starting a new load, with a comment noting explicit ownership "prevents rows from continuing iCloud/PhotoKit work after they are no longer useful on screen" (`:567-569`).

- **`ApplePhotosAlbumPhotoProvider`**: cancellation flows through `AsyncStream.onTermination`, which cancels both the owning `Task` and the underlying `PHImageRequestID` via `ActiveRequestRegistry.cancel` (`ApplePhotosAlbumPhotoProvider.swift:106-109, 145-152`) — a real, working cancellation path, separate from and not shared with any of the above.

- **`PhotoRenderEngine`**: uses `withTaskCancellationHandler` around each PhotoKit request, cancelling the specific `PHImageRequestID` on cancellation (`PhotoRenderEngine.swift:131, 153-155, 169, 191-193`) via a `PhotoRenderRequestBox`. Not traced in this pass whether rapid preset/slider changes in the editor actually let old in-flight renders finish and overwrite newer ones, or whether they're reliably cancelled — the mechanism exists; whether every call site uses it correctly on rapid successive edits was not verified.

---

## 10. Cache

There is **no single cache** — four independent caching layers exist, three of which are genuinely separate `NSCache` instances:

| Cache | Type | Scope/lifetime | Key | Eviction | File:line |
|---|---|---|---|---|---|
| `PhotoKitAssetProvider.sharedMemoryCache` | `NSCache<NSString, PlatformImage>` | `static let` — **one instance for the entire app process**, survives across every screen/instance of `PhotoKitAssetProvider` | `"\(assetID)-\(width)x\(height)-fill\|fit"` (`PhotoKitAssetProvider.swift:195-198`) | `countLimit = 500` (`:24`); otherwise OS memory-pressure eviction (implicit `NSCache` behavior) | `PhotoKitAssetProvider.swift:22-27` |
| `AlbumImageCache` | `NSCache<NSString, PlatformImage>` per instance | **Not shared** — a fresh instance is created every time `ApplePhotosAlbumPhotoProvider()` is constructed, and that happens at 9 separate call sites (`MemoryDetailView.swift:93`, `HomeView.swift:39`, `AlbumsListView.swift:84`, `AlbumDetailView.swift:31, 246, 263, 270`, `AlbumInfoEditSheet.swift:95`, `RealAlbumPhotoDiagnosticsView.swift:30`) | `"\(sourceIdentifier)\|\(widthBucket)x\(heightBucket)\|\(contentMode)"`, size bucketed to nearest 50px (`AlbumImageCache.swift:16-27`) | `countLimit = 200` (`:38`); also cleared entirely on `UIApplication.didReceiveMemoryWarningNotification` (`:41-43, 55-57`) | `AlbumImageCache.swift:32` |
| PhotoKit's own internal cache (inside each `PHCachingImageManager`/`PHImageManager` instance) | Opaque, Apple-managed | Per-manager-instance — since there are **at least 4 independently-constructed `PHCachingImageManager` instances** in the app (`PhotoKitAssetProvider.swift:14`, `PhotoRenderEngine.swift:23/29`, `AutoEnhanceService.swift:17/24`, `ApplePhotosAlbumPhotoProvider.swift:15/21`, plus one fresh one per each of the 9 `ApplePhotosAlbumPhotoProvider()` constructions above), PhotoKit's own cache is fragmented the same way the `AlbumImageCache` is | PhotoKit-internal | PhotoKit-internal | n/a |
| `AlbumPhotoView.state` | Per-view `@State`, not really a cache | Lives only as long as that one `AlbumPhotoView` instance | n/a | discarded when the view is torn down | `AlbumPhotoView.swift:49` |

**Cache hit/miss are logged (not counted)** for the `PhotoKitAssetProvider` path only: `NiziLogger.discovery.notice("thumbnail_cache_hit ...")` (`PhotoKitAssetProvider.swift:127`) and `"thumbnail_request_start"`/`"thumbnail_request_completed"` (`:135, 180`) — these are one-off log lines, not aggregated counters (see §16).

**Screens that skip the cache entirely**: none found that skip caching outright, but every screen reached exclusively through the Album pipeline effectively gets a **cold cache on almost every navigation**, because a fresh `ApplePhotosAlbumPhotoProvider` (and therefore a fresh `AlbumImageCache` and a fresh `PHCachingImageManager`) is constructed at each of the 9 sites above — e.g., opening the same photo from `MemoryDetailView`'s `AlbumPhotoPreviewView` sheet (`MemoryDetailView.swift:93`) and then from `AlbumDetailView` (`AlbumDetailView.swift:31`) hits two completely separate caches, even though both ultimately request the same `PHAsset`.

---

## 11. Preheating

Real preheating exists, but only in the `PhotoKitAssetProvider`/`CurationPreviewView` pipeline:

- `PhotoAssetProvider.prefetchThumbnails(assetIDs:targetSize:contentMode:networkAccessAllowed:)` / `stopPrefetchingThumbnails(...)` wrap `PHCachingImageManager.startCachingImages`/`stopCachingImages` directly — `PhotoKitAssetProvider.swift:208-225`.
- Called from `EventDetailView`'s grid, at `gridThumbnail` size, `networkAccessAllowed: false`, around initial appearance (`EventDetailView.swift:143, 149`).
- Called again inside `CurationPreviewView` at `displayPreview` size, `networkAccessAllowed: true`, as the prefetch window slides (`EventDetailView.swift:986, 1061, 1064`).
- As noted in §5, `EventDetailView.swift:18-24`'s own comment documents that `startCachingImages` alone was found **not sufficient** — it's "only a best-effort hint, not a guarantee" — which is why `viewerSeed` exists as a second, *awaited* (not just hinted) request layer on top of the caching hint.

**No preheating found** in: Home rails (Trip/Memory/Album cards each load independently on their own `.task`, no `startCachingImages` call for the rail as a whole), Trips List, Events List, Memory Detail gallery, Trip Detail gallery, or anywhere in the Album pipeline (`ApplePhotosAlbumPhotoProvider` has no `prefetch`/`startCaching` method at all — confirmed by reading the full file, §2c).

---

## 12. Duplicate Requests

Concrete, confirmed duplicate-request paths for the same asset:

1. **Cross-pipeline duplication (Album vs. everything else)**: because the Album pipeline never shares a cache or manager with `PhotoKitAssetProvider` (§10), any asset that appears both in a Memory/Event/Trip context *and* gets opened through an Album-backed viewer (`AlbumPhotoPreviewView`, reached from `MemoryDetailView.swift:93`'s `.environment(\.albumPhotoProvider, ApplePhotosAlbumPhotoProvider())`) is re-fetched from PhotoKit from scratch, even if an equivalent size was just loaded moments earlier through the other pipeline.

2. **`SelectionThumbnailCell`** (`MemorySelectionEditView.swift:124-129`): reads `cachedThumbnail` first (a synchronous, free lookup) but then **unconditionally** calls `requestThumbnail` again on the next line regardless of whether the cache lookup succeeded — there is no `guard image == nil else { return }` guard here (contrast with `TripMiniCard.swift:84-85`'s `loadCover`, which does have that guard). This means a cache **hit** in this cell still issues a live PhotoKit request every time the cell's `.task(id:)` fires.

3. **Same-asset, different-size, no shared "already loading at a nearby size" logic**: nothing in `PhotoKitAssetProvider` deduplicates two *concurrent* requests for the same `assetID` at *different* target sizes (e.g., a rail card requesting 480×720 for the same photo `CurationPreviewView`'s seed logic requests at 400×400) — each is a fully independent `PHImageManager.requestImage` call, keyed separately in the cache (`cacheKey(assetID:targetSize:contentMode:)`, `PhotoKitAssetProvider.swift:195-198`, includes size in the key by design). `EventPlaceEnrichmentService`-style in-flight dedup (an `actor` with an `inFlight: [Key: Task]` dictionary, seen elsewhere in this codebase for geocoding) has no equivalent for thumbnail requests in `PhotoKitAssetProvider` itself — `PhotoThumbnailRequestLoader` only limits *concurrency* (`maxConcurrentRequests = 2`, `TripMiniCard.swift:111`), it does not dedup two callers requesting the exact same `(assetID, size)` pair simultaneously into one shared PhotoKit call.

---

## 13. SwiftUI Patterns

- **No `AsyncImage`** usage anywhere in `Nizi/Features/` (confirmed via `grep -rn "AsyncImage" Nizi/` — no matches) — every image load goes through the custom `PhotoAssetProvider`/`AlbumPhotoProviding` abstractions.
- **No `ObservableObject`/`@StateObject`/`@ObservedObject` in the photo-loading path** for the MemoryDiscovery/CurationPreviewView/Album pipelines — they're all plain `View` structs with `@State private var image: PlatformImage?` and a `.task`. The one `@MainActor @Observable` class in the whole photo stack is `PhotoEditorViewModel` (`PhotoEditorViewModel.swift:44`), which is Editor-only, not used by any grid/rail/viewer cell.
- **`body` triggering `requestImage`/`requestThumbnail` directly**: not found — every request happens inside a `.task`/`.task(id:)` closure, never inline in a `var body` computed property. (`AlbumPhotoView.body`, `:52-65`, computes `pixelSize` inline in `body` when no explicit `targetSize` is given, via a `GeometryReader`, but the actual PhotoKit-triggering call is still inside `.task(id:)`, not `body` itself.)
- **Per-cell provider construction**: some cells hold their *own* `@State private var assetProvider: PhotoAssetProvider = PhotoKitAssetProvider()` rather than receiving one from a parent (e.g., `TripListRow`, `TripsListView.swift:134`; `EventListView`'s `private let assetProvider = PhotoKitAssetProvider()` at `EventListView.swift:40`, one shared instance for the whole list, not per-row). Since `PhotoKitAssetProvider.sharedMemoryCache` is `static` (§10), a fresh `PhotoKitAssetProvider()` per cell doesn't fragment the *cache*, but it does mean each such instance owns its own `PHCachingImageManager` (`PhotoKitAssetProvider.swift:14` is an instance property, not static) — so `TripListRow`, constructed once per row in a `LazyVStack`/`ForEach`, creates one `PHCachingImageManager` per row instance actually alive at once (not per asset, but still more than one for the whole screen).

---

## 14. Scroll Performance

- **Event Detail grid**: preheats via `prefetchThumbnails`/`stopPrefetchingThumbnails` at appear/disappear of the whole grid section (`EventDetailView.swift:143, 149`), not per-scroll-position — this is a one-shot preheat of an "initial" set (`initialPrefetchAssetIDs`), not a sliding preheat window reacting to live scroll offset. Individual `EventPhotoCell`s each carry their own `.task(id: item.assetID)` (`:741`), so fast scrolling through a `LazyVGrid` will start a new request per cell as it's instantiated and cancel it (via SwiftUI's automatic `.task(id:)` cancellation) if the cell is torn down/recycled before that resolves — no request-storm-specific counting or throttling code was found for this grid specifically (contrast with `CurationPreviewView`'s explicit `ViewerSeedThrottle(maxConcurrent: 3)`, §2b/§9, which *does* bound concurrency).
- **CurationPreviewView's sliding window** (`updateSeedPreheatWindow`/prefetch window logic, `EventDetailView.swift:1061-1064` and surrounding) is the one place in the codebase with an explicit "which assets are currently in the look-ahead window, start/stop caching for the delta" pattern.
- **No request-count instrumentation exists anywhere** (§16) — so "how many requests fire vs. complete vs. are wasted" during a fast scroll cannot be answered from logs/metrics; it would require live profiling (Instruments), which was not done as part of this static-code survey.

---

## 15. Viewer Performance (Memory / Album / Photo Viewer)

- **Memory Viewer**: `MemoryDetailView`'s photo tap opens `AlbumPhotoPreviewView` (the Album pipeline's viewer, §2c) via a `.fullScreenCover`, injecting a **freshly-constructed** `ApplePhotosAlbumPhotoProvider()` at `MemoryDetailView.swift:93` — i.e., Memory's viewer does **not** reuse the CurationPreviewView 3-tier pipeline (§2b/§5) at all; it goes through the Album pipeline's single-request-per-size, `.opportunistic`-delivery model instead, with its own cold cache.
- **Event/Trip Viewer**: both reuse `CurationPreviewView` (§2b) — confirmed for Trip via `TripDetailView.swift`'s `.fullScreenCover(item: $previewPresentation) { CurationPreviewView(...) }`, and for Event via `EventDetailView.swift`'s `CurationPreviewPresentation`/`.fullScreenCover` construction. This is the pipeline with real seed-guarantee + prefetch-window + throttled concurrency (§2b, §9, §11).
- **Album Viewer** (opened from `AlbumDetailView`): uses `AlbumPhotoView` directly (§2c) — same pipeline as Memory's, i.e., no 3-tier seed/preview/original split, relying instead on PhotoKit's own `.opportunistic` degraded/final delivery.
- **On open**: Event/Trip viewer requests `viewerSeed` (400×400) as a *guaranteed, awaited* call, not merely a caching hint (§5, `EventDetailView.swift:1074-1120` region) — i.e., it does **not** request Original immediately, and does request a bounded preview first. Album/Memory viewer requests whatever `targetPixelSize` the caller (`AlbumPhotoPreviewView`) computed — not verified in this pass whether that's screen-resolution or a capped size (`AlbumPhotoPreviewView.swift` was not re-read in this survey pass for its exact target size; it is a different file from `AlbumPhotoView.swift`, both in `Nizi/Features/AlbumPhotos/Presentation/` and `Nizi/Features/AlbumViewer/Presentation/` respectively — **not verified in this pass**).
- **Pinch/double-tap zoom**: `CurationPreviewView`/`CurationPreviewPage` tracks `isZoomed` (`EventDetailView.swift:802`) to gate the dismiss-swipe gesture, but §5's own comment states the `zoomDetail` tier ("reserved third tier — no caller needs it yet") is **unimplemented** — meaning zooming in on the `displayPreview` (1000×1000) tier does not trigger a higher-resolution request; the user is pinch-zooming a 1000px-capped image. Not verified in this pass whether `AlbumPhotoView`'s crop/zoom (`crop.scale`, §6) requests a higher-resolution image on zoom either — from the code read, `AlbumPhotoView.imageView` only ever uses whatever `image` `state` already holds; no size-escalation-on-zoom logic was found in that file.

---

## 16. Diagnostics — what instrumentation already exists

**None of the following exist anywhere in the codebase** (confirmed by `grep -rn "os_signpost\|OSSignposter\|MetricKit\|signpostID" Nizi/` — no matches):
- Cache hit/miss **counters** (only one-off `NiziLogger.notice` log lines per event, §10 — not aggregated, not queryable, not visible in any UI)
- Average image load time
- Decode time
- Render time
- "Main thread blocked" measurement
- Number of active/in-flight requests (tracked internally as private state in a few places — `PhotoThumbnailRequestLoader.activeRequestCount`, `TripMiniCard.swift:111`; `ViewerSeedThrottle.activeCount`, `EventDetailView.swift:1216` — but neither is exposed anywhere for inspection, both are private and only used internally to gate concurrency)
- Cancelled-request counts

The closest thing to diagnostics is the ad hoc `NiziLogger.discovery`/`NiziLogger.photoEditor` `.notice`/`.error` calls scattered through the files cited above (e.g. `PhotoKitAssetProvider.swift:127, 132, 135, 163, 168, 174, 180`) — these are individual log lines visible in Console/Xcode's debug console, not a structured metrics system, and were noted earlier this session as sometimes not visibly appearing in the Xcode console at all (a separate, unresolved Xcode-tooling issue, not a code issue).

There is a `PhotoLibraryDiagnosticsView`/`RealAlbumPhotoDiagnosticsView` family of debug-only screens (`Nizi/Features/MemoryDiscovery/Presentation/PhotoLibraryDiagnosticsView.swift`, `Nizi/Features/AlbumPhotos/Presentation/RealAlbumPhotoDiagnosticsView.swift`) — these were not read in full in this pass; based on the name and the debug-only framing at `PhotoLibraryDiagnosticsView.swift:10-12` ("Debug-only screen for inspecting Photos permission state"), they appear to be permission/authorization diagnostics, not photo-pipeline performance diagnostics — **not fully verified in this pass**.

---

## 17. Architecture Review

The app does **not** follow a single "PhotoKit → Shared Pipeline → Cache → Presentation" model. It follows, simultaneously:

- **Shared-provider model** for the MemoryDiscovery pipeline: `PhotoKitAssetProvider` + its `static` cache is genuinely shared, and several screens correctly reuse one passed-down instance (e.g., `HomeView.homeThumbnailProvider`, passed to both `TripMiniCard` and `LovedMemoryCard`).
- **Per-screen-request model** for the Album pipeline: every consumer constructs its own `ApplePhotosAlbumPhotoProvider`, each with independent state (§10), which is the "each screen requests PhotoKit itself" pattern the survey asked to distinguish from the shared-pipeline pattern — this is present, but scoped to Album specifically, not the whole app.
- **A third, semi-shared model** for the viewer: `CurationPreviewView` reuses the *same* `PhotoAssetProvider` instance its caller passes in (so it shares `PhotoKitAssetProvider`'s cache), but layers its own additional actors (`ViewerSeedThrottle`) and task-tracking dictionaries on top, specific to that view.
- **A fully separate model** for the Editor (`PhotoRenderEngine`), which is correct in isolation (editor has different needs — full-res, `.current` version, CIImage-only) but shares nothing with the other three.

Net assessment: the codebase clearly *intends* a shared-provider pattern (`PhotoAssetProvider` protocol, doc comments like `PhotoKitAssetProvider.swift`'s own "The only place in Memory Discovery allowed to call PHAsset/PHImageManager directly" at `:11`) and mostly follows it within the "Memory Discovery" feature boundary — but that boundary does not cover Album, and even within the boundary, several call sites bypass the one piece of shared infrastructure (`PhotoThumbnailRequestLoader`) that keeps synchronous PhotoKit work off the Main Actor (§3, §7).

---

## 18. Comparison With Apple's Own Best Practices

| Practice | Status | Evidence |
|---|---|---|
| Progressive loading (thumbnail → preview → original) | ⚠ Partial | Real 3-tier only in `CurationPreviewView` (§5). Most other screens are single-tier or ad hoc 2-tier. |
| `PHCachingImageManager` used | ✅ Yes, but fragmented | 4+ independent instances instead of one per logical "session" (§10) |
| Thumbnail sized to actual display size | ⚠ Mixed | Most are correctly downsized (§4); Album rail requests 400×400 for a 128pt tile "to match Memory/Trip's quality-first tier" (a deliberate choice, not a bug, per its own comment) |
| Cancel stale requests | ✅ Mostly yes | `.task(id:)` auto-cancel almost everywhere; explicit manual cancellation in `EventArchiveRow`, `CurationPreviewView`, `ApplePhotosAlbumPhotoProvider`, `PhotoRenderEngine` (§9) |
| Preheating (`startCachingImages`/`stopCachingImages`) | ⚠ Partial | Only in Event Detail grid + `CurationPreviewView` (§11); absent everywhere else, including every horizontal rail on Home |
| Decode off Main | N/A (no manual decode step, §8) — but the **synchronous asset lookup** that precedes every PhotoKit request is on Main in most direct-call sites (§7) | §7, §8 |
| Background image processing | ⚠ Partial | Present via `PhotoThumbnailRequestLoader`/`ViewerSeedThrottle` actors where used; absent at the 5 direct-call sites listed in §7's summary |
| Stable cell layout while loading | ✅ Mostly yes, with one caveat | Event grid cell explicitly fixed for this (§6); `AlbumPhotoView` re-enters a full `.loading` state (flat placeholder) on every `requestKey` change, which is a visible flash, not a silent bitmap swap (§6) |
| One shared cache reused across the app | ❌ No | Three separate cache layers, one of which (`AlbumImageCache`) is re-created 9 times (§10) |
| Deduplicate concurrent identical requests | ❌ No | No in-flight dedup by `(assetID, size)` anywhere in `PhotoKitAssetProvider` (§12) |
| Diagnostics / instrumentation for the pipeline itself | ❌ No | No signposts, no counters, no timing (§16) |

---

## 19. Root Cause Summary (by likely impact — no fixes proposed)

**P0 — Main thread blocked, directly reachable from a screen named in the user's report**
- `EventDetailView.swift:742` (`EventPhotoCell.task`) calls `assetProvider.requestThumbnail` directly, not through `PhotoThumbnailRequestLoader` → synchronous `PHAsset.fetchAssets` at `PhotoKitAssetProvider.swift:131` runs on Main Actor for every Event grid cell cache-miss. This is the Event grid specifically named in "mở ảnh preview chậm... UI đứng vài giây."
- Same pattern, same root line, also reachable from: `TripsListView.swift:180`, `EventListView.swift:656`, `MemorySelectionEditView.swift:126`.
- `PhotoRenderEngine.swift:119, 159` (`fetchAsset`'s synchronous lookup) runs on Main Actor because `PhotoEditorViewModel` is `@MainActor` and `PhotoRenderEngine` has no actor isolation of its own.

**P1 — No progressive loading on several photo-dense screens**
- Trips List, Events List, Event Detail grid, Memory selection editor: single-tier request, flat-color placeholder until it resolves, no intermediate preview (§5).

**P1 — Album pipeline's cold-cache-per-navigation**
- 9 independent `ApplePhotosAlbumPhotoProvider()` constructions (§10), each with its own `NSCache` and `PHCachingImageManager` — every Album-pipeline screen transition (including Memory's own photo viewer, which goes through this pipeline, §15) re-fetches from PhotoKit even for an asset already decoded seconds earlier elsewhere in the same session.

**P1 — Layout-visible flash on every reload in `AlbumPhotoView`**
- `state = .loading` on every `requestKey` change re-shows a flat `ProgressView` placeholder instead of keeping the previous bitmap visible during a refresh (§6) — a plausible source of "giao diện đôi khi 'vỡ' khi ảnh nét xuất hiện" for anything routed through the Album pipeline (Album screens, and Memory's photo viewer).

**P2 — No request deduplication**
- Two simultaneous requests for the same `(assetID, size)` both hit PhotoKit independently; no in-flight `Task` sharing in `PhotoKitAssetProvider` (§12), unlike the pattern already used elsewhere in this codebase for geocoding (`EventPlaceEnrichmentService`'s `inFlight` dictionary).

**P2 — Redundant request on cache hit**
- `MemorySelectionEditView.swift:125-126` fetches from cache, then unconditionally re-requests anyway (§12 item 2).

**P2 — No preheating outside Event Detail grid / CurationPreviewView**
- Home's three horizontal rails (Loved Memories, Trips, Album), Trips List, and Events List have no `startCachingImages` call at all (§11) — every cell pays a full cold-request cost the first time it's laid out, with no look-ahead.

**P3 — No instrumentation to confirm any of the above under real load**
- No signposts, counters, or timing exist anywhere (§16) — the P0/P1 findings above are architectural (confirmed by reading the code paths), but their actual real-device impact magnitude (how many ms, how often) cannot be quantified from the codebase alone and was not measured with Instruments as part of this survey.

**P3 — Two incompatible `deliveryMode` philosophies coexist**
- `PhotoKitAssetProvider` avoids `.opportunistic` by design (§3); `ApplePhotosAlbumPhotoProvider`'s `AlbumPhotoView` caller always uses `.opportunistic` (§3) — not a bug in either individually, but a sign the two pipelines were designed independently without a shared photo-loading policy.
