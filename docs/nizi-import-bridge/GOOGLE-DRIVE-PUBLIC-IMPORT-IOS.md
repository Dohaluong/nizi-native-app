# Nizi Native — Nhập ảnh từ Google Drive Share Link không cần đăng nhập

## 1. Bối cảnh

Nizi Native đã có hoặc đang triển khai luồng **Nizi Move Import**:

```text
Quét QR
→ nhận manifest
→ tải từng asset
→ kiểm tra file
→ tối ưu nếu cần
→ lưu vào Apple Photos
→ persist PHAsset.localIdentifier
→ index vào Nizi
→ chạy Event/Memory/Trip theo batch
```

Chức năng mới cho phép người dùng dán một Google Drive Share Link ngay trong app và nhập ảnh vào Nizi mà **không đăng nhập Google**.

Phạm vi MVP chỉ hỗ trợ file hoặc thư mục được chia sẻ ở chế độ:

```text
Bất kỳ ai có đường liên kết (Anyone with the link)
Quyền: Người xem (Viewer)
```

Link `Restricted`, link chỉ chia sẻ cho một số tài khoản hoặc Google Workspace chặn chia sẻ công khai không thuộc phạm vi MVP. Không xây cơ chế vượt quyền và không âm thầm chuyển sang OAuth.

## 2. Mục tiêu kiến trúc

Google Drive phải được triển khai như **một Import Source mới**, không phải một hệ thống import độc lập.

```text
Nizi Move QR Source ─────┐
                        ├── PhotoImportCoordinator dùng chung
Google Drive Source ─────┘
                              ├── download
                              ├── verify
                              ├── optimize
                              ├── save Photos
                              ├── persist localIdentifier
                              ├── index metadata
                              └── Event/Memory/Trip
```

Phần Google Drive chỉ chịu trách nhiệm:

1. Nhận và kiểm tra share link.
2. Tách `fileId`, `folderId` và `resourceKey`.
3. Đọc metadata và danh sách ảnh.
4. Cung cấp thumbnail/preview.
5. Download file được chọn.

Mọi bước từ file tạm trở đi phải tái sử dụng kinh nghiệm và code của Nizi Move.

## 3. Khảo sát bắt buộc trước khi sửa

Trước khi triển khai, hãy đọc và khảo sát đầy đủ:

- Tài liệu `NATIVE-IOS-QR-INTEGRATION.md` của Nizi Move.
- Các model Import Session/Import Asset đã có.
- QR import coordinator/API client.
- Download manager và background `URLSession`.
- Cơ chế download tuần tự hoặc giới hạn concurrency.
- Checksum verifier.
- Image optimization pipeline 3000 px/JPEG.
- PhotoKit writer và cách lấy `PHAsset.localIdentifier`.
- Persistence/resume/crash recovery.
- Metadata indexer.
- Incremental Event/Memory/Trip pipeline.
- UI progress, pause, retry và cancel hiện có.

Sau khảo sát, báo cáo:

1. Thành phần nào có thể tái sử dụng nguyên trạng.
2. Thành phần nào cần trừu tượng hóa để hỗ trợ nhiều nguồn.
3. Thành phần nào thực sự phải viết mới cho Google Drive.
4. Có logic trùng lặp nào giữa Nizi Move và pipeline ảnh hiện tại hay không.

Không sửa code trước khi hoàn thành khảo sát. Không copy nguyên Nizi Move thành một module Google Drive thứ hai.

## 4. Quyết định sản phẩm

### 4.1. Không Google Sign-In

MVP không dùng:

- Google Sign-In.
- OAuth consent screen.
- Refresh token.
- Service Account.
- Client secret nhúng trong app.

Chỉ dùng Google Drive API cho dữ liệu công khai bằng một API key bị giới hạn.

### 4.2. Không đi qua storage của Nizi Move

Ảnh phải tải trực tiếp:

```text
Google Drive → iPhone → Apple Photos
```

Không thực hiện:

```text
Google Drive → VPS Nizi Move → iPhone
```

Không tạo QR, Import Session trên web hoặc bản sao ảnh trên VPS.

### 4.3. Giới hạn bắt buộc

Nếu link không công khai, hiển thị:

```text
Nizi không thể truy cập liên kết này.

Trên Google Drive, hãy chọn:
Chia sẻ → Bất kỳ ai có đường liên kết → Người xem
```

Không yêu cầu đăng nhập trong MVP.

## 5. Google Cloud và API key

Cần tạo một Google Cloud project cho Nizi:

1. Enable Google Drive API.
2. Tạo API key.
3. Application restriction: iOS apps.
4. Giới hạn theo Bundle Identifier chính xác của Nizi.
5. API restriction: chỉ Google Drive API.
6. Đặt quota hợp lý và theo dõi lỗi/quota.

API key mobile không phải secret tuyệt đối. Không coi việc obfuscate key là cơ chế bảo mật chính. Bắt buộc dùng application restriction và API restriction.

Không commit key trực tiếp vào source. Đặt qua build configuration/`.xcconfig` không được commit, hoặc cơ chế secrets hiện có của dự án. Bản mẫu chỉ chứa placeholder.

## 6. Điểm truy cập trong giao diện

Màn nguồn nhập:

```text
Nhập ảnh
├── Từ máy tính — Nizi Move
└── Từ Google Drive
```

Màn Google Drive:

```text
Nhập ảnh từ Google Drive

[ Dán liên kết file hoặc thư mục Google Drive ]

[ Tiếp tục ]
```

Giải thích ngắn:

```text
Liên kết cần được đặt thành “Bất kỳ ai có đường liên kết — Người xem”.
Nizi chỉ đọc những ảnh bạn chọn.
```

Hỗ trợ paste từ clipboard nhưng không tự đọc clipboard khi người dùng chưa thao tác.

## 7. Các dạng URL cần hỗ trợ

Tối thiểu:

```text
https://drive.google.com/drive/folders/{folderId}
https://drive.google.com/file/d/{fileId}/view
https://drive.google.com/open?id={fileId}
```

Có thể có:

```text
?resourcekey={resourceKey}
&resourcekey={resourceKey}
```

Model:

```swift
struct GoogleDriveShareReference: Sendable {
    enum ItemType: Sendable {
        case file
        case folder
        case unknown
    }

    let itemId: String
    let resourceKey: String?
    let expectedType: ItemType
}
```

Validator:

- Chỉ chấp nhận HTTPS.
- Host chính xác thuộc allowlist Google Drive đã định nghĩa.
- Không chấp nhận URL tùy ý.
- Không thực hiện request đến host do người dùng tự cung cấp.
- Kiểm tra format `itemId` và `resourceKey`.
- Không log toàn bộ link nếu có resource key.

## 8. Resource key

Google có thể yêu cầu `resourceKey` cho file/folder được chia sẻ bằng link.

Khi có resource key, request phải gửi:

```http
X-Goog-Drive-Resource-Keys: {fileId}/{resourceKey}
```

Với nhiều resource trong một request, làm theo định dạng chính thức của Google Drive API.

Phải giữ resource key cho:

- Folder gốc.
- Folder con.
- File ảnh.
- Shortcut target nếu hỗ trợ shortcut.

Không lưu resource key vào analytics hoặc log production.

## 9. Google Drive API client

Tạo `GoogleDrivePublicAPIClient` riêng, nhưng tái sử dụng network foundation/error mapping hiện có nếu phù hợp.

Trách nhiệm:

```swift
protocol GoogleDrivePublicAPIClientProtocol: Sendable {
    func getItem(_ reference: GoogleDriveShareReference) async throws -> GoogleDriveItem
    func listChildren(folder: GoogleDriveItem, pageToken: String?) async throws -> GoogleDrivePage
    func downloadRequest(for item: GoogleDriveItem) throws -> URLRequest
}
```

Không đưa logic lưu Photos, resize hoặc Event/Memory vào API client.

## 10. Đọc metadata file/folder

Request:

```http
GET https://www.googleapis.com/drive/v3/files/{itemId}
    ?key={restrictedAPIKey}
    &supportsAllDrives=true
    &fields=id,name,mimeType,size,resourceKey,thumbnailLink,createdTime,modifiedTime,md5Checksum,imageMediaMetadata,shortcutDetails,parents
```

Kiểm tra response:

- `id` khớp item cần đọc.
- Xác định file hay folder bằng `mimeType`.
- Không tin filename để tạo đường dẫn local.
- Dùng ID nội bộ để đặt tên file tạm.

## 11. Đọc folder

Query:

```text
'{folderId}' in parents and trashed = false
```

Fields:

```text
nextPageToken,
files(
  id,
  name,
  mimeType,
  size,
  resourceKey,
  thumbnailLink,
  createdTime,
  modifiedTime,
  md5Checksum,
  imageMediaMetadata,
  shortcutDetails,
  parents
)
```

Yêu cầu:

- `pageSize` tối đa 1000.
- Lặp đến khi `nextPageToken == nil`.
- Không giả định thứ tự response.
- Sắp xếp hiển thị theo ngày chụp nếu có, sau đó theo tên.
- Có tùy chọn `Bao gồm thư mục con`.
- Duyệt folder con theo queue, không đệ quy call stack không giới hạn.
- Chống vòng lặp bằng `visitedFolderIds`.
- Giới hạn số folder/file theo cấu hình.
- Cho phép hủy quá trình đọc folder.

Giới hạn khởi đầu đề xuất:

```text
Tối đa 10.000 item được duyệt
Tối đa 5.000 ảnh trong một lần import
```

Nếu vượt giới hạn, báo rõ và yêu cầu người dùng chọn folder nhỏ hơn.

## 12. Định dạng hỗ trợ

MVP ưu tiên:

```text
image/jpeg
image/png
image/heic
image/heif
image/tiff
```

Không nhập:

- Google Docs.
- Google Sheets.
- Google Slides.
- PDF.
- Archive.
- File executable.
- File không phải ảnh.

RAW, GIF động, video và Live Photo phải được đánh dấu chưa hỗ trợ nếu pipeline Nizi Move chưa hỗ trợ an toàn.

## 13. Shortcut

Google Drive shortcut không phải nội dung ảnh.

MVP có hai lựa chọn:

1. Bỏ qua shortcut và báo số lượng đã bỏ qua; hoặc
2. Resolve `shortcutDetails.targetId`, `targetMimeType`, `targetResourceKey` nếu pipeline hỗ trợ chắc chắn.

Không được tải nội dung shortcut như một file ảnh. Nếu triển khai resolve, phải chống vòng lặp và quyền target không công khai.

## 14. Thumbnail và màn chọn ảnh

Màn hình cần có:

- Thumbnail grid/masonry tái sử dụng component hiện có nếu phù hợp.
- Virtualization/lazy loading.
- Không giữ hàng nghìn bitmap trong RAM.
- Chọn/bỏ chọn từng ảnh.
- Chọn tất cả/bỏ chọn tất cả.
- Nhóm theo folder hoặc thời gian.
- Hiển thị filename, ngày và dung lượng khi cần.
- Hiển thị số ảnh và tổng dung lượng được chọn.

`thumbnailLink` có thể ngắn hạn hoặc cần quyền. Nếu thumbnail không tải được:

- Hiển thị placeholder.
- Không coi asset là lỗi import.
- Không tải file gốc chỉ để tạo thumbnail cho hàng nghìn ảnh trước khi người dùng chọn, trừ khi có chiến lược cache/giới hạn rõ ràng.

## 15. Chọn chất lượng

Tái sử dụng chính xác UX và config của Nizi Move:

```text
Tối ưu dung lượng — Khuyên dùng
Giữ nguyên ảnh gốc
```

Preset cân bằng:

```text
Cạnh dài tối đa: 3000 px
JPEG quality: 85%
Không upscale
Giữ tỷ lệ
```

Khác biệt cần giải thích:

```text
Ảnh Google Drive phải được tải về iPhone trước khi tối ưu.
Tối ưu giúp giảm dung lượng Photos/iCloud, nhưng không giảm dung lượng tải từ Drive.
```

## 16. Adapter vào Import Coordinator dùng chung

Định nghĩa abstraction ở mức tối thiểu cần thiết, ví dụ:

```swift
protocol PhotoImportSource: Sendable {
    var sourceKind: PhotoImportSourceKind { get }

    func loadAssets() async throws -> [PhotoImportAsset]
    func makeDownloadRequest(for asset: PhotoImportAsset) async throws -> URLRequest
    func acknowledgeImported(_ asset: PhotoImportAsset) async throws
    func acknowledgeFailed(_ asset: PhotoImportAsset, reason: String) async
}
```

Implementations:

```text
NiziMoveImportSource
GoogleDrivePublicImportSource
```

Đối với Google Drive:

- `acknowledgeImported` chỉ cập nhật local state, không gọi server Nizi Move.
- Không có claim token/session completed.
- Access qua API key giới hạn.

Không ép hai nguồn giống nhau ở những điểm bản chất khác nhau. Chỉ chia sẻ pipeline từ download result trở đi.

## 17. Model asset dùng chung

Map Drive item sang model import chung:

```swift
struct PhotoImportAsset: Sendable, Identifiable {
    let id: String
    let sourceKind: PhotoImportSourceKind
    let sourceAssetId: String
    let originalFilename: String
    let mimeType: String
    let byteSize: Int64?
    let capturedAt: Date?
    let latitude: Double?
    let longitude: Double?
    let checksum: ImportChecksum?
    let relativePath: String?
    let sourceMetadata: SourceMetadata
}
```

Drive source metadata tối thiểu:

```text
driveFileId
resourceKey reference an toàn
modifiedTime
md5Checksum
parent/folder path
```

Không đặt Google-specific fields vào toàn bộ domain model nếu có thể bọc trong source metadata.

## 18. Download

Tải file:

```http
GET https://www.googleapis.com/drive/v3/files/{fileId}
    ?alt=media
    &supportsAllDrives=true
    &key={restrictedAPIKey}
```

Thêm resource-key header khi cần.

Tái sử dụng download engine của Nizi Move:

- `URLSessionDownloadTask`.
- Background session nếu đã có.
- Tải tuần tự mặc định.
- Tối đa hai asset song song.
- Retry riêng từng file.
- Persist checkpoint.
- Không dùng `Data(contentsOf:)` cho file lớn.
- Không giữ toàn batch trong thư mục tạm.

Quy trình từng ảnh:

```text
download
→ verify
→ optimize hoặc giữ nguyên
→ save Photos
→ persist localIdentifier
→ index
→ xóa temp
→ asset tiếp theo
```

## 19. Verify và chống trùng

Nếu Drive cung cấp `md5Checksum`, dùng để kiểm tra file tải về khi phù hợp.

Ngoài ra:

- Có thể tính SHA-256 local theo streaming nếu pipeline dùng chung yêu cầu.
- Không đưa toàn file vào RAM.
- Persist mapping trước khi chuyển asset tiếp theo.

Mapping chống trùng:

```text
sourceKind = googleDrivePublic
driveFileId
modifiedTime
md5Checksum
phAssetLocalIdentifier
```

Nếu cùng `driveFileId + modifiedTime/checksum` đã có mapping và PHAsset còn tồn tại:

- Không download lại.
- Không lưu Photos lần nữa.
- Cho phép người dùng chọn nhập lại rõ ràng nếu thực sự muốn.

## 20. Metadata ảnh

Không dùng `createdTime` của Drive làm ngày chụp mặc định nếu file chứa EXIF.

Thứ tự ưu tiên:

1. EXIF `DateTimeOriginal` từ file đã tải.
2. `imageMediaMetadata.time` nếu hợp lệ.
3. Drive `createdTime`.
4. `modifiedTime` chỉ là fallback cuối.

GPS:

1. EXIF GPS trong file.
2. Drive `imageMediaMetadata.location`.
3. Không có thì để trống.

Nếu tối ưu JPEG, metadata quan trọng phải được giữ hoặc truyền riêng đến PhotoKit writer:

- `creationDate`.
- `location`.
- orientation.
- filename mapping.

Không dùng thời điểm download/import làm ngày chụp.

## 21. Tối ưu ảnh

Tái sử dụng optimizer đã làm cho Nizi Move. Không viết lại một Canvas-equivalent bằng UIKit nếu pipeline native đã có ImageIO/Core Image.

Yêu cầu:

- Downsample theo file URL.
- Không decode nhiều ảnh full-resolution cùng lúc.
- Không upscale.
- Tôn trọng orientation.
- JPEG 85% cho preset 3000 px.
- HEIC có thể giữ nguyên khi chọn ảnh gốc.
- PNG có alpha không tự chuyển JPEG nếu làm mất dữ liệu ngoài ý muốn.
- Một ảnh tối ưu lỗi không làm hỏng toàn batch.
- Cho phép fallback giữ nguyên hoặc bỏ qua.

## 22. Lưu Apple Photos

Tái sử dụng PhotoKit writer của Nizi Move:

```text
file URL
→ PHPhotoLibrary.performChanges
→ PHAssetChangeRequest.creationRequestForAssetFromImage
→ set creationDate/location
→ placeholder localIdentifier
→ persist mapping
```

Thứ tự an toàn:

```text
download thành công
→ verify
→ Photos lưu thành công
→ persist localIdentifier
→ index/xếp hàng index
→ xóa file tạm
```

Nếu app crash sau khi Photos lưu nhưng trước khi xóa file tạm, khi mở lại phải nhận biết mapping và không tạo bản sao.

## 23. Persistence và resume

Tái sử dụng model/state machine của Nizi Move, bổ sung source kind và Drive metadata.

Session local:

```text
preparing
ready
importing
paused
partiallyCompleted
processingLibrary
completed
failed
cancelled
```

Asset:

```text
pending
downloading
downloaded
verified
optimizing
savingToPhotos
savedToPhotos
indexed
completed
failed
skipped
```

Khi app mở lại:

1. Tìm session Drive chưa hoàn thành.
2. Không đọc lại toàn folder nếu manifest local vẫn hợp lệ.
3. Không download asset đã có localIdentifier.
4. Tiếp tục asset còn thiếu.
5. Nếu share link hết quyền, giữ kết quả đã nhập và báo phần còn thiếu.

## 24. Event, Memory và Trip

Không tạo Event/Memory/Trip sau từng ảnh.

Trong khi import:

- Lưu Photos.
- Persist local identifier.
- Index metadata cần thiết.
- Gom danh sách asset mới.

Sau batch:

```text
incremental index
→ Event clustering
→ merge Event hiện có
→ Trip detection/update
→ Memory discovery/candidate
→ cập nhật UI
```

Không coi toàn bộ Drive folder là một Event hoặc Trip. Folder path chỉ là tín hiệu bổ sung.

Không full scan 100.000 ảnh nếu incremental pipeline đã có hoặc có thể bổ sung adapter hợp lý.

## 25. Progress UI

Các bước:

```text
Đang đọc thư mục Drive
Đang chuẩn bị danh sách ảnh
Đang tải 28/486
Đang tối ưu ảnh
Đang lưu vào Photos
Đang sắp xếp kỷ niệm
```

Hiển thị:

- Số ảnh hoàn thành/tổng.
- Dung lượng đã tải/tổng nếu biết.
- Ảnh lỗi.
- Trạng thái mạng.
- Pause/resume/cancel.

Không hiển thị API key, resource key hoặc Drive ID trong production UI.

## 26. Kết quả

Ví dụ:

```text
Đã nhập ảnh từ Google Drive

482 ảnh đã lưu vào Photos
3 ảnh không thể tải
1 ảnh bị bỏ qua

Nizi đang sắp xếp những kỷ niệm mới.
```

CTA:

```text
Xem ảnh vừa nhập
Xem kỷ niệm mới
Thử lại ảnh lỗi
```

## 27. Error mapping

Tối thiểu:

```text
INVALID_DRIVE_LINK
RESOURCE_KEY_REQUIRED
PUBLIC_ACCESS_REQUIRED
ITEM_NOT_FOUND
FOLDER_TOO_LARGE
UNSUPPORTED_FILE_TYPE
DRIVE_QUOTA_EXCEEDED
RATE_LIMITED
DOWNLOAD_FAILED
CHECKSUM_MISMATCH
INSUFFICIENT_STORAGE
PHOTO_PERMISSION_DENIED
PHOTO_SAVE_FAILED
```

Thông báo người dùng phải dễ hiểu, không hiện raw Google API response.

Xử lý HTTP:

- 400: link/request không hợp lệ.
- 401/403: không công khai, thiếu resource key, key restriction hoặc quota.
- 404: file không tồn tại/không truy cập được.
- 429: rate limit; retry có backoff.
- 5xx: lỗi tạm thời; retry có giới hạn.

Không retry vô hạn.

## 28. Bảo mật

- Chỉ HTTPS.
- Allowlist host Google API.
- Không tải URL tùy ý từ response nếu chưa validate.
- Không log API key/resource key/link đầy đủ.
- Không nhúng client secret/service-account credential.
- API key phải bị giới hạn theo iOS app và Drive API.
- Không expose key trong analytics/crash report.
- Filename server không được dùng trực tiếp làm path.
- Xóa temp sau import.
- Không thực thi hoặc mở file như code.
- Validate MIME, magic bytes và checksum khi phù hợp.

## 29. Kiểm thử bắt buộc

### Link parsing

1. Folder link hợp lệ.
2. File link hợp lệ.
3. Link có resource key.
4. Link HTTP.
5. Link sai host.
6. Link thiếu ID.
7. Link Restricted.

### Drive listing

8. Folder rỗng.
9. Folder có ảnh và file khác.
10. Folder nhiều page.
11. Folder con.
12. Vòng lặp qua shortcut.
13. Folder vượt giới hạn.
14. Resource key bắt buộc.

### Download/import

15. JPEG.
16. PNG.
17. HEIC.
18. Ảnh 50–250 MB.
19. Download gián đoạn.
20. Rate limit/quota.
21. Checksum sai.
22. App đóng giữa chừng.
23. Resume không tạo ảnh trùng.

### Optimization/Photos

24. Giữ nguyên ảnh gốc.
25. Tối ưu 3000 px/JPEG 85%.
26. Không upscale.
27. Giữ orientation.
28. Giữ ngày chụp.
29. Giữ GPS.
30. Persist localIdentifier.

### Nizi pipeline

31. Tái sử dụng Import Coordinator.
32. Không có download engine thứ hai.
33. Không có PhotoKit writer thứ hai.
34. Không chạy discovery sau từng ảnh.
35. Incremental Event/Trip/Memory hoạt động.
36. Drive asset được merge với Event đã có.

## 30. Thứ tự triển khai

### Sprint 1 — Drive source

- Link parser.
- API key configuration.
- `files.get`.
- Folder listing và pagination.
- Resource key.
- Lọc định dạng ảnh.
- UI danh sách/chọn ảnh cơ bản.

### Sprint 2 — Adapter vào import dùng chung

- `GoogleDrivePublicImportSource`.
- Map sang `PhotoImportAsset`.
- Download bằng engine Nizi Move.
- Resume/checksum.
- Save Photos và localIdentifier.

### Sprint 3 — Optimization và Discovery

- Giữ nguyên/Tối ưu dung lượng.
- Metadata preservation.
- Incremental Event/Memory/Trip.
- Kết quả import.

### Sprint 4 — Độ bền và UX

- Folder lớn.
- Pause/resume/cancel.
- Retry chọn lọc.
- Error messages.
- Quota/rate limiting.
- Performance/memory tests.

## 31. Tiêu chí hoàn thành

Chức năng chỉ được coi là hoàn thành khi:

- Không yêu cầu Google Sign-In.
- Chỉ nhập link public đúng quyền.
- API key được giới hạn đúng.
- Hỗ trợ file/folder và resource key.
- Không proxy ảnh qua Nizi VPS.
- Không copy pipeline Nizi Move.
- Download, optimize, PhotoKit, persistence và Discovery được tái sử dụng.
- Có resume và chống trùng.
- Không giữ toàn batch trong RAM/temp.
- Metadata ngày/GPS được giữ.
- Có test cho link Restricted và folder nhiều page.

## 32. Yêu cầu báo cáo sau triển khai

Báo cáo:

1. Các file đã đọc để khảo sát Nizi Move.
2. Thành phần được tái sử dụng nguyên trạng.
3. Thành phần được refactor thành abstraction dùng chung.
4. Thành phần viết mới riêng cho Drive.
5. Cấu hình Google Cloud cần thực hiện.
6. Cách giữ resource key an toàn.
7. Cách resume và chống trùng.
8. Cách giữ metadata.
9. Cách gọi incremental Event/Memory/Trip.
10. Test đã chạy và kết quả.
11. Giới hạn còn tồn tại.

Không tự mở rộng sang Google Sign-In, Google Photos API, video hoặc server proxy trong nhiệm vụ này.

## 33. Tài liệu chính thức tham khảo

- Google Drive API — Search files and folders: <https://developers.google.com/workspace/drive/api/guides/search-files>
- Google Drive API — Resource keys: <https://developers.google.com/workspace/drive/api/guides/resource-keys>
- Google Drive API — `files.get`: <https://developers.google.com/workspace/drive/api/reference/rest/v3/files/get>
- Google Drive API — `files.list`: <https://developers.google.com/workspace/drive/api/reference/rest/v3/files/list>
- Google Drive API — File resource: <https://developers.google.com/workspace/drive/api/reference/rest/v3/files>
