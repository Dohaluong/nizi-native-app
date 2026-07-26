# SPRINT-004 — EVENT DISCOVERY

## Goal

Tạo PhotoSession và EventCandidate bằng metadata rules.

## Scope

- Temporal segmentation.
- Spatial grouping cơ bản.
- Session persistence.
- Candidate persistence.
- Candidate scoring.
- Candidate reasons.

## Tasks

1. Tạo domain:
   - PhotoSession;
   - EventCandidate;
   - DiscoveryReason.
2. Tạo repository tương ứng.
3. Implement temporal segmentation.
4. Implement distance calculation.
5. Implement geo cell.
6. Tạo session.
7. Merge session thành event.
8. Score candidate.
9. Sinh title cơ bản:
   - ngày/tháng;
   - location nếu có.
10. Sinh reasons.
11. Candidate list debug.
12. Unit tests bằng synthetic metadata.

## Out of scope

- Vision.
- Duplicate detection.
- Album upload.

## Acceptance Criteria

- Cùng một fixture cho kết quả deterministic.
- Candidate có score và reason.
- Ảnh không GPS vẫn cluster được theo time.
- Không tạo candidate từ screenshot-only cluster.
- Rebuild không tạo duplicate candidate vô hạn.

## Suggested commit

```text
feat: add metadata based event discovery engine
```
