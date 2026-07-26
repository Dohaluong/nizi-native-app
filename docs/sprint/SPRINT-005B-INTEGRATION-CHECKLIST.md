# SPRINT-005B — Integration Checklist

Manual verification for Photo Curation on a real device with a real Event Candidate of a few
hundred photos. `EventPhotoCurationEngineTests` covers the pure selection/balancing logic with
synthetic fixtures; `SwiftDataMemoryDiscoveryStoreTests` covers cache/override persistence.
Neither can validate real Vision output (face detection, blur/exposure, near-duplicate distances)
or real-device performance — that's what this checklist is for.

## No full-library rescan (the sprint's hardest constraint)

- [ ] Open a large Event Candidate (200–300 photos) from Candidate List. Confirm via Console log
      (subsystem `vn.ima.Nizi`, category `memory-discovery`) that no `scan_started`/`scan_completed`
      events fire — only `event_curation_completed`.
- [ ] Confirm the Local Memory Index's total indexed count (Photo Library Diagnostics → Local
      Memory Index) is unchanged before/after opening the candidate.
- [ ] Confirm existing Event Candidates in Candidate List are all still present and openable
      before and after this test.

## Curation pipeline

- [ ] First open of a candidate: shows event info immediately (cover, dates, reasons), then a
      "Đang chọn ảnh… Đã xử lý N / M nhóm" progress state, then the curated grid — never a blank
      screen.
- [ ] For a 200–300 photo event, the suggested count lands roughly in the 20–40 range from
      § 14 *when the content is actually diverse* — a repetitive/low-diversity event legitimately
      landing outside that range is not a bug (§ 14 is explicit the range is a reference, not a
      hard limit).
- [ ] Burst/near-duplicate sequences (5+ near-identical shots) collapse to 1–2 selected, not all of them.
- [ ] Sharper, better-exposed, better-composed shots are visibly preferred within a similar-content group.
- [ ] Closing and reopening the same candidate loads instantly from cache — no reprocessing,
      no progress bar.

## User overrides survive everything

- [ ] Tap an unselected photo to select it, leave the screen, come back — still selected.
- [ ] Tap a selected photo to deselect it, leave the screen, come back — still deselected.
- [ ] Force-quit the app after making a few overrides, relaunch, reopen the candidate — overrides
      still there (this is the one that most directly tests SwiftData persistence, not just view state).
- [ ] Full-screen preview: toggling selection there matches what's reflected in the grid after dismissing.

## Error / missing-asset handling

- [ ] If a photo permission is downgraded or an asset is deleted from Photos between the scan and
      opening the candidate, curation completes for the remaining assets rather than failing outright
      — check the log for `curation_asset_thumbnail_unavailable` rather than a crash.
- [ ] Force a failure (e.g. airplane mode + iCloud-only assets, if your test library has any) and
      confirm the error state shows "Nizi chưa thể sắp xếp sự kiện này." with a working "Thử lại",
      not a stack trace.

## Performance

- [ ] Scrolling the curated grid for a 200–300 photo event stays smooth.
- [ ] Memory stays bounded during curation (Xcode memory gauge) — thumbnails aren't all held in
      RAM at once.
- [ ] Backgrounding the app mid-curation and returning doesn't crash or leave the screen stuck;
      reopening a candidate mid-analysis doesn't spawn duplicate concurrent curation runs (SwiftUI's
      `.task` cancels the prior one when the view is torn down/recreated).

## Photo Viewer performance — three-tier image model (docs/sprint/SPRINT-005B-preview.md)

`gridThumbnail` (160px, fill) → `displayPreview` (800px, fit — the viewer's actual target
quality) → `zoomDetail` (reserved for a future pinch-zoom feature, not implemented).

- [ ] **Open a Candidate and tap the very first photo (top-left of the grid) specifically** —
      this exact case was completely broken before (viewer opened but never showed anything;
      tapping a *different* photo worked fine). Root cause: `TabView(selection:)`'s initial
      `@State` value equaled the page we wanted to show, and SwiftUI silently failed to render it
      — fixed by starting the selection at an out-of-range sentinel (`-1`) and assigning the real
      index in `.task`, guaranteeing a genuine state change every time, index 0 included. Test
      this specific interaction on a real device before considering it resolved.
- [ ] The grid thumbnail (enlarged) should be visible in the viewer immediately on open, before
      `displayPreview` arrives — if it's still blank/spinner-only on first open, the seeding logic
      needs a second look.
- [ ] More generally: the viewer opens right away showing something reasonable for *any* tapped
      photo — never hangs, never fails to open.
- [ ] The image sharpens from the (upscaled, expectedly soft) grid thumbnail to `displayPreview`
      quality shortly after opening — clearly sharper than the thumbnail, doesn't need to match
      the original.
- [ ] Swiping to the next/previous photo (within ~2 positions of where you started) shows a
      `displayPreview`-quality image almost immediately — not a multi-second wait.
- [ ] Swiping back to a photo already viewed this session shows `displayPreview` instantly from
      the memory cache — no re-request.
- [ ] Reaching `displayPreview` is what "the viewer opened successfully" means now — nothing
      should visibly block on or wait for a higher-quality/original fetch.
- [ ] No visible stutter or memory spike from prefetching while rapidly swiping through 10+ photos.
- [ ] The very first grid load after opening Candidate Detail isn't slower than before — confirms
      capping the initial prefetch to ~60 assets (not the whole candidate) didn't regress grid scrolling.

## Known gaps / tuning notes (disclosed, not defects)

- **Eye-openness scoring is an approximation.** Vision has no direct "eyes closed" signal; this
  uses eye-landmark aperture ratio as a proxy, deliberately low-weight — see
  `VisionEventPhotoAnalyzer.eyeOpennessScore`.
- **Sharpness/exposure are a from-scratch Laplacian-variance/mean-brightness heuristic**, not a
  Vision model — see `ImagePixelAnalyzer`. Reference constants (e.g. `referenceVariance = 400`)
  are starting points; real photos will tell us if they need adjusting.
- **Near-duplicate clustering compares each photo only to the most recently opened cluster**
  (O(n) per session, not full pairwise O(n²)) — very unusual orderings within a burst could in
  theory split what should be one cluster into two. Acceptable tradeoff for performance on
  200–300+ photo events; revisit only if real testing shows it under-clusters often.
- **All quality-scoring weights (§ 11) and the balancing ceiling multiplier are unTuned defaults**,
  same disclaimer pattern as `EventDiscoveryConfig` from Sprint 4 — expect to revisit after seeing
  real output.
- **iCloud progress is a delayed indeterminate spinner, not a percentage bar.** The preview spec
  (SPRINT-005B-preview.md § 11) describes wiring `PHImageRequestOptions.progressHandler` for a
  real download percentage; this implementation only shows/hides a generic spinner after a 400ms
  delay if the `displayPreview` request hasn't resolved yet. Simpler, still satisfies "don't
  flicker, don't block the image" — revisit only if users specifically want to see download progress.
- **`zoomDetail` (the third tier — pinch/double-tap zoom, edit, upload) is not implemented.**
  There's no pinch-zoom UI yet, so there's nothing to call it; `ImageSizing` only defines
  `gridThumbnail` and `displayPreview`. Add the tier when a zoom feature actually exists, per
  docs/sprint/SPRINT-005B-preview.md § 3's "không request zoomDetail cho mọi ảnh chỉ vì người
  dùng vừa swipe tới."
- **`.opportunistic` progressive delivery (degraded → final in one request) was tried first and
  removed** after real-device testing showed the real problem was requesting too large a target
  size (full device resolution), not the delivery mode. The simpler two-tier model (grid
  thumbnail seed → one bounded-size `displayPreview` request) replaced it entirely —
  `requestProgressiveThumbnail`/`ProgressiveImageResult` no longer exist in the codebase.
