# IMPLEMENTATION PLAN — LOCAL FILE PROVIDER IMAGE IMPORT

**Dự án:** Nizi Native iOS  
**Nguồn yêu cầu:** `SURVEY-IOS-FILE-PROVIDER-IMPORT.md`  
**Trạng thái:** Sẵn sàng triển khai MVP  
**Quyết định kiến trúc:** **Document Picker đủ cho MVP**  
**Ngày:** 2026-08-04

---

## 1. Mục tiêu

Triển khai một luồng import ảnh cục bộ trong Nizi Native, cho phép người dùng chọn nhiều ảnh từ giao diện Files của iOS.

Các File Provider đã được cài và cấu hình trên thiết bị sẽ tự xuất hiện trong Files, bao gồm:

- Google Drive.
- iCloud Drive.
- OneDrive.
- Dropbox.
- Các File Provider tương thích khác.

Luồng mới không sử dụng backend, Google Drive API, Google OAuth, API key hoặc Nizi Move.

Luồng mục tiêu:

```text
Files / UIDocumentPicker
→ nhận bản copy vào sandbox
→ tạo Local Import Session bền vững
→ preflight dung lượng và quota
→ validate file bằng ImageIO
→ tạo thumbnail
→ review và chọn ảnh
→ giữ nguyên hoặc tối ưu từng ảnh
→ lưu vào Photos
→ index SwiftData
→ completed
→ dọn file tạm
```

---

## 2. Nguyên tắc bắt buộc

### 2.1. Đây là local import, không phải Nizi Move

Không sử dụng hoặc ghép luồng này với:

- QR.
- Pairing code.
- Nizi Move API.
- Manifest server.
- Owner token.
- Native access token.
- Download URL từ server.
- Server acknowledgement.
- Google Drive share link.
- Google OAuth credential.

Có thể tái sử dụng helper kỹ thuật từ Nizi Move sau khi tách phụ thuộc, nhưng không tái sử dụng nguyên model hoặc protocol có thông tin server.

### 2.2. Chọn file bằng Document Picker

Sử dụng:

```swift
UIDocumentPickerViewController(
    forOpeningContentTypes: [.image],
    asCopy: true
)
```

và:

```swift
picker.allowsMultipleSelection = true
```

Có thể bọc UIKit picker để sử dụng trong SwiftUI.

MVP chọn `asCopy: true` để Nizi sở hữu bản copy trong sandbox ngay sau callback. Không lưu URL ngoài sandbox để sử dụng lại trong lần mở app sau.

### 2.3. Không tải toàn bộ ảnh vào RAM

Không được dùng cho batch ảnh:

```swift
Data(contentsOf:)
UIImage(contentsOfFile:)
```

theo cách khiến nhiều ảnh gốc hoặc nhiều bitmap full-resolution cùng tồn tại trong RAM.

Phải:

- Đọc file theo URL.
- Dùng ImageIO để lấy metadata và tạo thumbnail.
- Giới hạn số tác vụ đồng thời.
- Chỉ decode hoặc resize tối đa một ảnh tại một thời điểm trong MVP.
- Không giữ toàn bộ thumbnail đã decode trong memory cache không giới hạn.

### 2.4. Commit đúng thứ tự

Một ảnh chỉ được đánh dấu `completed` sau khi:

1. File đầu ra đã sẵn sàng.
2. `PHPhotoLibrary.performChanges` thành công.
3. SwiftData index thành công.
4. Trạng thái session/asset được persist.

Sau đó mới được xóa file tạm.

Không được báo thành công trước khi Photos và index hoàn tất.

---

## 3. Phạm vi MVP

### 3.1. Có trong MVP

- Nút nhập ảnh từ Files.
- Mở `UIDocumentPickerViewController`.
- Chọn nhiều ảnh.
- Nhận bản copy bằng `asCopy: true`.
- Tối đa 300 ảnh mỗi session.
- Quota tổng cấu hình ban đầu 5 GB.
- Tạo Local Import Session bền vững.
- Copy/move file về:
  `Application Support/ImportSessions/<sessionId>/source/`.
- Sanitize filename.
- Chống trùng tên file.
- Preflight dung lượng trống.
- Kiểm lại dung lượng trong quá trình copy và xử lý.
- Đọc metadata bằng `URLResourceValues` và ImageIO.
- Validate ảnh bằng `CGImageSourceCreateWithURL`.
- Tạo thumbnail bằng ImageIO downsampling.
- Review grid lazy-loading.
- Chọn/bỏ chọn từng ảnh.
- Chọn tất cả/bỏ chọn tất cả.
- Hiển thị số ảnh và dung lượng thực tế.
- Chế độ giữ nguyên ảnh gốc.
- Chế độ tối ưu dung lượng.
- Lưu ảnh vào Photos.
- Index ảnh vào SwiftData.
- Retry asset lỗi từ bản copy trong sandbox.
- Journal session để phục hồi sau app restart.
- Dọn session hoàn thành, hủy hoặc quá hạn.
- Unit test cho state machine, quota, validation và cleanup.
- Kế hoạch test thiết bị thật 10/100/300 ảnh.

### 3.2. Không có trong MVP

- Google Sign-In.
- Google Drive API.
- Google OAuth.
- API key Google.
- Drive browser do Nizi tự xây.
- Dán Google Drive share link.
- Nizi Move hoặc QR.
- Chọn nguyên folder và import đệ quy.
- Bảo đảm giữ cấu trúc thư mục.
- Generic download progress của File Provider.
- Resume download đang do Google Drive/Dropbox File Provider thực hiện.
- Background guarantee khi provider còn đang chuẩn bị file.
- Security-scoped bookmark lâu dài.
- Đọc trực tiếp external URL sau app restart.
- Xử lý nhiều bitmap full-resolution song song.
- Tự động retry vô hạn.
- Silent conversion HEIC sang JPEG.
- Chuyển PNG có alpha thành JPEG.
- Làm mất animation GIF.

---

## 4. Kiến trúc module

Tạo module mới:

```text
Nizi/Features/LocalFileImport/
├── Domain/
├── Application/
├── Infrastructure/
└── Presentation/
```

### 4.1. Domain

Đề xuất các type:

```text
LocalImportSession
LocalImportAsset
LocalImportSessionStatus
LocalImportAssetStatus
LocalImportMode
LocalImportError
LocalImportQuota
LocalImportMetadata
LocalImportFormat
```

#### Session status tối thiểu

```text
created
copying
reviewing
committing
partiallyCompleted
completed
cancelled
failed
```

Có thể bổ sung `recovering` nếu thực sự cần cho UI.

#### Asset status tối thiểu

```text
pending
copying
validating
ready
selected
processing
saving
indexing
completed
failed
retryable
skipped
```

Không cần expose toàn bộ trạng thái nội bộ ra UI nếu không cần thiết, nhưng journal phải đủ để phục hồi an toàn.

#### LocalImportMode

```swift
enum LocalImportMode {
    case keepOriginal
    case optimized
}
```

Mặc định MVP:

```text
keepOriginal
```

### 4.2. Application

Đề xuất:

```text
LocalFileImportCoordinator
LocalImportSessionRepository
LocalImportAssetProcessor
LocalImportQuotaService
LocalImportRecoveryService
LocalImportCleanupService
```

`LocalFileImportCoordinator` chịu trách nhiệm điều phối:

```text
picker callback
→ session creation
→ copy queue
→ validation
→ thumbnail preparation
→ review
→ commit queue
→ Photos save
→ SwiftData index
→ cleanup
```

Coordinator không giữ bitmap full-resolution trong state.

### 4.3. Infrastructure

Đề xuất:

```text
DocumentPickerAdapter
LocalImportFileStore
LocalImportMetadataReader
LocalImportThumbnailGenerator
LocalImportImageOptimizer
LocalImportPhotoSaver
LocalImportFileHasher
LocalImportDiskMonitor
SwiftDataLocalImportRepository
```

Có thể tách và tái sử dụng code từ:

```text
NiziMovePhotoSaver.swift
```

nhưng helper mới không được phụ thuộc vào:

```text
NiziMoveManifestAsset
NiziMoveAPI
downloadURL
server token
server acknowledgement
```

### 4.4. Presentation

Đề xuất màn hình:

```text
LocalFileImportEntryView
LocalFileImportPickerPresenter
LocalFileImportPreparingView
LocalFileImportReviewView
LocalFileImportProgressView
LocalFileImportResultView
```

Có thể đặt entry mới tại màn import hiện có hoặc tách một màn “Nhập ảnh”.

---

## 5. Document Picker

### 5.1. UIKit wrapper

Tạo wrapper SwiftUI cho `UIDocumentPickerViewController`.

Yêu cầu:

- `forOpeningContentTypes: [.image]`.
- `asCopy: true`.
- `allowsMultipleSelection = true`.
- Delegate chỉ chuyển URL sang coordinator.
- Không tạo thumbnail trong delegate.
- Không đọc `Data` trong delegate.
- Không chạy xử lý ảnh trên main thread.
- Khi user hủy, không tạo session rỗng.

### 5.2. Xử lý security scope phòng thủ

Dù dùng `asCopy: true`, code copy file vẫn phải chịu được trường hợp URL cần security scope.

Mẫu bắt buộc:

```swift
let didAccess = url.startAccessingSecurityScopedResource()
defer {
    if didAccess {
        url.stopAccessingSecurityScopedResource()
    }
}
```

Khi đọc URL ngoài sandbox, sử dụng `NSFileCoordinator`.

Không giữ URL picker thô trong SwiftData hoặc UserDefaults.

### 5.3. Tên file

Khi đưa file vào session:

- Sanitize filename.
- Loại path separator.
- Không cho `..`.
- Không dùng absolute path.
- Giữ extension hợp lệ.
- Nếu trùng tên, tạo tên collision-safe.
- Không ghi đè file đã tồn tại.
- Lưu lại `originalFilename` để hiển thị.

Ví dụ:

```text
IMG_0001.HEIC
IMG_0001-2.HEIC
IMG_0001-3.HEIC
```

---

## 6. Local Import Session và journal

### 6.1. Thư mục session

```text
Application Support/
└── ImportSessions/
    └── <sessionId>/
        ├── source/
        ├── thumbnails/
        ├── output/
        └── journal.json
```

Nếu dự án đã dùng SwiftData cho journal thì có thể persist state trong SwiftData, nhưng file system vẫn phải là nguồn xác nhận file thực tế.

### 6.2. Tạo journal trước khi copy

Thứ tự:

1. Kiểm số URL không vượt 300.
2. Tạo session ID.
3. Tạo session folders.
4. Persist session với trạng thái `created`.
5. Persist danh sách asset `pending`.
6. Chuyển session sang `copying`.
7. Bắt đầu copy.

Không copy file trước rồi mới tạo journal.

### 6.3. Recovery

Khi app khởi động:

- Quét session chưa terminal.
- Đối chiếu journal với file thực tế.
- Không giả định asset đang `copying` đã copy xong.
- File source hợp lệ có thể tiếp tục validate/review.
- Asset thiếu file phải chuyển `retryable` hoặc `failed`.
- Không tự mở lại provider URL.
- Retry chỉ dùng bản copy đã có trong sandbox.
- Session `completed` hoặc `cancelled` cũ được cleanup theo retention policy.

---

## 7. Quota và kiểm tra disk

### 7.1. Giới hạn sản phẩm

Giá trị ban đầu:

```text
maxFilesPerSession = 300
maxSourceBytesPerSession = 5 GB
```

Đây là giới hạn sản phẩm, không phải cam kết mọi iPhone đều nhập được 5 GB.

### 7.2. Preflight

Sử dụng dung lượng khả dụng dành cho important usage.

Trước khi copy, ước lượng:

```text
source bytes
+ worst-case output bytes
+ safety margin
```

Không chỉ dựa vào `fileSize` do provider trả về.

Nếu metadata size thiếu:

- Vẫn cho phép bắt đầu trong giới hạn thận trọng.
- Đếm byte thực tế khi copy.
- Dừng khi vượt quota.

### 7.3. Kiểm tra trong quá trình xử lý

Sau mỗi file hoặc mỗi nhóm nhỏ:

- Kiểm dung lượng thực tế đã copy.
- Kiểm dung lượng trống còn lại.
- Không bắt đầu job mới nếu gần ngưỡng.
- Mark các asset chưa xử lý là `retryable`.
- Hiển thị lỗi rõ ràng.
- Không để app tiếp tục đến mức hệ điều hành kill vì hết disk.

### 7.4. Peak disk

Với `asCopy: true`, có thể cùng tồn tại:

```text
source copy
+ optimized output
+ temporary encoder file
```

Do đó không được giả định 5 GB source chỉ cần 5 GB disk.

Trong chế độ optimized:

- Xử lý tuần tự.
- Sau khi ảnh đã lưu Photos và index thành công, xóa output/source theo retention rule.
- Không giữ output của toàn batch nếu không cần.

---

## 8. Copy queue

### 8.1. Concurrency

Giới hạn ban đầu:

```text
copy concurrency: 2–3
decode/resize concurrency: 1
```

Không dùng task group không giới hạn.

### 8.2. Cách copy

- Dùng file-based copy.
- Không đọc toàn bộ file vào `Data`.
- Ghi nhận số byte thực tế.
- Sau copy, kiểm file tồn tại và size.
- Chỉ chuyển asset sang `validating` khi copy hoàn tất.
- File copy dở phải được nhận biết và cleanup.

### 8.3. Provider error

Lỗi provider có thể xuất hiện trong lúc Files chuẩn bị file hoặc callback/copy.

UI không được hứa có phần trăm chính xác cho quá trình provider tải cloud file.

Thông điệp phù hợp:

```text
Đang chuẩn bị ảnh từ Files…
```

Nếu copy lỗi:

- Ghi lỗi theo asset hoặc selection.
- Cho user chọn lại file.
- Không tự retry vô hạn.
- Không báo completed giả.

---

## 9. Validation và metadata

### 9.1. URLResourceValues

Đọc tối thiểu:

```text
name
fileSize
contentType
creationDate
contentModificationDate
```

Metadata provider chỉ dùng như gợi ý và hiển thị.

### 9.2. ImageIO validation

Dùng:

```text
CGImageSourceCreateWithURL
CGImageSourceCopyPropertiesAtIndex
```

Validate:

- Có thể tạo image source.
- Có ít nhất một image frame khi định dạng yêu cầu.
- Pixel width/height hợp lệ.
- Không vượt pixel limit cấu hình.
- Không corrupt.
- Format thực tế phù hợp với khả năng xử lý.

Không tin riêng:

- Extension.
- MIME.
- UTType từ picker.

### 9.3. Capture date

Lưu riêng:

- EXIF original capture date.
- Provider creation date.
- Provider modification date.

Ưu tiên EXIF capture date khi index ảnh, tương tự Nizi Move hiện tại.

### 9.4. Orientation và GPS

Đọc nếu có:

- Orientation.
- GPS.
- Pixel dimensions.
- UTI/format.
- Frame count với GIF nếu cần test.

Không bắt buộc mọi provider trả đủ metadata.

---

## 10. Thumbnail

Dùng ImageIO downsampling:

```text
CGImageSourceCreateThumbnailAtIndex
```

Yêu cầu:

- Tạo từ file URL.
- Không decode full-resolution nếu chỉ cần thumbnail.
- Max pixel size theo grid.
- Tạo thumbnail ngoài main thread.
- Lưu thumbnail disk cache trong session hoặc cache có giới hạn.
- Lazy-load theo cell.
- Cancel task khi cell rời màn hình nếu có thể.
- Không giữ toàn batch thumbnail dạng `UIImage` trong memory.

Ảnh unsupported/corrupt vẫn xuất hiện trong review dưới dạng placeholder và không thể chọn.

---

## 11. Review UI

### 11.1. Nội dung

Hiển thị:

- Thumbnail.
- Tên file.
- Kích thước pixel nếu có.
- Dung lượng thực tế.
- Format.
- Trạng thái hợp lệ.
- Lỗi nếu không đọc được.
- Trạng thái selected.

### 11.2. Thao tác

- Chọn từng ảnh.
- Bỏ chọn từng ảnh.
- Chọn tất cả ảnh hợp lệ.
- Bỏ chọn tất cả.
- Xem ảnh lớn.
- Hiển thị tổng số ảnh được chọn.
- Hiển thị tổng dung lượng source.
- Chọn `Giữ nguyên`.
- Chọn `Tối ưu dung lượng`.

### 11.3. Mặc định

- `Giữ nguyên` là mặc định của MVP.
- Ảnh hợp lệ được chọn mặc định, trừ khi UX hiện tại có quy tắc khác đã được chứng minh.
- Ảnh corrupt/unsupported không được chọn.

### 11.4. Folder path

Không coi cấu trúc thư mục là contract.

Có thể hiển thị path nếu provider trả được, nhưng:

- Không phụ thuộc vào path để index.
- Không yêu cầu folder recursive import.
- Không coi thiếu relative path là lỗi.

---

## 12. Chế độ giữ nguyên

Khi `keepOriginal`:

- Không resize.
- Không nén.
- Không đổi format.
- Không thay bytes.
- Giữ filename an toàn.
- Giữ EXIF container gốc nếu Photos chấp nhận.
- Validate trước khi lưu.
- Nếu Photos không nhận format, asset failed/retryable theo lỗi thực tế.

Định dạng cần test:

- HEIC.
- JPEG.
- PNG.
- GIF.
- TIFF.
- WebP.

Không tuyên bố support format chỉ dựa trên `UTType.image`.

---

## 13. Chế độ tối ưu

### 13.1. Quy tắc MVP

| Format | Hành vi tối ưu MVP |
|---|---|
| JPEG | JPEG quality khoảng 0.85, cạnh dài tối đa 3000 px, không upscale |
| HEIC | Giữ nguyên trong MVP |
| PNG có alpha | Giữ nguyên |
| GIF | Giữ nguyên để bảo toàn animation |
| TIFF/WebP | Chỉ xử lý theo kết quả test; fallback original nếu phù hợp |

Không silently đổi HEIC thành JPEG.

Không chuyển PNG có alpha sang JPEG.

Không làm mất animation GIF.

### 13.2. JPEG encoder

Khi tối ưu JPEG:

- Correct orientation.
- Max long edge 3000 px.
- Không upscale.
- Quality khoảng 0.85.
- Cố gắng copy metadata đã chọn.
- Test capture date, orientation và GPS.
- Output ghi vào session `output/`.
- Nếu encoder lỗi, fallback original và ghi lại lý do.

### 13.3. Memory

- Resize một ảnh mỗi lần.
- Không giữ source bitmap và output bitmap lâu hơn cần thiết.
- Dùng autorelease pool nếu cần trong vòng lặp lớn.
- Theo dõi memory warning.
- Không chạy encoder trên main thread.

---

## 14. Lưu Photos

Tách PhotoKit saver chung từ logic Nizi Move nếu phù hợp.

Interface mới không được nhận `NiziMoveManifestAsset`.

Đầu vào tối thiểu:

```text
sourceURL
originalFilename
captureDate
metadata cần thiết
```

Điểm commit:

```swift
PHPhotoLibrary.performChanges
```

Chỉ khi `performChanges` thành công mới:

1. Nhận local identifier nếu có.
2. Index SwiftData.
3. Cập nhật asset completed.
4. Cleanup file.

Nếu Photos save lỗi:

- Không completed.
- Không xóa source ngay.
- Chuyển `failed` hoặc `retryable`.
- Lưu error code đã được làm sạch.

Yêu cầu quyền Photos đúng thời điểm người dùng bắt đầu commit, không xin sớm khi app mở.

---

## 15. SwiftData index

Sau khi Photos save thành công:

- Index asset vào model hiện có.
- Ưu tiên dùng PHAsset local identifier để chống double commit.
- Operation phải idempotent.
- Nếu app bị kill sau Photos save nhưng trước index, recovery phải phát hiện và hoàn tất index thay vì lưu trùng ảnh lần nữa nếu có đủ identifier.

Cần khảo sát code hiện tại để xác định model index cụ thể, nhưng không được bỏ qua bước này.

---

## 16. Retry và idempotency

### 16.1. Retry từ sandbox

Retry không được phụ thuộc provider URL sau callback.

Chỉ retry khi file source vẫn còn trong session sandbox.

### 16.2. Các lỗi retryable

Ví dụ:

- Thiếu quyền Photos tạm thời sau khi user có thể cấp lại.
- SwiftData transaction lỗi tạm thời.
- Disk pressure có thể giải quyết sau khi user dọn bộ nhớ.
- Process bị gián đoạn khi source đã copy hoàn chỉnh.

### 16.3. Các lỗi không retry tự động

- File corrupt.
- ImageIO không decode được.
- Format không được Photos hỗ trợ.
- Source file thiếu hoặc copy dở.
- Pixel dimension vượt giới hạn an toàn.

### 16.4. Chống lưu trùng

Journal cần đủ dữ liệu để phân biệt:

```text
chưa lưu Photos
đã lưu Photos nhưng chưa index
đã index nhưng chưa cleanup
completed
```

Không chỉ dùng một boolean `completed`.

---

## 17. Cleanup

### 17.1. Khi completed

Sau Photos + index + persist:

- Xóa output.
- Xóa source theo policy.
- Xóa thumbnail.
- Xóa session folder khi toàn bộ asset terminal và không còn retry.

### 17.2. Khi cancelled

- Dừng job mới.
- Cancel task có thể cancel.
- Không để task tiếp tục ghi state sau cancel.
- Xóa file copy dở.
- Xóa session sau khi các task đã dừng an toàn.

### 17.3. Khi app khởi động

- Cleanup session completed/cancelled quá retention.
- Cleanup orphan temporary file.
- Không xóa session retryable còn trong thời hạn.
- Không xóa file của task đang được recovery xử lý.

---

## 18. UI trạng thái

### 18.1. Preparing

```text
Đang chuẩn bị ảnh từ Files
Đã chuẩn bị 34/100 ảnh
```

Với provider bên thứ ba, không hiển thị phần trăm download cloud giả.

### 18.2. Review

```text
100 ảnh
2,4 GB

[Chọn tất cả] [Bỏ chọn tất cả]

Chế độ:
○ Giữ nguyên
○ Tối ưu dung lượng
```

### 18.3. Commit

```text
Đang lưu ảnh
34/96 ảnh hoàn tất
```

### 18.4. Kết quả

```text
Đã nhập 94 ảnh
2 ảnh cần thử lại
```

Cho phép xem file lỗi và retry các asset phù hợp.

---

## 19. File dự kiến tạo mới

Codex phải khảo sát cấu trúc project thực tế trước khi chốt tên chính xác, nhưng phạm vi dự kiến:

```text
Nizi/Features/LocalFileImport/Domain/LocalImportModels.swift
Nizi/Features/LocalFileImport/Domain/LocalImportErrors.swift
Nizi/Features/LocalFileImport/Application/LocalFileImportCoordinator.swift
Nizi/Features/LocalFileImport/Application/LocalImportRecoveryService.swift
Nizi/Features/LocalFileImport/Application/LocalImportCleanupService.swift
Nizi/Features/LocalFileImport/Infrastructure/DocumentPickerAdapter.swift
Nizi/Features/LocalFileImport/Infrastructure/LocalImportFileStore.swift
Nizi/Features/LocalFileImport/Infrastructure/LocalImportMetadataReader.swift
Nizi/Features/LocalFileImport/Infrastructure/LocalImportThumbnailGenerator.swift
Nizi/Features/LocalFileImport/Infrastructure/LocalImportImageOptimizer.swift
Nizi/Features/LocalFileImport/Infrastructure/LocalImportPhotoSaver.swift
Nizi/Features/LocalFileImport/Infrastructure/LocalImportDiskMonitor.swift
Nizi/Features/LocalFileImport/Infrastructure/SwiftDataLocalImportRepository.swift
Nizi/Features/LocalFileImport/Presentation/LocalFileImportEntryView.swift
Nizi/Features/LocalFileImport/Presentation/LocalFileImportPreparingView.swift
Nizi/Features/LocalFileImport/Presentation/LocalFileImportReviewView.swift
Nizi/Features/LocalFileImport/Presentation/LocalFileImportProgressView.swift
Nizi/Features/LocalFileImport/Presentation/LocalFileImportResultView.swift
```

Test:

```text
NiziTests/LocalFileImport/LocalImportStateMachineTests.swift
NiziTests/LocalFileImport/LocalImportQuotaTests.swift
NiziTests/LocalFileImport/LocalImportValidationTests.swift
NiziTests/LocalFileImport/LocalImportCleanupTests.swift
NiziTests/LocalFileImport/LocalImportRecoveryTests.swift
```

---

## 20. File dự kiến sửa

Khảo sát và chỉ sửa khi cần:

```text
Nizi/Features/NiziMove/Infrastructure/NiziMovePhotoSaver.swift
Nizi/Features/NiziMove/Presentation/NiziMoveImportView.swift
Nizi/NiziApp.swift
Nizi/ContentView.swift
Nizi.xcodeproj/project.pbxproj
```

Mục tiêu khi sửa `NiziMovePhotoSaver.swift`:

- Tách PhotoKit saver dùng chung.
- Tách EXIF helper dùng chung.
- Giữ nguyên hành vi Nizi Move hiện tại.
- Không làm Nizi Move phụ thuộc LocalFileImport.
- Không gây regression QR import.

Nếu project đang dùng folder reference tự động, không sửa `project.pbxproj` thủ công nếu không cần.

---

## 21. Sprint triển khai

### Sprint 1 — Foundation và Document Picker

Mục tiêu:

- Tạo module.
- Tạo model/state.
- Tạo journal repository.
- Tạo session folder.
- Mở picker.
- Chọn nhiều ảnh.
- Copy file vào sandbox.
- Sanitize filename.
- Quota sơ bộ.
- Cancel.

Nghiệm thu:

- Chọn được nhiều ảnh từ Files.
- Google Drive xuất hiện khi đã cài/cấu hình.
- File được copy vào session.
- App không đọc full file vào RAM.
- Session tồn tại sau app restart.
- Không tạo session khi picker cancel.

### Sprint 2 — Validation, metadata và review

Mục tiêu:

- ImageIO validation.
- Metadata.
- Thumbnail downsampling.
- Lazy review grid.
- Selection.
- Dung lượng thực tế.
- Error per-file.

Nghiệm thu:

- Corrupt file không làm crash.
- Unsupported file có placeholder.
- Thumbnail không decode full batch.
- Chọn tất cả/bỏ chọn tất cả hoạt động.
- Review 300 item vẫn scroll ổn trong test development.

### Sprint 3 — Keep original commit

Mục tiêu:

- PhotoKit saver.
- Quyền Photos.
- SwiftData index.
- State transition.
- Cleanup.
- Retry.
- Recovery.

Nghiệm thu:

- Chỉ completed sau Photos + index.
- App restart không lưu trùng ảnh.
- Asset lỗi giữ source để retry theo policy.
- Completed asset được cleanup.
- Nizi Move không regression.

### Sprint 4 — Optimized mode

Mục tiêu:

- JPEG resize 3000 px.
- JPEG quality khoảng 0.85.
- Metadata copy.
- Format-specific fallback.
- Memory bounded.
- Disk checks.

Nghiệm thu:

- JPEG lớn được resize đúng tỷ lệ.
- JPEG nhỏ không upscale.
- HEIC giữ nguyên.
- PNG alpha giữ nguyên.
- GIF giữ animation.
- Encoder lỗi fallback original.
- Không OOM trong development batch.

### Sprint 5 — Hardening và test thiết bị

Mục tiêu:

- Unit/integration tests.
- Cleanup orphan.
- Metrics nội bộ đã redaction.
- Test device matrix.
- Fix provider-specific issues.

Không release trước khi test thiết bị thật hoàn tất.

---

## 22. Test tự động

### 22.1. State machine

Test:

- Session tạo đúng state.
- Asset transition hợp lệ.
- Không completed trước Photos/index.
- Cancel ngăn state update muộn.
- Recovery từ từng điểm gián đoạn.
- Idempotent commit.

### 22.2. Quota

Test:

- Vượt 300 ảnh.
- Vượt 5 GB metadata.
- Size metadata thiếu.
- Byte thực tế vượt quota.
- Disk reserve không đủ.
- Dừng queue khi gần hết disk.

### 22.3. Validation

Test:

- JPEG hợp lệ.
- HEIC hợp lệ.
- PNG alpha.
- GIF animated.
- TIFF/WebP theo hỗ trợ runtime.
- Extension giả.
- Corrupt header.
- Pixel dimension quá lớn.
- Zero-byte file.

### 22.4. Cleanup

Test:

- Completed session cleanup.
- Cancelled session cleanup.
- File copy dở.
- Orphan output.
- Retryable session không bị xóa sớm.
- Cleanup sau app restart.

### 22.5. Regression Nizi Move

Toàn bộ test Nizi Move hiện có phải tiếp tục pass.

Đặc biệt kiểm tra:

- QR claim.
- Download.
- SHA-256.
- Photos save.
- SwiftData index.
- Server acknowledgement.
- Cleanup.

---

## 23. Test thiết bị thật bắt buộc

Khảo sát chưa có số liệu thiết bị thật. Codex không được tự tuyên bố hoàn thành release chỉ dựa vào simulator hoặc unit test.

Thiết bị:

- Một iPhone cấu hình thấp còn được Nizi hỗ trợ.
- Một iPhone hiện hành.
- iOS deployment target.
- Bản iOS mới nhất Nizi hỗ trợ.

Provider:

- Google Drive.
- iCloud Drive.
- OneDrive.
- Dropbox.

Batch:

- 10 ảnh.
- 100 ảnh.
- 300 ảnh.

Network:

- Wi-Fi tốt.
- Mạng yếu.
- Offline.
- Chuyển Wi-Fi/LTE nếu phù hợp.

Format:

- JPEG.
- HEIC.
- PNG.
- GIF.
- TIFF.
- WebP.
- Corrupt file.

Chế độ:

- Keep original.
- Optimized.

Tình huống:

- File đã local.
- File cloud-only.
- Cancel picker.
- Mất mạng khi provider chuẩn bị file.
- App background.
- Force-close.
- Disk gần đầy.
- Photos permission denied.
- SwiftData failure giả lập nếu có thể.

Ghi nhận:

- Selection-to-callback.
- Copy elapsed.
- Validation elapsed.
- Thumbnail elapsed.
- Commit elapsed.
- Max RSS.
- Memory warning.
- Disk before/max/after cleanup.
- Số selected/completed/failed/cancelled.
- EXIF trước/sau.
- GIF frame count.
- Photos local identifiers.
- Recovery behavior.

Công cụ:

- Instruments Allocations.
- Leaks.
- Memory Graph.
- Time Profiler.
- Xcode memory gauge.
- Device analytics.
- `volumeAvailableCapacityForImportantUsage`.

---

## 24. Logging và privacy

Có thể log:

- Session ID.
- Asset ID.
- Phase.
- Duration.
- Byte count.
- Error code.
- Số file.
- Trạng thái.

Không log:

- Nội dung ảnh.
- File path đầy đủ có thông tin nhạy cảm nếu không cần.
- EXIF GPS.
- Tên file vào analytics bên ngoài.
- Security-scoped URL.
- Provider credential.
- Google token.
- User account identifier của provider.

Metrics phải được redaction.

---

## 25. Rủi ro và release gate

### P0 — OOM hoặc hết disk

Giảm thiểu:

- Bounded queues.
- Journal trước copy.
- Disk reserve.
- Per-batch disk check.
- Decode/resize một ảnh.
- Device test 300 ảnh.

Release gate:

- Không crash/OOM trong test bắt buộc.
- Không mất toàn bộ session khi app bị kill.

### P0 — Completed sai thời điểm

Giảm thiểu:

- Photos commit.
- SwiftData index.
- Persist terminal state.
- Cleanup cuối cùng.

Release gate:

- Test gián đoạn tại từng bước.
- Không báo completed giả.
- Không double import.

### P0 — Security scope/file coordination

Giảm thiểu:

- `defer stopAccessing`.
- `NSFileCoordinator`.
- Copy vào sandbox ngay.

Release gate:

- Không rò scope.
- Không giữ external URL qua restart.

### P1 — Provider khác nhau

Giảm thiểu:

- Test matrix thực tế.
- Không hứa generic progress.
- Copy failure retryable.
- UX thông báo rõ.

### P1 — Mất metadata/animation/transparency

Giảm thiểu:

- Keep original mặc định.
- HEIC/PNG/GIF giữ nguyên.
- Test EXIF.
- Fallback original.

### P1 — 5 GB không phù hợp mọi thiết bị

Giảm thiểu:

- Dynamic quota.
- Disk reserve.
- Thông báo cụ thể.
- Không quảng bá 5 GB như bảo đảm.

---

## 26. Tiêu chí nghiệm thu MVP

MVP được coi là hoàn thành khi:

1. Người dùng mở được Files picker từ Nizi.
2. Có thể chọn nhiều ảnh.
3. Google Drive/iCloud/OneDrive/Dropbox xuất hiện theo File Provider đã cài.
4. Picker sử dụng `asCopy: true`.
5. Không lưu provider URL để dùng lâu dài.
6. Tối đa 300 file được enforce.
7. Quota và disk reserve được kiểm tra.
8. File được copy vào session sandbox.
9. Filename được sanitize và collision-safe.
10. Session journal được persist trước copy.
11. App restart có thể phục hồi session.
12. Validation dùng ImageIO.
13. File corrupt không làm crash.
14. Thumbnail dùng downsampling.
15. Review grid lazy-load.
16. Có selection và thống kê dung lượng.
17. Keep original hoạt động.
18. Optimized JPEG hoạt động đúng quy tắc.
19. HEIC/PNG/GIF không bị chuyển đổi âm thầm.
20. Photos save là điểm commit đầu tiên.
21. SwiftData index hoàn tất trước completed.
22. Retry không tạo ảnh trùng.
23. Cancel dừng và cleanup đúng.
24. Session completed được cleanup.
25. Nizi Move không regression.
26. Test thiết bị thật 10/100/300 đã chạy và được ghi nhận.
27. Không có P0 còn mở trước release.

---

## 27. Chỉ dẫn thực hiện cho Codex

Trước khi sửa code:

1. Đọc toàn bộ:
   - `SURVEY-IOS-FILE-PROVIDER-IMPORT.md`.
   - Các model/coordinator của Nizi Move.
   - `NiziMovePhotoSaver.swift`.
   - SwiftData model/container hiện tại.
   - Điểm điều hướng import hiện tại.
2. Lập danh sách file thực tế cần tạo/sửa.
3. Xác định helper nào có thể tách dùng chung mà không gây regression.
4. Không sửa production theo suy đoán khi chưa đọc implementation hiện tại.
5. Không thêm Google OAuth, Google SDK hoặc backend.
6. Không thay đổi protocol Nizi Move nếu không bắt buộc.
7. Chia commit theo sprint nhỏ.
8. Sau mỗi sprint:
   - Build.
   - Chạy test.
   - Ghi rõ phần đã xác minh.
   - Ghi rõ phần chỉ mới code nhưng chưa test thiết bị thật.

Khi báo cáo hoàn thành, phải phân biệt rõ:

```text
Đã kiểm tra bằng unit/integration test
Đã kiểm tra trên simulator
Đã kiểm tra trên thiết bị thật
Chưa kiểm tra
```

Không được thay số liệu thiết bị thật bằng giả định.

---

## 28. Kết luận

Triển khai lựa chọn A:

```text
UIDocumentPicker + asCopy
→ local persistent import session
→ ImageIO validation/thumbnail
→ review
→ keep original hoặc optimize
→ PhotoKit
→ SwiftData
→ recovery/cleanup
```

Đây là một module import local độc lập.

Không xây Google Drive browser, không dùng Google OAuth, không dùng API key và không đưa chức năng này qua Nizi Move trong MVP.
