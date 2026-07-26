# Photo Editor — Bước 10 Test Checklist

Bước 10 (`docs/modules/photo-editor/PHOTO-EDITOR.md` § task instructions) asks for a specific
manual-QA matrix plus performance monitoring. Most of it needs a real device/simulator with actual
Photos-library content and a human driving the UI — neither of which this environment can do.
This document is the checklist to run through on-device; automated coverage is noted per item
where it exists so it's clear what's already guarded by a unit test vs. what's manual-only.

Reach the editor via **Home → Diagnostics → Photo Editor → Standalone Preview** (DEBUG builds
only) for anything not specific to a real Album/Event, or via a real Album/Event's photo viewer's
`Edit` button (the ✨ icon) for the Album/Event-specific cases.

## 1. Photo content cases

| Case | How to test | Automated coverage |
|---|---|---|
| Landscape photo | Open editor on a landscape photo from a real Album/Event | None — orientation normalization (`PhotoRenderEngine.oriented(_:)`) has no unit test since it needs a real oriented asset |
| Portrait photo | Same, portrait photo | Same as above |
| Large file (e.g. 48MP ProRAW/HEIC) | Open editor on the largest photo in your library; watch for slow preview load or full-res export lag | None — needs a real large asset |
| iCloud photo not yet downloaded locally | Open editor on a photo you know is iCloud-only (not "Downloaded"); preview should still load ( `isNetworkAccessAllowed = true` throughout) without hanging the whole UI | None — needs a real iCloud-only asset and network conditions |
| Screenshot | Open editor on a screenshot; presets/warmth may look odd on UI screenshots — this is expected per spec § 17.1, not a bug (no blocking warning is implemented, per spec allowing that to be optional) | None |
| Live Photo | Open editor on a Live Photo; only the still image is editable (§ 17.3) — confirm nothing crashes and the still frame renders | None — `PhotoRenderEngine` always requests a still image regardless of Live Photo status; not explicitly tested against one |
| Photo already edited in Apple Photos | Open editor on a photo with an existing Photos-app edit; confirm the *edited* (current) version is what loads, not the untouched original — `PHImageRequestOptions.version = .current` is set in every request (`PhotoEditorAssetLoader`... now `PhotoRenderEngine`/`AutoEnhanceService`) | None — needs a real Photos-edited asset |

## 2. Album/Event integration cases

| Case | How to test | Automated coverage |
|---|---|---|
| Album with many photos | Open Edit from an Album with 20+ photos; confirm `EditorContext.photoIds` covers every Page, not just the current one (`AlbumDetailView.allAlbumPhotoIds`) | None directly, but `PresetValidator`/`CollectionStyleResolver` unit tests cover the logic that consumes this list |
| Event with many photos | Same, for an Event — `CurationPreviewView`'s `items` (already the full flattened snapshot) is what's used | None directly |
| Rapid preset switching | Tap through several presets quickly in the Preset strip | Covered structurally by `PhotoEditorViewModel`'s render-generation counter (not directly unit-testable without a real render pipeline); manually watch for stale/flickering previews |
| Continuous slider dragging (intensity or Adjust) | Drag the intensity or an Adjust slider continuously | Same generation-counter mechanism, `debounced: true` path; watch for main-thread stutter or a pile-up of in-flight renders |
| Cancel with unsaved changes | Change a preset/Adjust value, tap Cancel | `PhotoEditSessionTests` covers `hasUnsavedChanges` logic; the confirmation-dialog UI itself is manual-only |
| Reopen a saved recipe | Save an edit, close the editor, reopen on the same photo | `SwiftDataPhotoEditRepositoryTests` covers the persistence round-trip; the full "reopen shows the same state" flow is manual |
| Change Album/Event style, revisit an inheriting photo | Apply a style to a whole Album/Event, then open a *different*, previously-untouched photo from it | `CollectionStyleResolverTests` covers the resolution logic; the live re-fetch-on-open behavior is manual |
| Photo with its own override | Give one photo in a styled Album/Event its own different preset, save "just this photo," then reopen it and a sibling that still inherits | Same as above |
| Reset to Original | Use "Reset to Original" in the Adjust tab on an edited photo | `PhotoEditSessionTests.resetToOriginalClearsWorkingRecipeButKeepsOriginalRecipe` covers the underlying session logic |

## 3. Performance/memory monitoring (use Xcode's Debug Navigator / Instruments while doing the above)

- **RAM**: watch the memory gauge while switching presets and dragging sliders repeatedly — should stay flat, not climb. `PhotoEditorViewModel.presetThumbnails` (8 small 160×160 images) and `loadState` (one preview-sized `CGImage` at a time, previous one released on reassignment) are the only image state it retains.
- **Main-thread blocking**: use Instruments' Time Profiler while dragging sliders — `PhotoRenderEngine`/`AutoEnhanceService` are plain (non-`@MainActor`) async types, so their PHImageManager/Core Image work should already run off the main actor; confirm no visible hitch.
- **Render latency**: time from a preset tap/slider release to the preview updating — should feel "gần liên tục" per spec § 18.1, not sluggish.
- **Task cancellation**: confirm switching presets/dragging rapidly doesn't cause a visible pile-up or a stale preview winning over a newer one (the render-generation counter in `PhotoEditorViewModel` is what prevents this — a regression here would show up as flicker or a wrong image landing after rapid input).
- **Cache lifecycle**: `presetThumbnails` is session-scoped only (never written to disk); confirm memory drops back down after closing the editor (no retained `Task`s — verified in code: no stored `Task<>` properties anywhere in `Features/PhotoEditor`).

## 4. Known, deliberate gap (not a bug to test around)

Album's and Event's own photo *display* (`AlbumPhotoView`/`ApplePhotosAlbumPhotoProvider`,
`EventDetailView`'s `PhotoAssetProvider`-based thumbnails) does not render through
`PhotoRenderEngine`/`CollectionStyleResolver` yet — a saved edit has no visible effect outside the
editor itself. This was flagged at the end of Bước 8 and Bước 9 and is out of scope for this pass;
don't file it as a Bước 10 regression.
