# SPEC — NIZI NATIVE COMPATIBILITY FOR GOOGLE DRIVE SHARE IMPORT

**Dự án:** Nizi Native iOS  
**Phạm vi:** Xác nhận tương thích với ImportSession do Nizi Move tạo từ Google Drive Share Link  
**Mức độ thay đổi dự kiến:** Rất nhỏ hoặc bằng 0  
**Điều kiện bắt đầu:** Chỉ triển khai sau khi Nizi Move vượt qua test API và curl Native simulation.

## 1. Mục tiêu

Native tiếp tục dùng protocol hiện có:

```text
QR
→ claim
→ manifest
→ download
→ HTTP Range
→ SHA-256
→ save Photos
→ SwiftData index
→ asset completed
→ session completed
```

Native không truy cập Google Drive và không biết folder/share link/Google credential.

## 2. Không thêm vào Native

- Google SDK.
- Google Sign-In.
- Drive API.
- Document Picker.
- Google credential.
- Share link input.
- Cloud browser.
- Code path download riêng cho Google Drive.

## 3. Điều kiện trước khi mở task Native

Backend phải cung cấp bằng chứng curl:

- claim thành công;
- manifest hợp lệ;
- download thành công;
- Range 206;
- checksum đúng;
- completed thành công;
- tải lại trả 410;
- session close thành công.

Nếu curl chưa pass, không sửa Native để workaround.

## 4. Công việc Native bắt buộc

### 4.1. Regression bằng session Google Drive

1. Scan QR.
2. Claim.
3. Decode manifest.
4. Download asset.
5. Resume Range.
6. Kiểm SHA-256.
7. Lưu Photos.
8. Index SwiftData.
9. Gửi completed.
10. Cleanup.

### 4.2. Format test

- JPEG optimized.
- JPEG original.
- HEIC original.
- PNG.
- GIF nếu protocol hiện tại hỗ trợ.
- Tên Unicode.
- File lớn.
- Batch nhiều file.

### 4.3. Network test

- Wi-Fi.
- LTE.
- Mất mạng giữa download.
- Background/foreground.
- Resume Range.
- Token hết hạn.
- Một asset failed nhưng asset khác tiếp tục.

## 5. Thay đổi optional

Nếu manifest thêm:

```json
{
  "sourceType": "google_drive_share"
}
```

Native có thể decode optional:

```swift
let sourceType: String?
```

Nhưng:

- không bắt buộc;
- không dùng để rẽ nhánh pipeline;
- session cũ vẫn decode;
- Native cũ có thể bỏ qua.

UI `Nguồn: Google Drive` không thuộc MVP bắt buộc.

## 6. Không tạo logic riêng theo nguồn

Sai:

```swift
if source == .googleDrive {
    downloadGoogleDriveWay()
}
```

Đúng:

```swift
processImportSession(manifest)
```

## 7. Hướng test trước khi chạy app

Nhận từ backend:

```text
PUBLIC_BASE_URL
sessionId
QR URL
pairing code
expected asset count
expected checksum list
expected total bytes
```

Kiểm tra health:

```bash
curl -sS https://move.nizi.vn/api/health | jq
```

Sau đó dùng chính script curl claim/manifest/download của tài liệu Nizi Move.

Chỉ khi curl pass nhưng app fail mới khảo sát Native.

## 8. Test trên thiết bị thật

### Case 1 — 2 ảnh

- 1 JPEG optimized.
- 1 HEIC original.

### Case 2 — 50 ảnh

- Mixed formats.
- Tổng dung lượng vừa.

### Case 3 — file lớn

- HTTP Range.
- Resume.
- Background/foreground.

### Case 4 — một asset lỗi

- Asset khác vẫn tiếp tục.
- Không đóng session sai trạng thái.

### Case 5 — cleanup

- Photos save thành công.
- Completed callback.
- Server trả 410 khi tải lại.

## 9. Regression bắt buộc

Test cả hai loại session:

```text
browser_upload

google_drive_share
```

Cùng đi qua một pipeline Native.

## 10. Tiêu chí nghiệm thu

1. Google Drive session claim như browser session.
2. Manifest decode không lỗi.
3. Không có code path Google riêng.
4. Download và Range hoạt động.
5. SHA-256 đúng.
6. Photos save đúng.
7. SwiftData index đúng.
8. Completed callback đúng.
9. Không duplicate.
10. Session upload máy tính cũ vẫn hoạt động.
11. Không thêm Google SDK/credential.
12. Không regression.

## 11. Definition of done

Nếu Nizi Move giữ nguyên protocol, Native có thể hoàn thành chỉ bằng test và regression verification.

Chỉ sửa production code khi có incompatibility thực tế, kèm:

- request/response gây lỗi;
- file/line;
- nguyên nhân;
- patch tối thiểu;
- regression test.
