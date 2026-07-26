# SPRINT-003 — Integration Checklist

Manual verification for the Local Memory Index (`LibraryIndexScanView`, reached from Photo Library Diagnostics → Local Memory Index) on a real iPhone with a large library. Automated coverage is in `NiziTests/SwiftDataMemoryDiscoveryStoreTests.swift` (in-memory SwiftData) — this checklist is for what that can't reach: real PhotoKit data, real relaunch, real device performance.

## Batch scan correctness

- [ ] On a library with 10k+ assets, **Start Scan** completes with `processedCount` equal to the library's total count (± items added/removed mid-scan).
- [ ] `failedCount` stays at 0 on a normal library; if non-zero, check the log (`local_asset_upsert_failed`) for which records failed and why.
- [ ] Year/month stats (**Refresh Stats**) roughly match the library's known distribution across years.

## Pause / resume

- [ ] Tap **Pause** mid-scan → status becomes `paused`, `processedCount` stops advancing, UI stays responsive.
- [ ] Tap **Resume Scan** (previously "Start Scan") → scan continues from the saved `cursorOffset`, not from zero — `processedCount` should not reset or double-count.
- [ ] Force-quit the app mid-scan (not just background), relaunch, open Local Memory Index → checkpoint shows the last saved progress; tapping **Start Scan** resumes rather than restarting.

## No duplicates

- [ ] Run the scan to completion twice in a row → `totalIndexedCount` stays the same after the second run (upsert, not insert).

## UI responsiveness

- [ ] While scanning a 10k+ library, the app remains scrollable/interactive — no visible freeze. (`SwiftDataMemoryDiscoveryStore` is a `@ModelActor`, so this should hold, but only real device timing confirms it.)

## Clear index

- [ ] **Clear Local Index** → confirmation dialog appears (Vietnamese copy per docs/philosophy/DESIGN-PRINCIPLES.md), confirming removes all `MDLocalAsset`/`MDScanCheckpoint` rows; `totalIndexedCount` returns to 0 and the checkpoint screen shows "Not scanned yet".
- [ ] Photos in the Apple Photos app are untouched by Clear.

## Data hygiene

- [ ] Console log (subsystem `vn.ima.Nizi`, category `memory-discovery`) never shows GPS coordinates, only event names and counts — spot check `scan_completed` / `scan_paused` lines.
- [ ] No `UIImage`/binary data ends up in the SwiftData store (nothing to check visually, but worth confirming via Xcode's SwiftData model inspector that only scalar fields are populated).

## Known gaps (Sprint 3 scope)

- No `PhotoSession` / `EventCandidate` / clustering yet — that's Sprint 4.
- No reconciliation of assets deleted from Photos mid-scan (`availabilityStatus` stays `available` once written) — the Change Observer lands in a later sprint.
- Cursor is a numeric offset into an ascending-by-`creationDate` fetch, not a stable identifier — if many new photos are imported *during* a scan, some assets near the cursor could theoretically be skipped or revisited. Acceptable for MVP since upsert is idempotent and a full re-scan self-heals; flagged here rather than solved, per docs/architecture/ADR/adr-md-009-long-running-tasks-must-be-resumable.md.
