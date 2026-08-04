# SPEC — NIZI MOVE BACKEND: GOOGLE DRIVE SHARE LINK IMPORT FOR NATIVE

**Dự án:** Nizi Move / Cloud Bridge backend  
**Mục tiêu:** Hỗ trợ Nizi Native dán Google Drive Share Link, chọn ảnh và yêu cầu server chuẩn bị ImportSession để Native tải về  
**Nguyên tắc bắt buộc:** Không làm ảnh hưởng luồng hiện có từ máy tính → web upload → QR → Native

---

## 1. Bối cảnh

Nizi Move hiện có luồng:

```text
Máy tính
→ Nizi Move Web chọn ảnh
→ Browser tối ưu nếu cần
→ Browser tạo ImportSession
→ Browser upload asset
→ Finalize
→ QR
→ Nizi Native claim
→ Manifest
→ Download
→ Completed
```

Luồng này phải giữ nguyên.

Bổ sung luồng mới:

```text
Nizi Native dán Google Drive Share Link
→ Native gọi Nizi Move backend inspect
→ Backend đọc metadata + thumbnail
→ Native chọn ảnh
→ Native gọi backend tạo session
→ Backend tải ảnh đã chọn từ Google Drive
→ Backend tối ưu nếu cần
→ Backend tạo asset ready
→ Native được cấp quyền truy cập session trực tiếp
→ Native lấy manifest và import bằng pipeline hiện có
```

Không dùng QR trong luồng mới vì chính Native tạo và nhận session.

---

## 2. Hai luồng cùng tồn tại

### Luồng A — Máy tính và QR

Giữ nguyên:

```text
Browser create
→ upload
→ finalize
→ QR
→ Native claim
```

### Luồng B — Native và Drive Link

Thêm mới:

```text
Native inspect link
→ select
→ create Drive session
→ backend prepare
→ direct native access
→ manifest/download
```

Hai luồng hội tụ tại:

```text
ImportSession ready
→ manifest
→ download
→ completed
```

---

## 3. Phạm vi backend cần thay đổi

Backend cần bổ sung:

- Parse Google Drive Share Link.
- Xác thực host và loại link.
- Đọc danh sách file/folder từ Google Drive.
- Phân trang metadata.
- Tạo preview/thumbnail proxy.
- Inspection session tạm thời.
- Nhận danh sách item Native chọn.
- Chỉ tải original của item đã chọn.
- Stream ảnh về temporary storage.
- Validate file.
- Resize/nén server-side nếu user chọn.
- Tính SHA-256.
- Ghi file vào `StorageProvider`.
- Tạo `ImportSession` bằng model hiện có.
- Cấp native access token trực tiếp cho session do Native tạo.
- Cho Native poll trạng thái chuẩn bị.
- Tái sử dụng manifest/download/completed/cleanup hiện có.

---

## 4. Những phần không được thay đổi

Không thay đổi behavior của:

```text
POST /api/import-sessions
POST /api/import-assets/:assetId/upload
POST /api/import-sessions/:sessionId/finalize
POST /api/import-sessions/:sessionId/claim
GET  /api/import-sessions/:sessionId/manifest
GET  /api/import-assets/:assetId/download
POST /api/import-assets/:assetId/completed
POST /api/import-assets/:assetId/failed
POST /api/import-sessions/:sessionId/completed
```

Không được làm regression:

- Browser upload.
- Multipart validation.
- Owner token.
- QR token.
- Pairing code.
- Claim một lần.
- Native token hiện tại.
- Manifest v1.
- HTTP Range.
- Asset cleanup.
- Session expiry.

---

## 5. Feature flag

Thêm:

```env
GOOGLE_DRIVE_SHARE_IMPORT_ENABLED=false
```

Khi `false`:

- API Drive trả `FEATURE_DISABLED`.
- Luồng upload/QR cũ hoạt động bình thường.
- Không chạy Drive adapter.
- Không yêu cầu Google credential lúc startup.

Khi `true`:

- Kiểm tra credential/config.
- Bật API mới.

---

## 6. Google Drive access

Google credential chỉ nằm trên server.

Không đưa vào:

- Native.
- React.
- QR.
- Manifest.
- Log.
- Git.
- Docker image.

Cấu hình đề xuất:

```env
GOOGLE_DRIVE_CREDENTIALS_PATH=/run/secrets/google-drive-service-account.json
```

Trước khi triển khai đầy đủ, Codex phải tạo prototype xác minh phương thức credential thực tế có thể:

1. Đọc folder `Anyone with the link`.
2. Đọc file con.
3. Xử lý resource key.
4. Tải original.
5. Phân biệt private/permission denied.
6. Hoạt động với folder Google cá nhân và Workspace trong phạm vi hỗ trợ.

Nếu service identity không đọc được public link theo Drive API trong môi trường thật, phải báo lại bằng bằng chứng API. Không tự chuyển sang scrape HTML.

---

## 7. Parse và validate link

Hỗ trợ tối thiểu:

```text
https://drive.google.com/drive/folders/{folderId}
https://drive.google.com/file/d/{fileId}/view
https://drive.google.com/open?id={id}
https://drive.google.com/uc?id={id}
```

Kết quả nội bộ:

```text
resourceId
resourceType
resourceKey
canonicalUrl
```

Yêu cầu bảo mật:

- Whitelist hostname.
- Chống SSRF.
- Không cho URL tùy ý.
- Không theo redirect ra host ngoài whitelist.
- Giới hạn URL length.
- Validate ID.
- Redact resource key trong log.

---

## 8. Inspection session

Inspection dùng để Native duyệt metadata trước khi tạo ImportSession.

Inspection không phải ImportSession.

Model nội bộ:

```text
DriveInspection
- id
- sourceResourceId
- sourceResourceType
- sourceResourceKey
- sourceName
- createdAt
- expiresAt
- items
- cursors
```

Item mapping:

```text
DriveInspectionItem
- opaqueItemId
- googleFileId
- resourceKey
- name
- mimeType
- size
- width
- height
- modifiedTime
- canDownload
- thumbnailReference
```

Không trả `googleFileId` hoặc `resourceKey` cho Native nếu không cần.

TTL đề xuất:

```env
GOOGLE_DRIVE_INSPECTION_TTL_MINUTES=30
```

Inspection chỉ lưu metadata, không lưu original.

---

## 9. API mới

### 9.1. Inspect link

```http
POST /api/google-drive-share/inspect
Content-Type: application/json
```

Request:

```json
{
  "url": "https://drive.google.com/drive/folders/...",
  "includeSubfolders": false
}
```

Response:

```json
{
  "success": true,
  "inspectionId": "opaque-inspection-id",
  "source": {
    "type": "folder",
    "name": "Ảnh sự kiện"
  },
  "items": [
    {
      "itemId": "opaque-item-id",
      "name": "IMG_0012.HEIC",
      "mimeType": "image/heic",
      "size": 5283942,
      "width": 4032,
      "height": 3024,
      "modifiedTime": "2026-07-20T10:30:00Z",
      "thumbnailUrl": "/api/google-drive-share/previews/preview-token",
      "canDownload": true
    }
  ],
  "nextCursor": "opaque-next-cursor",
  "summary": {
    "loadedItems": 100,
    "knownBytes": 623456789
  }
}
```

### 9.2. Pagination

```http
GET /api/google-drive-share/inspections/:inspectionId/items?cursor=...
```

### 9.3. Thumbnail proxy

```http
GET /api/google-drive-share/previews/:previewToken
```

### 9.4. Tạo Drive ImportSession cho Native

```http
POST /api/google-drive-share/import-sessions
Content-Type: application/json
```

Request:

```json
{
  "inspectionId": "inspection-id",
  "selectedItemIds": [
    "opaque-item-1",
    "opaque-item-2"
  ],
  "mode": "optimized",
  "clientType": "nizi_native"
}
```

Response:

```json
{
  "success": true,
  "sessionId": "existing-import-session-id",
  "nativeAccessToken": "one-time-returned-native-token",
  "status": "preparing",
  "totalAssets": 2
}
```

---

## 10. Direct native access

Luồng QR hiện tại:

```text
QR token
→ claim
→ nativeAccessToken
```

Luồng Drive mới:

```text
Native create Drive session
→ backend tạo nativeAccessToken trực tiếp
```

Không gọi claim.

Yêu cầu:

- Token crypto-random.
- Chỉ trả một lần.
- Server chỉ lưu SHA-256 hash.
- Gắn token vào đúng session.
- Thu hồi khi completed/cancelled/expired.
- Không làm thay đổi claim logic cũ.
- Session Drive không được claim lại bằng QR nếu không có QR.

Có thể triển khai bằng một service token chung hiện có:

```text
NativeSessionAccessService
```

Không duplicate thuật toán token.

---

## 11. Session status

Có thể giữ model hiện tại, nhưng API cần biểu đạt giai đoạn server đang chuẩn bị.

Ưu tiên không sửa enum nếu không cần:

```text
uploading = server đang tải/xử lý Drive
ready = assets đã sẵn sàng
transferring = Native đang tải
```

UI Native có thể hiển thị `uploading` thành:

```text
Đang chuẩn bị ảnh
```

Có thể thêm metadata:

```json
{
  "preparation": {
    "total": 42,
    "pending": 20,
    "ready": 21,
    "failed": 1,
    "currentFileName": "IMG_0012.HEIC"
  }
}
```

---

## 12. Status API cho Native-created session

API trạng thái hiện có đang dùng quyền browser owner hoặc cơ chế riêng.

Cần bổ sung khả năng đọc trạng thái bằng Bearer native token:

```http
GET /api/import-sessions/:sessionId
Authorization: Bearer {nativeAccessToken}
```

Hoặc endpoint riêng:

```http
GET /api/import-sessions/:sessionId/preparation
Authorization: Bearer {nativeAccessToken}
```

Ưu tiên mở rộng backward-compatible endpoint hiện có.

Không làm mất khả năng browser dùng owner token.

---

## 13. Chỉ tải item đã chọn

Đây là invariant bắt buộc:

```text
Original download count == selectedItemIds count
```

Inspect và preview không được tải original.

Quy trình:

```text
Native chọn 30 / 1.000 item
→ backend tạo 30 ImportAsset
→ backend gọi original download đúng 30 lần
```

Không prefetch original.

Không “tối ưu trước” toàn folder.

---

## 14. Download pipeline

Concurrency đề xuất:

```env
GOOGLE_DRIVE_DOWNLOAD_CONCURRENCY=3
GOOGLE_DRIVE_PROCESS_CONCURRENCY=1
```

Pipeline:

```text
Google Drive stream
→ temporary/{sessionId}/{assetId}.source
→ kiểm byte thực tế
→ validate MIME/header/ImageIO
→ optimize hoặc keep original
→ SHA-256 trên output
→ StorageProvider.moveAsset
→ asset ready
```

Không dùng:

- `Buffer` toàn file.
- `readFile` cho file lớn.
- nhiều decode song song.
- filename nguồn làm path trực tiếp.

---

## 15. Chế độ ảnh

### Keep original

```text
mode = keep_original
```

- Không resize.
- Không nén.
- Không đổi format.
- SHA-256 trên original.

### Optimized

```text
mode = optimized
```

MVP:

- JPEG: cạnh dài tối đa 3000 px, quality khoảng 85%, không upscale.
- HEIC: giữ nguyên.
- PNG có alpha: giữ nguyên.
- GIF: giữ nguyên.
- TIFF/WebP: theo support thực tế; fallback original.
- Optimize lỗi: fallback original, không làm mất asset.

Metadata manifest phải phản ánh output thực tế:

- filename.
- MIME.
- size.
- width/height nếu có.
- SHA-256.

---

## 16. Partial failure

Nếu một số item lỗi:

```text
selected = 30
ready = 28
failed = 2
```

Session chỉ chuyển `ready` khi:

- mọi item đã terminal;
- có ít nhất một asset ready.

Manifest chỉ chứa asset ready.

Native nhận thông tin số file failed qua status.

Nếu tất cả failed:

```text
session = failed
```

Không cho lấy manifest rỗng như session thành công.

---

## 17. Cancel

Native gọi:

```http
DELETE /api/import-sessions/:sessionId
Authorization: Bearer {nativeAccessToken}
```

Backend:

- validate token;
- đánh dấu cancelled;
- dừng queue;
- abort download có thể abort;
- xóa temporary;
- xóa asset;
- thu hồi token;
- không ảnh hưởng session khác.

Owner-token DELETE của browser vẫn giữ nguyên.

---

## 18. Recovery và server restart

Hạ tầng hiện tại persist `sessions.json`, chưa có job queue thực thụ.

MVP cần:

- Persist asset metadata trước khi bắt đầu download.
- Persist trạng thái sau mỗi asset.
- Temporary file dở được cleanup.
- Khi restart, asset đang xử lý dở chuyển `failed` hoặc `pending` theo policy rõ ràng.
- Không đánh dấu ready nếu file chưa tồn tại/checksum chưa hoàn tất.
- Native có thể hỏi lại status.

Không cần xây distributed queue trong MVP, nhưng phải ghi rõ giới hạn.

---

## 19. Cleanup

Tái sử dụng cleanup hiện có:

- session TTL.
- asset completed bị xóa ngay.
- temporary TTL.
- session expired.

Bổ sung cleanup:

- inspection hết hạn.
- preview token hết hạn.
- orphan Drive temporary file.
- cancelled Drive session.

---

## 20. Config đề xuất

```env
GOOGLE_DRIVE_SHARE_IMPORT_ENABLED=false
GOOGLE_DRIVE_CREDENTIALS_PATH=/run/secrets/google-drive-service-account.json

GOOGLE_DRIVE_INSPECTION_TTL_MINUTES=30
GOOGLE_DRIVE_PREVIEW_TTL_MINUTES=15

GOOGLE_DRIVE_MAX_INSPECT_FILES=5000
GOOGLE_DRIVE_MAX_SELECTED_FILES=300
GOOGLE_DRIVE_MAX_FOLDER_DEPTH=5

GOOGLE_DRIVE_DOWNLOAD_CONCURRENCY=3
GOOGLE_DRIVE_PROCESS_CONCURRENCY=1
GOOGLE_DRIVE_REQUEST_TIMEOUT_MS=60000
GOOGLE_DRIVE_MAX_RETRIES=3
```

Tiếp tục dùng:

```env
MAX_FILE_SIZE_BYTES
MAX_SESSION_SIZE_BYTES
SESSION_TTL_HOURS
UPLOAD_STORAGE_PATH
```

---

## 21. Error codes

```text
FEATURE_DISABLED
GOOGLE_DRIVE_INVALID_LINK
GOOGLE_DRIVE_UNSUPPORTED_LINK
GOOGLE_DRIVE_PERMISSION_DENIED
GOOGLE_DRIVE_RESOURCE_NOT_FOUND
GOOGLE_DRIVE_NO_SUPPORTED_IMAGES
GOOGLE_DRIVE_INSPECTION_EXPIRED
GOOGLE_DRIVE_TOO_MANY_FILES
GOOGLE_DRIVE_TOO_MANY_SELECTED_FILES
GOOGLE_DRIVE_FILE_NOT_DOWNLOADABLE
GOOGLE_DRIVE_FILE_TOO_LARGE
GOOGLE_DRIVE_DOWNLOAD_FAILED
GOOGLE_DRIVE_RATE_LIMITED
GOOGLE_DRIVE_PREVIEW_FAILED
GOOGLE_DRIVE_PROCESSING_FAILED
```

Giữ format lỗi hiện có:

```json
{
  "success": false,
  "code": "GOOGLE_DRIVE_PERMISSION_DENIED",
  "message": "Không thể truy cập thư mục. Hãy kiểm tra quyền chia sẻ Google Drive."
}
```

---

## 22. Bảo mật

### SSRF

- Host whitelist.
- Không dùng URL client làm download URL trực tiếp.
- Không follow redirect tùy ý.
- Giới hạn response size/time.

### Inspection authorization

Inspection ID và item ID phải opaque, khó đoán.

Cần rate limit:

```text
inspect
pagination
preview
create session
```

### Native token

- Hash at rest.
- Bearer authorization.
- Không log.
- Không trả lần hai.
- Revocation terminal.

### Path

- Sanitize filename.
- Không path traversal.
- Không absolute path.
- Không ghi đè.

---

## 23. Test API trước khi nối Native

### Health/config

```bash
curl -sS http://localhost:4318/api/health | jq
curl -sS http://localhost:4318/api/config | jq
```

### Inspect

```bash
curl -sS \
  -X POST http://localhost:4318/api/google-drive-share/inspect \
  -H 'Content-Type: application/json' \
  -d '{
    "url": "GOOGLE_DRIVE_SHARE_LINK",
    "includeSubfolders": false
  }' | tee /tmp/drive-inspect.json | jq
```

### Pagination

```bash
INSPECTION_ID=$(jq -r '.inspectionId' /tmp/drive-inspect.json)
CURSOR=$(jq -r '.nextCursor // empty' /tmp/drive-inspect.json)

curl -sS \
  "http://localhost:4318/api/google-drive-share/inspections/${INSPECTION_ID}/items?cursor=${CURSOR}" \
  | jq
```

### Preview

```bash
PREVIEW_URL=$(jq -r '.items[0].thumbnailUrl' /tmp/drive-inspect.json)

curl -i \
  "http://localhost:4318${PREVIEW_URL}" \
  -o /tmp/drive-preview
```

### Create session

```bash
ITEM_1=$(jq -r '.items[0].itemId' /tmp/drive-inspect.json)
ITEM_2=$(jq -r '.items[1].itemId' /tmp/drive-inspect.json)

curl -sS \
  -X POST http://localhost:4318/api/google-drive-share/import-sessions \
  -H 'Content-Type: application/json' \
  -d "{
    \"inspectionId\": \"${INSPECTION_ID}\",
    \"selectedItemIds\": [\"${ITEM_1}\", \"${ITEM_2}\"],
    \"mode\": \"optimized\",
    \"clientType\": \"nizi_native\"
  }" | tee /tmp/drive-session.json | jq
```

### Poll

```bash
SESSION_ID=$(jq -r '.sessionId' /tmp/drive-session.json)
NATIVE_TOKEN=$(jq -r '.nativeAccessToken' /tmp/drive-session.json)

watch -n 1 "
curl -sS \
  -H 'Authorization: Bearer ${NATIVE_TOKEN}' \
  http://localhost:4318/api/import-sessions/${SESSION_ID} | jq
"
```

### Manifest

```bash
curl -sS \
  -H "Authorization: Bearer ${NATIVE_TOKEN}" \
  http://localhost:4318/api/import-sessions/${SESSION_ID}/manifest \
  | tee /tmp/drive-manifest.json | jq
```

### Download

```bash
ASSET_ID=$(jq -r '.assets[0].id' /tmp/drive-manifest.json)

curl -L \
  -H "Authorization: Bearer ${NATIVE_TOKEN}" \
  http://localhost:4318/api/import-assets/${ASSET_ID}/download \
  -o /tmp/drive-asset
```

### Range

```bash
curl -i \
  -H "Authorization: Bearer ${NATIVE_TOKEN}" \
  -H 'Range: bytes=0-1023' \
  http://localhost:4318/api/import-assets/${ASSET_ID}/download
```

Kỳ vọng:

```text
206 Partial Content
```

### SHA-256

```bash
shasum -a 256 /tmp/drive-asset
```

So sánh với manifest.

### Completed

```bash
curl -sS \
  -X POST \
  -H "Authorization: Bearer ${NATIVE_TOKEN}" \
  http://localhost:4318/api/import-assets/${ASSET_ID}/completed \
  | jq
```

Tải lại phải trả:

```text
410 ASSET_LOCKED
```

---

## 24. Test folder lớn

Bắt buộc:

```text
Folder 1.000 ảnh
→ inspect metadata
→ Native/test script chọn 30
→ original download count phải đúng 30
```

Mock adapter cần đếm:

```text
listCalls
thumbnailCalls
originalDownloadCalls
```

Assertion:

```text
originalDownloadCalls == selectedItemIds.count
```

---

## 25. Automated tests

### Unit

- Parse link.
- Host whitelist.
- Resource key.
- Opaque ID.
- Inspection expiry.
- Pagination cursor.
- Filename sanitize.
- MIME validation.
- State transition.

### Integration với mock Drive

- Folder nhỏ.
- Folder 1.000 item.
- Chọn 2/1.000.
- Permission denied.
- Rate limit.
- Retry.
- Download failure.
- Partial failure.
- Cancel.
- Cleanup.
- Optimize.
- Keep original.
- Direct native token.
- Manifest.
- Range.
- Completed.

### Regression

Tất cả test hiện có của browser upload và QR phải pass.

---

## 26. Sprint triển khai

### Sprint 0 — Prototype Drive access

- Credential.
- Public link.
- Resource key.
- List.
- Download.
- Không sửa pipeline cũ.

### Sprint 1 — Inspection

- Parse.
- Inspect API.
- Pagination.
- Preview.
- TTL.
- Tests.

### Sprint 2 — Native-created session

- API create.
- Direct native token.
- Status by Bearer.
- Asset metadata.
- Tests.

### Sprint 3 — Download và processing

- Stream.
- Validation.
- Optimize.
- SHA-256.
- StorageProvider.
- Partial failure.
- Cancel.

### Sprint 4 — Integration

- Manifest.
- Download.
- Range.
- Completed.
- Curl end-to-end.
- Native handoff.

### Sprint 5 — Regression/hardening

- Folder 1.000.
- Rate limit.
- Cleanup.
- Restart.
- Upload/QR regression.
- Feature flag.

---

## 27. Tiêu chí nghiệm thu

Backend hoàn thành khi:

1. Feature flag hoạt động.
2. Luồng upload/QR cũ không thay đổi.
3. Native inspect được Drive link.
4. Backend trả metadata/thumbnail, không tải original.
5. Pagination folder lớn hoạt động.
6. Native gửi selected item.
7. Backend chỉ tải item đã chọn.
8. Backend stream xuống disk.
9. Keep original hoạt động.
10. Optimized hoạt động.
11. Session dùng model hiện có.
12. Native token được cấp trực tiếp và lưu hash.
13. Native poll được preparation status.
14. Manifest hiện có dùng được.
15. Range dùng được.
16. SHA-256 đúng.
17. Completed xóa asset.
18. Cancel cleanup đúng.
19. Session/inspection expiry đúng.
20. Folder 1.000 ảnh chỉ tải số selected.
21. Toàn bộ regression test cũ pass.

---

## 28. Chỉ dẫn cuối cho Codex

Không xây lại Nizi Move.

Không sửa luồng QR để phục vụ Drive.

Không đưa Google logic vào Native protocol.

Chỉ bổ sung nhánh:

```text
Native Drive Link
→ Drive inspection
→ server prepares existing ImportSession
→ direct native token
```

Sau đó dùng nguyên:

```text
manifest
→ download
→ Range
→ checksum
→ completed
```

Mọi sửa đổi shared service phải có regression test cho browser upload và QR trước khi merge.
