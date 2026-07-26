# SPRINT-002 — PHOTOKIT DIAGNOSTICS

## Goal

Kiểm chứng quyền Photos và khả năng đọc metadata/thumbnails trên iPhone thật.

## Scope

- Full/Limited/Denied.
- Đếm asset.
- Metadata summary.
- Thumbnail sample.
- iCloud network toggle.
- Console progress.

## Tasks

1. Implement `PhotoAuthorizationService`.
2. Implement `PhotoKitAssetProvider`.
3. Scan summary:
   - total;
   - photo/video;
   - with date;
   - with GPS;
   - oldest/newest.
4. Hiển thị 100–200 thumbnail.
5. Hủy request khi cell biến mất.
6. Test `networkAccessAllowed=false/true`.
7. Thêm nút mở Limited Library Picker.
8. Ghi scan duration.
9. Test trên thư viện thật.
10. Viết integration checklist.

## Out of scope

- Persistence.
- Full scan index.
- Clustering.

## Acceptance Criteria

- Full Access đọc đúng.
- Limited chỉ đọc asset được cấp.
- Denied không crash.
- Thumbnail scroll ổn.
- iCloud asset được nhận biết.
- Không tải original hàng loạt.

## Suggested commit

```text
feat: add photokit diagnostics and permission flow
```
