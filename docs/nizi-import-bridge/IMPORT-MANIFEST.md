# Import Manifest v1

`GET /api/import-sessions/:sessionId/manifest` trả `protocolVersion`, `sessionId`, `status`, `expiresAt` và `assets`. Mỗi asset có `assetId`, `filename`, `relativePath`, `mimeType`, `byteSize`, `sha256`, metadata EXIF tùy chọn, grouping sơ bộ và `downloadUrl`.

Native nên xử lý tuần tự hoặc với concurrency thấp: tải asset (có thể resume bằng `Range`), kiểm SHA-256, lưu Photos, báo `/completed`, rồi xoá file tạm local. Lời gọi `/completed` là xác nhận không thể đảo ngược: server xoá bản asset, `downloadUrl` trả `410 ASSET_LOCKED` cho mọi lần tải sau. Khi một asset lỗi, báo `/failed` và tiếp tục asset còn lại; retry phải diễn ra trước `/completed`.
