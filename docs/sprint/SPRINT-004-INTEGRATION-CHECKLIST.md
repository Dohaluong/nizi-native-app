# SPRINT-004 — Integration Checklist

Manual verification for Event Discovery (`EventCandidateListView`, reached from Photo Library Diagnostics → Event Candidates) on a real library. `EventDiscoveryEngine` itself is fully covered by synthetic-fixture unit tests (`NiziTests/EventDiscoveryEngineTests.swift`) since it's a pure function — this checklist is for what synthetic fixtures can't tell you: whether the tuned thresholds feel right against a messy real library.

## Prerequisite

Run a Local Memory Index scan to completion first (Sprint 3), then open Event Candidates → **Run**.

## Sanity on a real library

- [ ] A known multi-day trip in the library (if any) shows up as a single `trip` candidate, not fragmented into several.
- [ ] A known single-day event (party, outing) shows up as `dayEvent`.
- [ ] Candidates are sorted by score, highest first.
- [ ] Every candidate shown has at least one reason line.
- [ ] No candidate is made up entirely of screenshots.
- [ ] Ordinary daily-life photos (commute, meals, work) mostly do **not** turn into high-scoring candidates — score should trend low for repetitive/undifferentiated clusters. If they score surprisingly high, the weights in `EventDiscoveryConfig` need tuning (see "Known gaps" below).

## Rebuild behavior

- [ ] Tap **Run** twice in a row without any library changes → same number of candidates, similar (not accumulating) results.
- [ ] Add a few new photos to the library (or wait for a real incremental scan in a later sprint), re-run Local Memory Index scan, then **Run** again → candidate count updates sensibly, no duplicate near-identical candidates pile up.

## Known gaps (Sprint 4 scope)

- **Location labels are not generated.** `primaryLocationLabel` is always `nil` — reverse geocoding wasn't in this sprint's task list (only geo-cell math was). Titles are date-only for now.
- **"Daily-repeating cluster" noise (from SPEC § 10) is not specifically detected.** A long span of near-daily photos in the same place (e.g., home) could in theory merge into one long-duration, low-score candidate rather than being excluded outright. The duration-value term in scoring already decays candidates longer than 5 days, but there's no hard cap — watch for this if a "trip" candidate spans months.
- **Session-merge and scoring thresholds are the SPEC's stated starting values, unturned.** SPEC explicitly calls the scoring formula "chỉ là điểm khởi đầu" (a starting point) — expect to revisit `EventDiscoveryConfig`'s defaults after seeing real candidates.
- Vision-based quality/similarity signals, duplicate detection, and Album upload are out of scope for this sprint by design.
