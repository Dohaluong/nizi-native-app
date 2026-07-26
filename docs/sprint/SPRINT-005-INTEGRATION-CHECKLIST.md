# SPRINT-005 — Integration Checklist

Manual verification for the new user-facing flow on a real iPhone. UI flow correctness can't
be exercised by `xcodebuild test`; `LibraryScanScopeTests` only covers the pure date-range math.

## Full flow

- [ ] Fresh install → **Hello Nizi** shows (not Home, not Candidate List).
- [ ] **Bắt đầu** → Scope Selection.
- [ ] Choosing **Toàn bộ thư viện** → **Tiếp tục** → Photos permission prompt appears (only now, not earlier).
- [ ] Choosing **Chỉ một số năm**, picking 1–2 years → scan only covers those years (spot-check the processed count against what Photos shows for that year range).
- [ ] Choosing **Chỉ một số tháng**, picking a year then a few months → same spot-check for the narrower range.
- [ ] After permission is granted (Full), scan starts automatically — no extra tap needed.
- [ ] Scan progress updates live, **Tạm dừng** stops it, **Tiếp tục** resumes from the same count (not from zero).
- [ ] When scan finishes, the app lands on **Home** — never on Candidate List directly.
- [ ] Home's Quick Action card shows a "N đề xuất mới" badge matching the actual new-candidate count.
- [ ] Tapping the Quick Action card → Candidate List, showing cards with cover/date/count/type/stars/one reason line.
- [ ] Tapping a card → Candidate Detail: cover, count, session timeline, full reasons list, thumbnail grid.
- [ ] Tapping **Tạo Album** shows the "coming soon" alert — no crash, no blank screen.
- [ ] Relaunch the app after completing a scan → skips straight to Home (Hello Nizi doesn't reappear).

## Permission states

- [ ] **Denied**: shows "Nizi chưa thể đọc thư viện ảnh." with **Mở Cài đặt** (opens Settings) and **Để sau** (proceeds to Home with an empty index).
- [ ] **Limited**: shows "Bạn chỉ chia sẻ một phần thư viện." with **Tiếp tục** (scans the limited set) and **Chọn thêm ảnh** (opens the system picker, then re-checks status without leaving the screen).
- [ ] After **Chọn thêm ảnh**, if the user happens to switch to Full Access from the system UI, the flow advances to scanning on its own.

## Performance / memory

- [ ] Scrolling the Candidate List and a large Candidate Detail thumbnail grid stays smooth; no unbounded memory growth (Xcode memory gauge or Instruments Allocations).
- [ ] Scrolling fast past thumbnails and back doesn't show stale images in reused cells.
- [ ] No full-resolution/original images are ever requested by these screens (`networkAccessAllowed: false`, thumbnail-sized targets only).

## Accessibility

- [ ] VoiceOver reads candidate cards as one combined element with title/count/type.
- [ ] Month chips in Scope Selection announce "Tháng 0N" and selected state.
- [ ] Dynamic Type: bump text size in Settings and confirm Hello Nizi / Scope Selection / Candidate Detail don't clip or overlap badly.

## Known gaps (Sprint 5 scope, by design)

- **Home is a minimal placeholder, not a port of the Nizi webapp timeline.** There is no Album module yet (no domain model, no creation flow), so there's nothing real to power a timeline with. This was a deliberate scope decision — see `docs/architecture/ARCHITECTURE.md` for the module map and revisit once Album Management exists.
- **Scope isn't persisted across a killed app mid-scoped-scan.** If the app is force-quit during a "years"/"months" scoped scan and relaunched, resuming re-enters the onboarding flow rather than resuming the exact same scope automatically — only the full-library case round-trips cleanly today via the checkpoint. See `LibraryScanScope` doc comment.
- **No photo selection in Candidate Detail.** Per the addendum, Sprint 5 only shows the full set of photos and a single "Tạo Album" action — selecting/deselecting individual photos is Sprint 006 (Album Draft) scope.
- Upload, Login, API, AI/Vision, similarity, maps, sharing, and cloud sync are all out of scope, per docs/sprint/SPRINT-005-UI.md § 20.
