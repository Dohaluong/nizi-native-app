## Kết nối Nizi Native với Import Bridge

Native app chỉ cần xử lý luồng kết nối qua QR, không cần biết nguồn ảnh là máy tính hay Google Drive.

1. Quét QR do Nizi Move tạo. QR chứa URL dạng:

```text
https://move.nizi.vn/import/{sessionId}?token={qrToken}
```

2. Native lấy `sessionId` và `token`, gọi:

```http
POST /api/import-sessions/{sessionId}/claim
Content-Type: application/json

{ "token": "{qrToken}" }
```

3. Nếu thành công, server trả `accessToken`. Lưu token này tạm thời trong memory/Keychain cho đến khi hoàn tất phiên.

4. Native tải manifest:

```http
GET /api/import-sessions/{sessionId}/manifest
Authorization: Bearer {accessToken}
```

Manifest gồm danh sách asset, filename, MIME, kích thước, SHA-256 và `downloadUrl`.

5. Với từng asset, tải file qua `downloadUrl` cùng Bearer token. Hỗ trợ HTTP Range để resume. Sau khi tải xong:
   - kiểm kích thước và SHA-256;
   - lưu thành công vào Photos/local storage;
   - chỉ sau đó gọi:

```http
POST /api/import-assets/{assetId}/completed
Authorization: Bearer {accessToken}
```

Nếu thất bại không thể retry, gọi:

```http
POST /api/import-assets/{assetId}/failed
Authorization: Bearer {accessToken}

{ "reason": "..." }
```

6. Khi tất cả asset đã hoàn tất, đóng phiên:

```http
POST /api/import-sessions/{sessionId}/completed
Authorization: Bearer {accessToken}
```

Yêu cầu bảo mật:

- Không đưa Google Drive credential vào Native, QR hoặc manifest.
- `accessToken` chỉ dùng cho một session và bị thu hồi khi session hoàn tất.
- Không đánh dấu asset `completed` trước khi file đã được lưu thành công.
- Hiển thị rõ tiến trình theo từng ảnh và cho phép retry các ảnh lỗi.