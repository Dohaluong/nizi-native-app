# SPRINT-002 — Integration Checklist

Manual verification for `PhotoLibraryDiagnosticsView` → `PhotoLibraryScanSampleView` on a real iPhone. Simulator libraries are too small/synthetic to exercise this meaningfully — must run on device.

Check each item and note the device/library size used.

## Permission states

- [ ] Fresh install, tap **Request Access** → system prompt appears, choosing **Allow Full Access** sets status to `Full`.
- [ ] Fresh install, choosing **Select Photos...** sets status to `Limited`, and **Manage Selected Photos** opens the limited-library picker.
- [ ] Fresh install, choosing **Don't Allow** sets status to `Denied`; app does not crash; **Open Settings** opens the app's Settings page.
- [ ] With access `Denied` or `Restricted`, **Scan Sample** is disabled (no PhotoKit calls attempted).

## Scan summary

- [ ] On a real library, `totalCount` matches the Photos app's "All Photos" count (± a few, since counts can drift slightly if the library is live).
- [ ] `photoCount + videoCount` is sensible against the library's known photo/video mix (audio/unknown are effectively zero for a normal camera roll).
- [ ] `withGPSCount` is lower than `totalCount` on a library with screenshots or messaging-app-saved images (those usually lack GPS).
- [ ] `oldestCreationDate` / `newestCreationDate` roughly bound the library's known date range.
- [ ] Scan duration is logged (Console.app, subsystem `vn.ima.Nizi`, category `memory-discovery`, event `scan_summary_completed`) and finishes without blocking the UI thread (screen stays responsive while scanning).

## Thumbnails

- [ ] Grid shows up to 150 thumbnails, most recent first.
- [ ] Scrolling is smooth; no visible frame drops on a mid-range device.
- [ ] Video assets show the video badge overlay.
- [ ] Scrolling fast past a row and back doesn't leave stale/wrong thumbnails in recycled cells.

## iCloud / network access

- [ ] With **Allow iCloud network access** off, an asset that isn't downloaded locally (e.g. under "Optimize Storage" with an old, rarely-opened photo) shows the iCloud placeholder icon instead of an image.
- [ ] Toggling the switch on re-requests those thumbnails and they resolve once downloaded.
- [ ] No original-resolution assets are downloaded in bulk — Console log / Network link conditioner should show only thumbnail-sized traffic, never full originals, during this flow.

## Cancellation

- [ ] Scrolling quickly through the grid does not pile up unfinished PhotoKit requests (check for `thumbnail_request_failed` cancellation spam in the log, which should be absent — cancellations complete silently).

## Known gaps (Sprint 2 scope)

- No persistence — summary and sample are recomputed every time the screen opens.
- No batching/checkpointing — `scanSummary()` walks the whole library in one pass; acceptable for a diagnostics screen, not for the production Library Scanner (Sprint 3+).
