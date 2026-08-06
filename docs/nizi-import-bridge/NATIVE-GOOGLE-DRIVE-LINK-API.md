# Native API — nhập ảnh từ Google Drive Share Link

Tài liệu này dành cho Nizi Native. Base URL production là `https://move.nizi.vn`. Luồng này **không dùng QR và không gọi `claim`**: app Native nhận Bearer token đúng một lần khi tạo session.

Mọi lỗi có dạng:

```json
{ "success": false, "code": "ERROR_CODE", "message": "Mô tả lỗi" }
```

## Điều kiện và nguyên tắc

- Backend chỉ bật khi `GOOGLE_DRIVE_SHARE_IMPORT_ENABLED=true`. Nếu tắt, ba API Drive trả `503 FEATURE_DISABLED`.
- Chỉ hỗ trợ Google Drive share link dạng folder, `file/d/.../view`, `open?id=...`, hoặc `uc?id=...`.
- Không gửi credential Google, `resourceKey`, hoặc Google file ID lên app Native.
- `thumbnailUrl` là URL tương đối; ghép với Base URL trước khi gọi.
- Lưu `nativeAccessToken` trong Keychain/memory; không log, không đưa vào URL. Token chỉ được trả ở phản hồi tạo session và không thể lấy lại.

## Luồng tích hợp

```text
POST inspect link
GET  page tiếp theo (nếu có)
Native chọn itemId
POST create Drive session → nhận sessionId + nativeAccessToken
GET  session status (poll đến ready/failed)
GET  manifest
GET  từng asset download (Bearer, hỗ trợ Range)
POST completed/failed từng asset
POST session completed
```

## 1. Đọc Google Drive share link

`POST /api/google-drive-share/inspect`

```json
{
  "url": "https://drive.google.com/drive/folders/FOLDER_ID?resourcekey=...",
  "includeSubfolders": false
}
```

Phản hồi `200`:

```json
{
  "success": true,
  "inspectionId": "opaque-inspection-id",
  "source": { "type": "folder", "name": "Ảnh sự kiện" },
  "items": [{
    "itemId": "opaque-item-id",
    "name": "IMG_0012.HEIC",
    "mimeType": "image/heic",
    "size": 5283942,
    "width": 4032,
    "height": 3024,
    "modifiedTime": "2026-07-20T10:30:00Z",
    "thumbnailUrl": "/api/google-drive-share/previews/preview-token",
    "canDownload": true
  }],
  "nextCursor": "opaque-next-cursor",
  "summary": { "loadedItems": 100, "imageItems": 100, "knownBytes": 623456789 }
}
```

`inspectionId` và `itemId` là opaque: Native chỉ lưu/chuyển lại nguyên giá trị, không suy diễn nội dung. Inspection chỉ chứa metadata, hết hạn sau `GOOGLE_DRIVE_INSPECTION_TTL_MINUTES` (mặc định 30 phút).

## 2. Phân trang và thumbnail

`GET /api/google-drive-share/inspections/{inspectionId}/items?cursor={nextCursor}`

Phản hồi cùng cấu trúc `items`, `nextCursor`, `summary` như inspect. Gọi đến khi `nextCursor` không còn xuất hiện. `400 GOOGLE_DRIVE_INSPECTION_EXPIRED` nghĩa là phải inspect link lại.

`GET /api/google-drive-share/previews/{previewToken}?size=320`

`size` tùy chọn, từ 160 đến 1600 pixel. Đây chỉ là thumbnail proxy, không phải original; không cần Bearer token. Nếu preview hết hạn hoặc Google từ chối, API trả `404`/`502 GOOGLE_DRIVE_PREVIEW_FAILED`; vẫn có thể chọn item nếu `canDownload=true`.

## 3. Tạo session trực tiếp cho Native

`POST /api/google-drive-share/import-sessions`

```json
{
  "inspectionId": "opaque-inspection-id",
  "selectedItemIds": ["opaque-item-1", "opaque-item-2"],
  "mode": "optimized",
  "clientType": "nizi_native"
}
```

`mode` nhận `optimized` (JPEG tối đa 3000px, quality 85; các định dạng không hỗ trợ sẽ giữ nguyên) hoặc `original`/`keep_original` (không đổi file). Chỉ những `selectedItemIds` mới được backend tải original.

Phản hồi `201`:

```json
{
  "success": true,
  "sessionId": "imp_...",
  "nativeAccessToken": "one-time-secret",
  "status": "preparing",
  "totalAssets": 2
}
```

Ngay sau khi nhận phản hồi, lưu token trước khi làm bất kỳ request khác. Không gọi `/claim` cho session này; endpoint đó trả `409 SESSION_DIRECT_NATIVE_ACCESS`.

## 4. Poll quá trình chuẩn bị

`GET /api/import-sessions/{sessionId}`

Header bắt buộc:

```http
Authorization: Bearer {nativeAccessToken}
```

Phản hồi `200` có `data.status` và `data.preparation`:

```json
{
  "success": true,
  "data": {
    "sessionId": "imp_...",
    "status": "uploading",
    "readyAssets": 4,
    "failedAssets": 1,
    "failures": [{ "filename": "bad.jpg", "code": "GOOGLE_DRIVE_DOWNLOAD_FAILED" }],
    "preparation": { "total": 8, "pending": 3, "ready": 4, "failed": 1, "currentFileName": "IMG_0005.JPG" }
  }
}
```

Poll 1–2 giây/lần khi `status=uploading` (hiển thị “Đang chuẩn bị ảnh”). Chỉ gọi manifest khi `status=ready`. `ready` có thể chứa một phần ảnh nếu một số ảnh lỗi; `failed` nghĩa là không còn asset nào để tải. Sau khi server restart, asset Drive đang chuẩn bị được đánh dấu failed với mã `GOOGLE_DRIVE_SERVER_RESTARTED`; Native đọc `failures` và cho người dùng tạo lại session nếu cần.

## 5. Manifest và tải asset

`GET /api/import-sessions/{sessionId}/manifest` với Bearer token. Nếu chưa sẵn sàng API trả `409 SESSION_NOT_READY`; nếu không còn ảnh sẵn sàng trả `409 NO_READY_ASSETS`.

Phản hồi manifest chỉ chứa asset `ready`:

```json
{
  "protocolVersion": 1,
  "sessionId": "imp_...",
  "status": "transferring",
  "expiresAt": "...",
  "assets": [{
    "assetId": "asset_1_...",
    "filename": "IMG_0012.jpg",
    "relativePath": "Album/IMG_0012.jpg",
    "mimeType": "image/jpeg",
    "byteSize": 123456,
    "sha256": "hex-sha256",
    "downloadUrl": "https://move.nizi.vn/api/import-assets/asset_1_.../download"
  }]
}
```

Với từng `downloadUrl`, dùng `Authorization: Bearer {nativeAccessToken}`. Endpoint hỗ trợ HTTP `Range`/`206`, và trả `Accept-Ranges: bytes`. Tải ra file tạm, kiểm `byteSize` và SHA-256, sau đó lưu vào Photos/local storage. Không đánh dấu hoàn tất trước khi lưu thành công.

## 6. Ghi nhận kết quả và đóng/hủy session

Sau mỗi file đã lưu thành công:

```http
POST /api/import-assets/{assetId}/completed
Authorization: Bearer {nativeAccessToken}
```

Server xóa original tạm ngay; download asset đó sau đó trả `410 ASSET_LOCKED`.

Nếu không thể retry:

```http
POST /api/import-assets/{assetId}/failed
Authorization: Bearer {nativeAccessToken}
Content-Type: application/json

{ "reason": "PHOTO_LIBRARY_SAVE_FAILED" }
```

Khi toàn bộ asset manifest đã `completed` (hoặc `skipped`):

```http
POST /api/import-sessions/{sessionId}/completed
Authorization: Bearer {nativeAccessToken}
```

Endpoint đóng phiên và thu hồi token. Nếu người dùng hủy khi backend còn chuẩn bị hoặc đang tải:

```http
DELETE /api/import-sessions/{sessionId}
Authorization: Bearer {nativeAccessToken}
```

Server abort job Drive, xóa file tạm/asset và thu hồi token.

## Mã lỗi Native nên xử lý

| Code | Cách xử lý UI |
| --- | --- |
| `FEATURE_DISABLED` | Ẩn/tắt tính năng, báo server chưa bật Drive import. |
| `GOOGLE_DRIVE_INVALID_LINK`, `GOOGLE_DRIVE_UNSUPPORTED_LINK` | Yêu cầu dán link Drive hợp lệ. |
| `GOOGLE_DRIVE_PERMISSION_DENIED`, `GOOGLE_DRIVE_RESOURCE_NOT_FOUND` | Yêu cầu kiểm tra link/quyền “Anyone with the link”. |
| `GOOGLE_DRIVE_INSPECTION_EXPIRED` | Inspect lại rồi chọn lại ảnh. |
| `GOOGLE_DRIVE_FILE_NOT_DOWNLOADABLE`, `GOOGLE_DRIVE_FILE_TOO_LARGE` | Hiển thị và bỏ chọn file tương ứng. |
| `GOOGLE_DRIVE_RATE_LIMITED` | Backoff rồi thử lại. |
| `SESSION_UNAUTHORIZED` | Xóa token local, không retry tự động. |
| `SESSION_EXPIRED` | Tạo session mới. |
| `SESSION_NOT_READY` | Tiếp tục poll status. |
| `NO_READY_ASSETS` | Hiển thị lỗi chuẩn bị; không gọi download. |
