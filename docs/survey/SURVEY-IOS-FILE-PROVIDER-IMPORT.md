# SURVEY — iOS File Provider Import (Google Drive và Files)

**Trạng thái:** khảo sát mã nguồn + tài liệu chính thức, không thay đổi production.  
**Ngày:** 2026-08-04.  
**Quyết định MVP:** **A — Document Picker đủ cho MVP.**

## 1. Kết luận

Nizi nên thêm một luồng import cục bộ, độc lập với Nizi Move:

```text
Files / UIDocumentPicker (asCopy: true)
→ thư mục ImportSession trong Application Support
→ preflight quota + metadata + ImageIO validation
→ thumbnail/review
→ xử lý tuần tự (hoặc copy 2–3, decode 1)
→ PHPhotoLibrary commit
→ index SwiftData
→ đánh dấu completed
→ dọn temporary files
```

`UIDocumentPickerViewController(forOpeningContentTypes: [.image], asCopy: true)` hỗ trợ nhiều file qua `allowsMultipleSelection`; Files là giao diện hệ thống, nên các provider đã cài (Google Drive, iCloud Drive, OneDrive, Dropbox…) tự xuất hiện. Apple cũng nêu rõ picker mở/copy các content type chỉ định và có `allowsMultipleSelection`. [Apple: UIDocumentPickerViewController](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller)

MVP không cần backend, API key Google, OAuth token, Drive scope, hay quyền đọc toàn bộ Drive. Do đó nó thỏa thứ tự ưu tiên 1–4. Nizi Move vẫn chỉ dành cho computer/web → QR → iPhone; public share link, nếu làm, là phương án C độc lập và phụ.

**Ràng buộc quan trọng:** không thể trung thực tuyên bố đã test Drive trên thiết bị thật từ workspace này. Bảng test thiết bị ở §7 là protocol và trạng thái **chưa chạy**; cần chạy trước release để chốt số liệu 10/100/300 ảnh, mạng yếu, background và từng provider/phiên bản iOS.

## 2. Kiến trúc hiện có và phần tái sử dụng

Nizi Move hiện là một import pipeline có server session, không phải file-provider import:

```text
QR → claim token Keychain → manifest → URLSession.download
→ file tạm → SHA-256 → PHPhotoLibrary
→ SwiftData index → server acknowledgement → cleanup
```

Các điểm đã có thể tái sử dụng về mặt thiết kế:

| Hiện có | Bằng chứng | Dùng lại / điều chỉnh cho local import |
|---|---|---|
| Trạng thái asset/session bền vững | `NiziMoveModels.swift`, `MDNiziMoveImport.swift`, `NiziMoveImportStore.swift` | Tách model/protocol chung; không dùng nguyên schema có `accessToken`, `downloadURL`, ACK server. |
| Luồng commit đúng thứ tự | `NiziMoveImportCoordinator.process`: save Photos → index → terminal state → delete temp | Dùng cùng nguyên tắc: chỉ completed sau Photos và index thành công. |
| SHA-256 streaming | `NiziMovePhotoSaver.sha256(of:)` dùng `FileHandle.read(upToCount:)` 1 MiB | Có thể chuyển thành `ImportFileHasher`; chỉ hash khi cần dedupe, không là điều kiện bắt buộc MVP. |
| Đọc EXIF capture date | `NiziMovePhotoSaver.embeddedCaptureDate(in:)` dùng ImageIO | Tái sử dụng/tách helper metadata; thêm orientation, pixel size, UTI. |
| Lưu Photos | `NiziMovePhotoSaver.save` với `PHPhotoLibrary.performChanges` | Tách thành saver nhận metadata local; hiện saver chỉ phù hợp `NiziMoveManifestAsset`. |
| Kiểm tra disk | `availableStorage()` trong coordinator | Nâng thành preflight + reserve + kiểm tra sau từng nhóm; current check chỉ bằng tổng manifest size. |

Không tái sử dụng `NiziMoveAPI`, QR parser, Keychain token, manifest server, acknowledge, hoặc public-link handling. Local import không có server và không được mang Google credential vào các thành phần này.

## 3. Prototype được đề xuất

Chọn UIKit wrapper (dễ kiểm soát `asCopy`) trong SwiftUI. UIKit và SwiftUI đều hợp lệ; SwiftUI `fileImporter` cũng trả security-scoped URL và yêu cầu mở/đóng scope khi truy cập. [Apple: fileImporter](https://developer.apple.com/documentation/swiftui/view/fileimporter%28ispresented%3Aallowedcontenttypes%3Aallowsmultipleselection%3Aoncompletion%3Aoncancellation%3A%29)

```swift
let picker = UIDocumentPickerViewController(
    forOpeningContentTypes: [.image],
    asCopy: true
)
picker.allowsMultipleSelection = true
```

Delegate phải chỉ chuyển các URL vào `LocalFileImportCoordinator`, không tạo `UIImage` hay đọc `Data(contentsOf:)` trên main thread. Mỗi URL được copy/move ngay vào `Application Support/ImportSessions/<UUID>/source/` với filename được sanitize và tên collision-safe. `asCopy: true` là lựa chọn MVP vì lifecycle rõ ràng: sau callback Nizi sở hữu bản copy và có thể review/retry sau khi provider không còn khả dụng.

Mẫu xử lý an toàn nếu trong thực tế provider vẫn trả URL cần scope (hoặc nếu chọn phương án open URL):

```swift
let didAccess = url.startAccessingSecurityScopedResource()
defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
var coordinator = NSFileCoordinator()
var error: NSError?
coordinator.coordinate(readingItemAt: url, options: [], error: &error) { readableURL in
    try? FileManager.default.copyItem(at: readableURL, to: destination)
}
```

Không lưu URL thô qua lần mở app. Apple yêu cầu security scope cho URL ngoài sandbox, file coordination khi đọc/ghi external document, và chỉ bookmark khi thực sự phải truy cập lại. [Apple: document picker security-scoped URLs](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller)

### Thiết kế pipeline

1. Kiểm max 300 URL; tạo session folder và journal persisted trước khi copy.
2. Preflight quota: available capacity for important usage, reserve tối thiểu, ước lượng source + output; không chỉ tin `fileSize` provider báo.
3. Copy 2–3 file đồng thời vào sandbox; ghi byte thực tế; sau mỗi nhóm kiểm tra disk. Khi sát ngưỡng, dừng các job mới và báo retryable.
4. Trên utility queue: đọc `URLResourceValues` (`name`, `fileSize`, `contentType`, dates), header/UTI thực, `CGImageSourceCreateWithURL`, dimensions và EXIF. MIME/extension chỉ là gợi ý; ImageIO là validation.
5. Tạo thumbnail bằng `CGImageSourceCreateThumbnailAtIndex` với cache/decode options và max pixel size; ImageIO hỗ trợ đọc URL, properties, và tạo thumbnail mà không cần nạp toàn bộ batch vào RAM. [Apple: CGImageSource](https://developer.apple.com/documentation/imageio/cgimagesource)
6. Review grid lazy-load thumbnail, hiển thị lỗi theo file; select all/none và tổng dung lượng actual.
7. Commit: tối ưu hoặc giữ nguyên từng file, một decode/output tại một thời điểm; `PHPhotoLibrary.performChanges` thành công là commit Photos; sau đó index SwiftData, cập nhật completed, rồi cleanup. Lỗi thì `failed`/`retryable`, giữ source theo retention policy.
8. Lúc app start: recovery quét journal session non-terminal; xóa session cancelled/completed cũ theo retention. Không tự retry provider URL; retry từ bản copy sandbox.

### Định dạng và metadata

`UTType.image` không thay thế validation. Matrix cần kiểm trên thiết bị: HEIC, JPEG, PNG, GIF, TIFF, WebP. ImageIO support thực tế phụ thuộc iOS/provider và file; unsupported/corrupt phải vào review với trạng thái không chọn được. “Giữ nguyên” copy nguyên bytes, vì vậy giữ EXIF container nếu Photos chấp nhận file. “Tối ưu” có thể mất metadata/animation nếu encoder không chủ động copy properties; phải test EXIF orientation/date/GPS và GIF frame count. Quy tắc MVP an toàn:

| Format | Giữ nguyên | Tối ưu MVP |
|---|---|---|
| JPEG | Có | JPEG q≈0.85, max long edge 3000, copy selected metadata |
| HEIC | Có | Giữ HEIC ở MVP (không silently đổi format); quyết định conversion sau benchmark |
| PNG transparency | Có | Giữ nguyên; không JPEG hóa ảnh alpha |
| GIF | Có | Giữ nguyên để giữ animation |
| TIFF/WebP | Nếu PhotoKit/ImageIO validate | Hiển thị supported/unsupported sau test; fallback original nếu Photos save thất bại |

Ngày tạo file provider không đáng tin để thay thế capture date: ghi cả provider `creationDate/modificationDate` và EXIF original; ưu tiên EXIF capture date giống logic Nizi Move hiện tại. File name có thể giữ; **cấu trúc thư mục không phải contract của picker multi-file**. MVP hiển thị relative display path nếu provider trả được, nhưng không nhận “chọn folder và recursive import” như requirement chắc chắn.

## 4. `asCopy: true` so với security-scoped URL

| Tiêu chí | `asCopy: true` — chọn MVP | Open URL + security scope |
|---|---|---|
| Lifecycle/retry sau app restart | Nizi có copy riêng, đơn giản | Cần bookmark (nếu cần resume), stale bookmark và provider availability |
| File coordination | Ít phụ thuộc provider sau callback | Bắt buộc khi external document |
| Disk peak | Có thể ~source copy + optimized output; cần reserve | Thấp hơn lúc review, nhưng output/Photos vẫn cần disk |
| Network/provider lỗi | Cô lập sau lúc copy xong | Đọc sau có thể trigger/đứt download provider |
| Phù hợp batch 300 | Có, với bounded concurrency/quota | Phức tạp, lợi ích disk chưa chứng minh |

Nói cách khác, `asCopy: true` không có nghĩa là “không dùng disk”: phải benchmark peak; nếu source 5 GB và output còn tồn tại đồng thời, có thể gần 2× (hoặc hơn theo implementation). MVP cần reserve cấu hình, ví dụ `source bytes copied + worst-case output + safety margin`; không claim 5 GB sẽ luôn import trên iPhone dung lượng thấp. Security-scoped URL là giai đoạn sau chỉ khi benchmark chứng minh disk là blocker thực tế.

## 5. Hành vi provider, cloud và background

Files là UI của hệ điều hành/provider. Nizi không kiểm soát thumbnail, folder browsing, cache hay download dialog của Google Drive/OneDrive/Dropbox. Sau khi chọn, provider có thể cần fetch từ cloud trước khi URL đọc được; Nizi chỉ bắt đầu own pipeline khi copy có thể đọc thành công. Việc đóng picker trước callback là cancel: không có session/không có temp file để clean. Lỗi copy (offline, timeout, provider error) phải được surfaced per-file hoặc per-selection và cho người dùng chọn lại.

Apple có URL ubiquitous download status cho **iCloud** (`notDownloaded`, `downloaded`, `current`) và API start downloading; đây không phải generic progress contract cho Google Drive File Provider. [Apple: ubiquitous download status](https://developer.apple.com/documentation/foundation/urlresourcekey/ubiquitousitemdownloadingstatuskey) Vì vậy MVP chỉ có progress chính xác cho bytes Nizi tự copy/process; không hứa progress tải nội bộ của provider. Với iCloud-only file, có thể hiện “Đang chuẩn bị từ iCloud” và poll status; với provider bên thứ ba, UI phải là indeterminate/progress best-effort.

`fileImporter` cancellation không gọi completion (nếu dùng overload có `onCancellation`, callback đó được gọi). [Apple: fileImporter](https://developer.apple.com/documentation/swiftui/view/fileimporter%28ispresented%3Aallowedcontenttypes%3Aallowsmultipleselection%3Aoncompletion%3Aoncancellation%3A%29) Nếu background khi picker/provider đang download, Nizi không có API để đảm bảo resume provider work. Sau khi sandbox copy xong, use persisted journal; app background execution vẫn không được coi là guaranteed. Background completion/retry là P1 và cần test real device; không dùng `URLSession` background để “resume” file-provider download vì provider download không phải request do Nizi sở hữu.

## 6. So sánh A / B / C

| | A. Document Picker | B. OAuth + Drive API native | C. Public link qua Nizi Move |
|---|---|---|---|
| Nguồn | Mọi Files provider | Chỉ Google Drive | Nguồn public/web/desktop |
| Backend/credential | Không | OAuth client/tokens Keychain | Server Nizi Move |
| Chọn nhiều ảnh | Có, hệ thống/provider UI | Có, Nizi phải tự xây | Sau server enumerate |
| Privacy/scope | Per-file user action | `drive.file` tối thiểu; `drive.readonly` restricted | Không chuyển Google credential vào QR/manifest |
| Resume cloud download | Provider-dependent | Nizi kiểm soát URLSession sau OAuth | Nizi Move download protocol hiện có |
| MVP recommendation | **Có** | Không | Không thay thế A; chỉ feature phụ sau này |

B chỉ được xem lại nếu §7 chứng minh A thất bại ở một nhu cầu trọng yếu (batch 100–300 không thao tác được, folder UX, thumbnail, metadata, progress/resume) trên cohort thực tế. UI đẹp hơn không là bằng chứng đủ. Nếu B bắt buộc, dùng authorization code + PKCE qua system browser/Google Sign-In hoặc AppAuth; không dùng embedded `WKWebView`, không có client secret trong app. [Google: OAuth native apps](https://developers.google.com/identity/protocols/oauth2/native-app)

Scope ưu tiên là `drive.file`, scope non-sensitive và per-file; `drive.readonly` là restricted và mở quyền download toàn Drive. Verification là cần cho app public với scope user data; restricted data lưu/truyền server kéo theo security assessment. [Google: Drive scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth) Nếu B tồn tại: access/refresh token chỉ Keychain, logout/revoke, multi-account, `invalid_grant`, Workspace admin policy (`admin_policy_enforced`), shared drives/shortcuts/resource keys/`canDownload`, pagination/backoff và `URLSession` background là requirements riêng. Link-shared items có thể cần resource key header; đây là API concern của B, **không** được đưa resource key vào Nizi Move QR/manifest. [Google: resource keys](https://developers.google.com/workspace/drive/api/guides/resource-keys)

## 7. Kế hoạch test thiết bị thật — bắt buộc trước release

**Trạng thái thực thi hiện tại: chưa chạy.** Không có iPhone, account provider, Xcode device run hay instrumentation trace được cung cấp trong workspace. Không thay “chưa chạy” bằng số liệu giả.

Thiết bị tối thiểu: một iPhone cấu hình thấp được hỗ trợ và một iPhone hiện hành; iOS release target + bản iOS mới nhất được Nizi hỗ trợ. Provider: iCloud Drive, Google Drive, OneDrive, Dropbox; ghi version provider và network (Wi‑Fi tốt, network shaping yếu, offline). Sample phải có JPEG/HEIC/PNG/GIF/TIFF/WebP và corrupt file.

| Case | 10 | 100 | 300 | Cần ghi nhận / pass |
|---|---:|---:|---:|---|
| Google Drive online/local | chạy | chạy | chạy | Picker selection, callback URLs, success/fail, names |
| Google Drive cloud-only | chạy | chạy | chạy | thời gian provider prepare/copy, cancel khi đang tải, recovery |
| iCloud Drive cloud-only | chạy | chạy | chạy | ubiquitous status, prepare/error |
| OneDrive/Dropbox | chạy | chạy | chạy | cùng matrix, provider-specific limits |
| Review → keep original | chạy | chạy | chạy | peak disk, RSS/memory warning, commit count |
| Review → optimize | chạy | chạy | chạy | peak disk, output format/EXIF, elapsed time |
| Background / force-close | chạy | chạy | chạy | state journal, no false completed, retry behaviour |
| Network loss during provider fetch/copy | chạy | chạy | chạy | error surface, temp cleanup, no corrupt commit |

Đo bằng Instruments (Allocations/Leaks, Memory Graph, Time Profiler), Xcode memory gauge + device analytics, `volumeAvailableCapacityForImportantUsage`, per-session actual bytes/time, and logs per phase. Báo cáo số liệu cần tối thiểu: selection-to-callback, copy/validate/thumbnail/review/commit elapsed, max RSS, disk before/max/after cleanup, selected/completed/failed/cancelled, Photos local identifiers, EXIF comparison. Không giải phóng toàn batch thumbnail/decoded image cùng lúc; thumbnail queue bounded, decode/resize max 1, copy max 2–3.

## 8. Giới hạn không thể khắc phục hoàn toàn

* Nizi không thể ép Files provider cung cấp batch select, folder recursion, thumbnail, metadata hay download progress giống nhau. Đây là capability và UX của provider.
* Không có contract generic để Nizi resume download mà Google Drive/Dropbox provider đang làm trong picker.
* `asCopy` chịu peak disk; quota 5 GB là product cap, không phải bảo đảm import được trên mọi device.
* Photos hỗ trợ/import metadata của từng format có thể khác nhau; preserve bytes không đồng nghĩa `PHAsset` sẽ expose tất cả EXIF sau import.
* Tên file có thể giữ, nhưng hierarchy không được đảm bảo khi picker trả danh sách files; folder import không nằm MVP.

## 9. Phạm vi MVP, giai đoạn sau và file dự kiến

**MVP:** A, multi-image files only (max 300, configured 5 GB), `asCopy`, review lazy grid, keep-original default, PhotoKit commit/index/retry journal/cleanup, device matrix §7 pass. Không OAuth, backend, Drive browser, public-link import, folder recursive import hoặc generic provider download progress.

**Sau MVP:** disk-aware security-scoped experiment; optimized-image encoder + EXIF test hardening; background recovery UX; B chỉ theo evidence; C product decision riêng qua Nizi Move.

File production dự kiến khi được phê duyệt implementation (không sửa trong khảo sát):

* mới: `Nizi/Features/LocalFileImport/{Domain,Application,Infrastructure,Presentation}/…`
* sửa/tách: `Nizi/Features/NiziMove/Infrastructure/NiziMovePhotoSaver.swift` để có PhotoKit saver/EXIF helper không phụ thuộc manifest;
* sửa: điểm điều hướng import hiện có, có thể `Nizi/Features/NiziMove/Presentation/NiziMoveImportView.swift` hoặc một entry Import mới;
* sửa: `Nizi.xcodeproj/project.pbxproj`, model container `Nizi/NiziApp.swift` và `Nizi/ContentView.swift` nếu thêm SwiftData journal;
* mới: unit tests cho quota/state machine/validation/cleanup, UI/device test plan.

## 10. Rủi ro

| Priority | Rủi ro | Giảm thiểu / release gate |
|---|---|---|
| P0 | OOM hoặc hết disk làm app kill/mất retry state | Bounded queues, session journal trước copy, reserve + per-batch disk check, device test 300. |
| P0 | Báo completed trước khi Photos/index thành công | State transition only after `performChanges` + index; idempotent recovery. |
| P0 | Rò security scope/đọc provider URL sai | `defer stopAccessing`, `NSFileCoordinator`; MVP own copy immediately. |
| P1 | Provider cloud-only/offline/cancel behavior khác nhau | Real-device matrix per provider; copy failures retryable; no promised provider-progress/resume. |
| P1 | EXIF/animation/transparency mất khi optimize | Keep-original default; format-specific tests; original fallback. |
| P1 | 5 GB peak không đủ free storage | Dynamic quota + clear error; benchmark asCopy before enabling 5 GB cap. |
| P2 | Tên/path metadata không nhất quán | Treat provider metadata as optional/display-only; retain original filename where safe. |
| P2 | OAuth scope creep sau này | Decision gate; `drive.file` first, no Nizi Move token transfer. |

## 11. Go/no-go

Chọn **A** ngay bây giờ. Chỉ đổi sang **B** sau khi kết quả §7 có bằng chứng rõ ràng rằng Document Picker không đáp ứng một requirement MVP trọng yếu, kèm kết quả trên ít nhất Google Drive và iCloud Drive. Không chọn C làm luồng mặc định: nó không giải quyết import Drive cá nhân trên iPhone mà còn đưa backend vào một use case local.
