# SPRINT-006 — ALBUM DRAFT

## Goal

Cho phép người dùng chọn ảnh và chuyển candidate thành AlbumDraft local.

## Scope

- Photo selection.
- Cover selection.
- Title editing.
- Draft persistence.
- Selected/rejected states.
- Availability check.

## Tasks

1. Tạo AlbumDraft domain.
2. Tạo AlbumDraft repository.
3. Candidate → AlbumDraft use case.
4. Photo selection grid.
5. Select all/select suggested/deselect.
6. Filter screenshot/favorite/media type.
7. Cover picker.
8. Edit title.
9. Lưu draft.
10. Restore draft.
11. Asset unavailable state.
12. Draft summary.

## Out of scope

- Server API.
- Upload original.
- Similarity/Vision nâng cao.

## Acceptance Criteria

- Selection lưu sau relaunch.
- Chỉ selected assets nằm trong draft upload list.
- User đổi cover/title được.
- Deleted asset không crash draft.
- Candidate chuyển status đúng.

## Suggested commit

```text
feat: add local album draft and photo selection
```
