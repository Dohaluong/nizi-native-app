# Nizi Memory Discovery — Document Index

## Foundation

1. `ARCHITECTURE-MEMORY-DISCOVERY.md`
2. `DB-MEMORY-DISCOVERY.md`
3. `SPEC-MEMORY-DISCOVERY.md`
4. `UI-MEMORY-DISCOVERY.md`

## Sprint order

1. `SPRINT-001-NATIVE-FOUNDATION.md`
2. `SPRINT-002-PHOTOKIT-DIAGNOSTICS.md`
3. `SPRINT-003-LOCAL-MEMORY-INDEX.md`
4. `SPRINT-004-EVENT-DISCOVERY.md`
5. `SPRINT-005-DISCOVERY-UI.md`
6. `SPRINT-006-ALBUM-DRAFT.md`
7. `SPRINT-007-MOBILE-API-UPLOAD-HANDOFF.md`
8. `SPRINT-008-INCREMENTAL-PERFORMANCE-HARDENING.md`

## Recommended execution rule

- Chỉ làm một sprint tại một thời điểm.
- Không triển khai phần Out of scope.
- Mỗi sprint phải:
  - build pass;
  - test trên iPhone thật nếu có PhotoKit;
  - cập nhật tài liệu;
  - commit riêng;
  - ghi rõ các mục chưa xác minh.
- Không tối ưu AI/Vision trước khi Sprint 004–006 ổn định.
- Không sửa lớn Nizi Web trước Sprint 007.
