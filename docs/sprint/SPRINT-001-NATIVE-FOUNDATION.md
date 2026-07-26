# SPRINT-001 — NATIVE FOUNDATION

## Goal

Tạo dự án `nizi-ios` chạy được trên iPhone thật và chuẩn bị cấu trúc module Memory Discovery.

## Scope

- Tạo SwiftUI app.
- Thiết lập signing.
- Chạy trên iPhone thật.
- Tạo folder architecture.
- Tạo Debug Diagnostics entry.
- Thêm permission description.
- Thiết lập logging cơ bản.
- Tạo test target.

## Deliverables

```text
nizi-ios/
├── NiziApp/
├── Features/MemoryDiscovery/
├── Core/
├── Tests/
└── Docs/
```

## Tasks

1. Tạo project `NiziNative`.
2. Bundle ID dev riêng.
3. Bật automatic signing.
4. Chạy màn hình Hello Nizi trên iPhone.
5. Thêm `NSPhotoLibraryUsageDescription`.
6. Tạo `MemoryDiscoveryFeature`.
7. Tạo `PhotoLibraryDiagnosticsView`.
8. Tạo `PhotoAccessStatus`.
9. Tạo logger không chứa dữ liệu nhạy cảm.
10. Tạo unit test đầu tiên.

## Out of scope

- Scan thật.
- Database.
- Clustering.
- Upload.

## Acceptance Criteria

- App cài và chạy trên iPhone.
- Không phụ thuộc simulator.
- Debug menu mở được.
- Project build Release và Debug.
- Test target chạy pass.

## Suggested commit

```text
feat: initialize nizi ios memory discovery foundation
```
