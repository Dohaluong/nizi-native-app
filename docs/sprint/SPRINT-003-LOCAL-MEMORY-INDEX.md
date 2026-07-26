# SPRINT-003 — LOCAL MEMORY INDEX

commit và push git theo repo: git@github.com:Dohaluong/nizi-native-app.git

## Goal

Lập chỉ mục metadata cục bộ theo batch, có checkpoint và resume.

## Scope

- SwiftData schema v1.
- LocalAsset repository.
- ScanCheckpoint.
- Batch scan.
- Pause/resume.
- Clear index.

## Tasks

1. Tạo SwiftData models:
   - MDLocalAsset;
   - MDScanCheckpoint.
2. Tạo repository protocols trong Domain.
3. Tạo SwiftData repository implementations.
4. Implement `ScanPhotoLibraryUseCase`.
5. Upsert idempotent theo `assetLocalIdentifier`.
6. Batch write.
7. Progress publisher.
8. Pause.
9. Resume sau relaunch.
10. Clear local index.
11. Thống kê năm/tháng.
12. Test 10k+ asset.

## Out of scope

- Candidate.
- Vision.
- Upload.

## Acceptance Criteria

- Không duplicate.
- App đóng giữa scan và tiếp tục được.
- UI không freeze.
- DB không lưu binary ảnh.
- Clear index hoạt động.
- Ảnh lỗi không dừng batch.

## Suggested commit

```text
feat: add resumable local photo metadata index
```
