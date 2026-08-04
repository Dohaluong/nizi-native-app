# SPEC — NIZI NATIVE: IMPORT ẢNH TỪ GOOGLE DRIVE SHARE LINK

**Dự án:** Nizi Native iOS  
**Phạm vi:** Bổ sung luồng import ảnh mới từ Google Drive Share Link  
**Nguyên tắc bắt buộc:** Không làm ảnh hưởng luồng quét QR hiện có từ Nizi Move

---

## 1. Bối cảnh

Nizi Native hiện đã có luồng nhận ảnh từ máy tính thông qua Nizi Move:

```text
Máy tính
→ chọn ảnh trên web
→ upload lên Nizi Move
→ tạo QR
→ Nizi Native quét QR
→ claim session
→ lấy manifest
→ tải từng ảnh
→ kiểm SHA-256
→ lưu Photos
→ index SwiftData
→ báo completed
```

Luồng này đang hoạt động và phải được giữ nguyên.

Tính năng mới không thay thế luồng QR.

Tính năng mới chỉ bổ sung một cách khác để tạo ImportSession:

```text
Nizi Native
→ user dán Google Drive Share Link
→ Native gửi link về Nizi Move backend
→ backend đọc link và trả danh sách ảnh
→ user chọn ảnh trên Native
→ backend tải và xử lý ảnh trên server
→ backend trả session ready
→ Native dùng pipeline import hiện có để tải ảnh
```

---

## 2. Hai luồng phải cùng tồn tại

### Luồng A — Máy tính sang điện thoại bằng QR

Giữ nguyên hoàn toàn:

```text
Máy tính
→ Nizi Move Web
→ upload
→ QR
→ Native scan
→ claim
→ manifest
→ download
→ import
```

Không thay đổi:

- QR scanner.
- QR parser.
- Pairing code.
- Claim API.
- Native access token hiện có.
- Manifest API.
- Download API.
- HTTP Range.
- SHA-256.
- PhotoKit save.
- SwiftData index.
- Completed/failed callback.
- Cleanup.

### Luồng B — Điện thoại tự dán Google Drive Share Link

Bổ sung mới:

```text
Native nhập link
→ gọi backend inspect
→ nhận metadata + thumbnail
→ user chọn ảnh
→ gọi backend tạo session
→ backend tải ảnh từ Drive
→ backend resize/nén nếu chọn
→ session ready
→ Native nhận manifest
→ download
→ import
```

Hai luồng chỉ khác nhau ở giai đoạn tạo session.

Sau khi session `ready`, cả hai phải đi qua cùng một pipeline.

---

## 3. Kiến trúc mục tiêu

```text
                         ┌──────────────────────────┐
                         │ Luồng A: QR từ máy tính  │
                         └────────────┬─────────────┘
                                      │
                                      ▼
                               Claim ImportSession
                                      │
                                      │
┌──────────────────────────┐          │
│ Luồng B: Dán Drive Link  │          │
└────────────┬─────────────┘          │
             │                        │
             ▼                        │
      Inspect + chọn ảnh              │
             │                        │
             ▼                        │
      Backend chuẩn bị session        │
             │                        │
             └──────────────┬─────────┘
                            ▼
                     ImportSession ready
                            ▼
                         Manifest
                            ▼
                         Download
                            ▼
                        SHA-256
                            ▼
                         Photos
                            ▼
                       SwiftData
                            ▼
                        Completed
```

Điểm hội tụ bắt buộc:

```text
ImportSession ready
```

Không tạo một pipeline tải ảnh riêng cho Google Drive.

---

## 4. Phạm vi Native cần bổ sung

### 4.1. Entry mới trong màn Import

Màn import hiện có phải có hai lựa chọn rõ ràng:

```text
Nhận ảnh

[ Quét mã QR từ máy tính ]

[ Nhập từ Google Drive Link ]
```

Hoặc:

```text
Thêm ảnh

• Quét QR từ Nizi Move
• Dán Google Drive Share Link
```

Luồng QR hiện tại giữ nguyên.

Nút Google Drive mở flow mới.

---

## 5. Màn nhập Google Drive Share Link

Giao diện:

```text
Nhập ảnh từ Google Drive

Dán đường dẫn thư mục hoặc ảnh được chia sẻ.

[ https://drive.google.com/drive/folders/... ]

[ Kiểm tra liên kết ]
```

Hiển thị hướng dẫn:

```text
Link cần có quyền xem phù hợp.
Nizi không lưu tài khoản hoặc mật khẩu Google của bạn.
```

Native không:

- parse HTML Google Drive;
- gọi Google Drive API trực tiếp;
- lưu Google API key;
- đăng nhập Google;
- tải ảnh gốc từ Google.

Native chỉ gửi link cho Nizi Move backend.

---

## 6. Inspect API

Native gọi:

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

Response mẫu:

```json
{
  "success": true,
  "inspectionId": "inspection-id",
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
      "thumbnailUrl": "https://move.nizi.vn/api/google-drive-share/previews/...",
      "canDownload": true
    }
  ],
  "nextCursor": "opaque-cursor"
}
```

Native không được nhận hoặc lưu:

- Google file ID thô nếu backend không cần expose.
- Resource key.
- Google token.
- Google credential.
- Direct original download URL.

---

## 7. Màn chọn ảnh

Sau inspect, Native hiển thị gallery.

Yêu cầu:

- Lazy grid.
- Lazy thumbnail.
- Pagination hoặc infinite scroll.
- Chọn/bỏ chọn từng ảnh.
- Chọn tất cả ảnh đã tải metadata.
- Bỏ chọn tất cả.
- Hiển thị số ảnh đã chọn.
- Hiển thị tổng dung lượng đã chọn.
- Không tải ảnh gốc.
- Không giữ toàn bộ thumbnail trong RAM.
- Ảnh `canDownload=false` không thể chọn.
- Item lỗi có placeholder và thông báo rõ.

Native chỉ hiển thị thumbnail do backend cung cấp.

---

## 8. Pagination

Nếu response có `nextCursor`, Native gọi:

```http
GET /api/google-drive-share/inspections/{inspectionId}/items?cursor={cursor}
```

Yêu cầu:

- Không tải tất cả 1.000–5.000 item ngay lập tức.
- Chỉ lấy trang tiếp theo khi gần cuối danh sách.
- Không trùng item.
- Giữ selection theo `itemId`.
- Nếu inspection hết hạn, hiển thị yêu cầu kiểm tra lại link.

---

## 9. Chế độ import

Native cho user chọn:

```text
○ Giữ nguyên ảnh gốc
● Tối ưu dung lượng
```

Request gửi backend:

```text
keep_original
optimized
```

Native không tự resize ảnh Google Drive ở giai đoạn này.

Toàn bộ xử lý nặng diễn ra trên server.

---

## 10. Tạo session từ Native

Sau khi user xác nhận:

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

Response đề xuất:

```json
{
  "success": true,
  "sessionId": "import-session-id",
  "nativeAccessToken": "native-access-token",
  "status": "preparing"
}
```

Điểm khác luồng QR:

- Luồng QR phải claim bằng QR token.
- Luồng Native Drive được backend cấp quyền cho session ngay khi tạo.

Không cần:

- QR.
- Pairing code.
- Camera scan.
- Claim bằng QR token.

---

## 11. Bảo mật session Native-created

`nativeAccessToken` phải:

- sinh random;
- chỉ trả một lần;
- lưu trong Keychain;
- không ghi log;
- không lưu UserDefaults;
- không đưa analytics;
- thu hồi khi session completed/cancelled/expired.

Backend chỉ lưu hash token nếu kiến trúc hiện tại đang làm như vậy.

Native phải xóa token khỏi Keychain khi session terminal.

---

## 12. Theo dõi backend chuẩn bị ảnh

Sau khi tạo session:

```text
status = preparing
```

Native hiển thị:

```text
Đang chuẩn bị ảnh trên Nizi Move

17 / 42 ảnh đã sẵn sàng
```

Native poll:

```http
GET /api/import-sessions/{sessionId}
Authorization: Bearer {nativeAccessToken}
```

Khoảng poll MVP:

```text
1–2 giây khi màn đang mở
```

Khi app background:

- giảm hoặc dừng poll;
- khi foreground thì hỏi lại trạng thái;
- không tạo timer chạy vô hạn;
- không dùng polling ở main thread.

Response mẫu:

```json
{
  "success": true,
  "session": {
    "id": "session-id",
    "status": "preparing",
    "totalAssets": 42,
    "readyAssets": 17,
    "failedAssets": 1
  }
}
```

---

## 13. Khi session ready

Khi backend trả:

```text
ready
```

Native chuyển sang pipeline import hiện có:

```text
GET manifest
→ download assets
→ Range/resume
→ SHA-256
→ Photos
→ SwiftData
→ completed
```

Không viết thêm:

```swift
GoogleDriveDownloadCoordinator
```

nếu downloader hiện có đã xử lý manifest asset.

Đúng:

```swift
existingImportCoordinator.start(
    sessionId: sessionId,
    accessToken: nativeAccessToken
)
```

Tên API thực tế phải theo codebase hiện tại.

---

## 14. Tái sử dụng pipeline hiện có

Bắt buộc tái sử dụng:

- Manifest model.
- Download queue.
- URLSession download.
- Background/resume nếu đã có.
- HTTP Range.
- SHA-256.
- Temporary file handling.
- PhotoKit saver.
- SwiftData index.
- Asset completed callback.
- Asset failed callback.
- Session completed callback.
- Cleanup.

Không duplicate code chỉ vì source là Google Drive.

---

## 15. State machine đề xuất

### UI flow mới

```text
idle
inspecting
browsing
creatingSession
preparing
ready
importing
partiallyCompleted
completed
failed
cancelled
```

### Mapping sang backend

```text
Native browsing
→ chưa có ImportSession

Native preparing
→ backend session uploading/preparing

Native ready
→ backend session ready

Native importing
→ backend claimed/transferring

Native completed
→ backend completed
```

Tên state chính xác phải theo model hiện có.

---

## 16. Cancel

### Cancel trước khi tạo ImportSession

- Chỉ hủy inspection UI.
- Không có server asset cần cleanup.
- Có thể bỏ inspection tự hết TTL.

### Cancel sau khi tạo ImportSession

Native gọi API xóa/hủy session hiện có hoặc API tương ứng:

```http
DELETE /api/import-sessions/{sessionId}
Authorization: Bearer {nativeAccessToken}
```

Backend:

- dừng tải file mới;
- abort job có thể abort;
- xóa temporary;
- xóa asset;
- thu hồi token.

Native:

- dừng poll;
- dừng download;
- xóa token Keychain;
- trở về màn import.

---

## 17. Recovery khi app bị đóng

Native phải persist tối thiểu:

- sessionId;
- trạng thái local;
- thời điểm tạo;
- số ảnh;
- mode;
- token trong Keychain.

Khi app mở lại:

1. Tìm session chưa terminal.
2. Lấy token từ Keychain.
3. Gọi status.
4. Nếu backend vẫn `preparing`, tiếp tục theo dõi.
5. Nếu `ready`, tiếp tục manifest/download.
6. Nếu `expired/cancelled/failed`, dọn local state và token.
7. Không tạo session mới trùng.

Nếu pipeline hiện tại đã có import persistence, mở rộng tối thiểu để lưu loại entry mới.

---

## 18. Không ảnh hưởng luồng QR hiện có

Codex phải bảo đảm:

### Không thay đổi behavior

```text
Scan QR
→ parse URL
→ claim
→ store token
→ import
```

### Không đổi API claim hiện có

Luồng QR vẫn dùng:

```http
POST /api/import-sessions/{sessionId}/claim
```

### Không bắt QR session đi qua API create-from-Drive

Hai entry riêng:

```text
QR entry
Drive Link entry
```

Hai entry hội tụ sau khi có:

```text
sessionId + nativeAccessToken
```

---

## 19. Cấu trúc code đề xuất

Không tạo module `LocalFileImport`.

Đề xuất bổ sung trong hoặc cạnh module Nizi Move hiện có:

```text
Nizi/Features/NiziMove/
├── Domain/
│   ├── GoogleDriveInspectionModels.swift
│   └── NiziMoveImportSource.swift
├── Application/
│   ├── GoogleDriveShareImportCoordinator.swift
│   └── existing NiziMoveImportCoordinator.swift
├── Infrastructure/
│   ├── GoogleDriveShareAPI.swift
│   └── existing NiziMoveAPI.swift
└── Presentation/
    ├── GoogleDriveLinkImportView.swift
    ├── GoogleDriveImagePickerView.swift
    ├── GoogleDrivePreparationView.swift
    └── existing QR views
```

Có thể dùng chung một API client nếu phù hợp.

Không duplicate downloader/saver.

---

## 20. File cần khảo sát trước khi sửa

Codex phải đọc:

- QR import entry hiện tại.
- QR scanner/parser.
- `NiziMoveAPI`.
- `NiziMoveImportCoordinator`.
- `NiziMoveImportStore`.
- Manifest models.
- Download coordinator.
- `NiziMovePhotoSaver`.
- Keychain token store.
- SwiftData import session models.
- Navigation màn Import.

Sau khảo sát phải ghi rõ:

- file nào chỉ thêm code;
- file nào cần chỉnh;
- file nào tuyệt đối không cần sửa;
- điểm hội tụ pipeline hiện tại nằm ở đâu.

---

## 21. API test trước khi nối UI

Trước khi làm gallery đầy đủ, Native cần có một debug harness hoặc test gọi:

### Inspect

```swift
inspectGoogleDriveLink(url)
```

Kiểm tra:

- link hợp lệ;
- metadata;
- pagination;
- thumbnail URL;
- permission error;
- inspection expiry.

### Create session

```swift
createGoogleDriveImportSession(
    inspectionId,
    selectedItemIds,
    mode
)
```

Kiểm tra:

- nhận sessionId;
- nhận native token;
- poll status;
- ready;
- manifest;
- download một asset;
- checksum.

Chỉ sau khi API flow chạy được mới hoàn thiện UI.

---

## 22. Test không regression QR

Bắt buộc test:

### QR case 1

```text
Máy tính upload 2 ảnh
→ QR
→ Native scan
→ nhận đủ 2 ảnh
```

### QR case 2

```text
QR hết hạn
→ báo lỗi đúng
```

### QR case 3

```text
claim một lần
→ không claim lại
```

### QR case 4

```text
download bị gián đoạn
→ Range/resume
```

### QR case 5

```text
completed
→ server xóa asset
```

Không merge nếu bất kỳ case QR cũ nào bị regression.

---

## 23. Test luồng Drive Link

### Case 1 — Link nhỏ

```text
10 ảnh
→ inspect
→ chọn 2
→ backend chỉ chuẩn bị 2
→ Native import 2
```

### Case 2 — Folder 1.000 ảnh

```text
inspect pagination
→ chọn 30
→ backend chỉ tải 30 original
→ Native nhận 30
```

### Case 3 — Một file lỗi

```text
30 selected
→ 1 backend failed
→ Native nhận 29
→ UI hiển thị 1 lỗi
```

### Case 4 — Keep original

- HEIC.
- JPEG.
- PNG.

### Case 5 — Optimized

- JPEG lớn.
- kiểm max 3000 px.
- checksum đúng output.

### Case 6 — App restart

```text
backend đang preparing
→ kill app
→ mở lại
→ resume status
→ ready
→ import
```

### Case 7 — Cancel

```text
backend đang tải
→ user cancel
→ server cleanup
→ Native dọn token/state
```

---

## 24. Error UX

Các lỗi cần phân biệt:

```text
Link không hợp lệ
Không thể truy cập link
Không tìm thấy ảnh
Inspection đã hết hạn
Ảnh không thể tải
Server đang bận
Phiên đã hết hạn
Không đủ dung lượng trên iPhone
Không thể lưu vào Photos
Mất kết nối
```

Không hiển thị error code kỹ thuật trực tiếp cho user.

Giữ error code trong debug log đã redaction.

---

## 25. Logging và privacy

Không log:

- link đầy đủ nếu có resource key;
- thumbnail signed URL;
- native token;
- Google credential;
- tên file vào analytics ngoài nếu không cần;
- GPS EXIF.

Có thể log:

- session ID;
- inspection ID rút gọn;
- số item;
- selected count;
- ready count;
- failed count;
- duration;
- error code.

---

## 26. Sprint triển khai Native

### Sprint 1 — API client và state

- Inspect models.
- API inspect/pagination.
- Create session API.
- Native token storage.
- Poll status.
- Debug test không UI hoàn chỉnh.

### Sprint 2 — UI dán link và gallery

- Entry mới.
- Link input.
- Gallery.
- Pagination.
- Selection.
- Mode.
- Error states.

### Sprint 3 — Hội tụ pipeline import hiện có

- Khi ready, gọi coordinator cũ.
- Không duplicate downloader.
- Recovery.
- Cancel.
- Partial failure.

### Sprint 4 — Regression và thiết bị thật

- QR cũ.
- Drive link mới.
- Batch lớn.
- Network.
- Background.
- Storage.
- Photos.
- Cleanup.

---

## 27. Tiêu chí nghiệm thu

Tính năng hoàn thành khi:

1. Luồng QR từ máy tính vẫn hoạt động nguyên trạng.
2. Native có entry mới để dán Google Drive Share Link.
3. Native gọi backend inspect, không gọi Google trực tiếp.
4. Native hiển thị metadata và thumbnail.
5. Native phân trang folder lớn.
6. User chọn được ảnh.
7. Chỉ item đã chọn được gửi tạo session.
8. Backend chuẩn bị ảnh.
9. Native theo dõi trạng thái.
10. Không cần QR cho session do Native tạo.
11. Khi ready, dùng pipeline import hiện có.
12. HTTP Range và SHA-256 vẫn hoạt động.
13. Photos và SwiftData commit đúng.
14. App restart có thể phục hồi session.
15. Cancel dọn server và local state.
16. Không có Google SDK/API key/token trong Native.
17. Không duplicate downloader hoặc saver.
18. Không regression luồng QR.

---

## 28. Chỉ dẫn cuối cho Codex

Không tiếp tục triển khai theo hướng:

```text
Document Picker
Files Provider
Local File Import
Google Drive trong Files
```

Không thay thế luồng QR.

Không viết lại Nizi Move import pipeline.

Yêu cầu chính xác là:

```text
Luồng cũ:
Máy tính → QR → Native import

Luồng mới:
Native dán Google Drive Share Link
→ Nizi Move backend xử lý
→ Native nhận session
→ pipeline import hiện có
```

Hai luồng phải độc lập ở phần khởi tạo và dùng chung toàn bộ phần nhận ảnh sau khi đã có `sessionId` và `nativeAccessToken`.
