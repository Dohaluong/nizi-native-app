# SPRINT-008 — INCREMENTAL UPDATE AND PERFORMANCE HARDENING

## Goal

Ổn định module cho thư viện lớn và thay đổi liên tục.

## Scope

- Photo library change observer.
- Incremental indexing.
- Candidate rebuild theo phạm vi.
- Memory/CPU profiling.
- Error hardening.
- Data reset.
- Privacy review.

## Tasks

1. Implement PhotoKit change observer.
2. Handle inserted assets.
3. Handle changed assets.
4. Handle deleted/access revoked assets.
5. Recluster vùng thời gian liên quan.
6. ResourceGovernor.
7. Memory warning handling.
8. Thermal/low-power behavior.
9. Instruments:
   - Allocations;
   - Leaks;
   - Time Profiler;
   - Network.
10. Test 20k–50k asset.
11. Data reset.
12. Privacy log audit.
13. Crash/error scenarios.
14. Performance report.

## Acceptance Criteria

- Thêm ảnh mới không yêu cầu full rescan.
- Xóa ảnh không crash candidate/draft.
- Scroll không tăng RAM vô hạn.
- App không tải iCloud ngoài cấu hình.
- Data reset sạch.
- Không log GPS hoặc nội dung ảnh.
- Báo cáo benchmark được lưu trong Docs.

## Suggested commit

```text
perf: harden memory discovery for large photo libraries
```
