# SPRINT-007 — MOBILE API AND UPLOAD HANDOFF

## Goal

Kết nối AlbumDraft với Nizi Web/API và upload đúng các ảnh đã chọn.

## Scope

- Authentication reuse.
- Create Album API.
- Upload session.
- Original asset request.
- Queue.
- Pause/resume.
- Complete upload.

## Tasks

1. Xác định auth contract.
2. Implement mobile API client.
3. Create Album endpoint.
4. Create upload session endpoint.
5. Request original từng selected asset.
6. Nhận biết iCloud download required.
7. Upload queue giới hạn concurrency.
8. Retry lỗi mạng.
9. Persist upload state.
10. Resume sau relaunch.
11. Complete session.
12. Server ownership validation.
13. Không gửi local asset identifier nếu không cần.

## Out of scope

- Background upload hoàn chỉnh cấp production nếu chưa có entitlement/architecture.
- Cloud AI.
- Album editor native.

## Acceptance Criteria

- Chỉ ảnh selected được upload.
- Không upload candidate chưa xác nhận.
- Upload fail có thể resume.
- iCloud trạng thái rõ.
- Webapp nhìn thấy Album mới.
- Không ghi trực tiếp database server.

## Suggested commit

```text
feat: connect album draft to nizi mobile upload api
```
