# ARCHITECTURE-MEMORY-DISCOVERY

## 1. Mục đích tài liệu

Tài liệu này mô tả kiến trúc của module **Memory Discovery** trong ứng dụng native iOS của Nizi.

Module này có nhiệm vụ:

- khảo sát thư viện ảnh trên iPhone;
- lập chỉ mục metadata cục bộ;
- nhóm ảnh theo thời gian và địa điểm;
- đề xuất các sự kiện có thể tạo thành Album;
- hỗ trợ người dùng rà soát và chọn ảnh;
- chỉ chuyển những ảnh được xác nhận sang hệ thống Nizi Web/API.

Module không thay thế Apple Photos và không tự động upload toàn bộ thư viện.

---

## 2. Bối cảnh hệ thống

Nizi hiện có hai ứng dụng độc lập:

```text
nizi-web/
nizi-ios/
```

### Nizi Web

Phụ trách:

- tài khoản;
- Album;
- chỉnh sửa Album;
- chia sẻ;
- dữ liệu server;
- quản lý ảnh đã upload;
- API dành cho mobile.

### Nizi iOS

Phụ trách:

- truy cập thư viện Photos qua PhotoKit;
- khảo sát metadata;
- tạo chỉ mục cục bộ;
- phát hiện sự kiện;
- chọn ảnh;
- tạo Album Draft;
- upload ảnh đã chọn.

---

## 3. Product Philosophy

### 3.1. Local-first

Dữ liệu khảo sát thư viện được xử lý và lưu trên thiết bị.

Mặc định không upload:

- toàn bộ danh sách ảnh;
- tọa độ GPS;
- thumbnail;
- feature print;
- dữ liệu phân tích;
- đề xuất bị từ chối.

### 3.2. Metadata-first

Pipeline xử lý:

```text
Metadata
→ Temporal grouping
→ Spatial grouping
→ EventCandidate
→ Thumbnail analysis
→ User review
→ Original upload
```

Không tải ảnh gốc trong quá trình khảo sát ban đầu.

### 3.3. Suggest, not decide

Nizi chỉ đề xuất. Người dùng luôn có quyền:

- đổi tên;
- thêm ảnh;
- bỏ ảnh;
- tách sự kiện;
- gộp sự kiện;
- bỏ qua đề xuất;
- tạo Album hoặc không tạo.

### 3.4. Progressive intelligence

MVP ưu tiên thuật toán có thể giải thích:

- thời gian;
- vị trí;
- mật độ ảnh;
- favorite;
- burst;
- loại media.

AI/Vision được bổ sung sau khi lõi hoạt động ổn định.

### 3.5. Resumable by design

Mọi tác vụ dài phải:

- chia batch;
- lưu checkpoint;
- có thể tạm dừng;
- tiếp tục khi app mở lại;
- không phụ thuộc app chạy liên tục.

---

## 4. Kiến trúc tổng thể

```text
┌────────────────────────────────────────────┐
│ Nizi iOS Presentation                     │
│ SwiftUI Screens, Components, ViewModels   │
├────────────────────────────────────────────┤
│ Application                               │
│ Use Cases, Coordinators, DTOs             │
├────────────────────────────────────────────┤
│ Domain                                    │
│ Entities, Rules, Scoring, Repositories    │
├────────────────────────────────────────────┤
│ Infrastructure                            │
│ PhotoKit, Persistence, Vision, Geocoding  │
├────────────────────────────────────────────┤
│ Apple Frameworks                          │
│ Photos, Vision, CoreLocation, Background  │
└────────────────────────────────────────────┘
```

Module giao tiếp với Nizi Web thông qua API, không truy cập trực tiếp database server.

---

## 5. Phân lớp

## 5.1. Presentation

Bao gồm:

- màn hình;
- component;
- ViewModel;
- navigation;
- trạng thái UI.

Presentation không được:

- gọi trực tiếp `PHAsset.fetchAssets`;
- ghi trực tiếp SwiftData;
- chứa thuật toán clustering;
- giữ `UIImage` lâu dài trong state.

## 5.2. Application

Bao gồm các use case:

- RequestPhotoAccess;
- ScanPhotoLibrary;
- ResumePhotoLibraryScan;
- DiscoverEvents;
- AnalyzeEventCandidate;
- ConvertCandidateToAlbumDraft;
- SynchronizeLibraryChanges;
- PrepareAlbumUpload.

Application điều phối luồng nhưng không chứa chi tiết PhotoKit.

## 5.3. Domain

Bao gồm:

- `LocalAsset`;
- `PhotoSession`;
- `EventCandidate`;
- `SimilarityGroup`;
- `AlbumDraft`;
- scoring rules;
- clustering rules;
- repository protocols.

Domain không import:

```swift
Photos
SwiftUI
UIKit
SwiftData
```

## 5.4. Infrastructure

Bao gồm:

- PhotoKit adapter;
- SwiftData repositories;
- thumbnail cache;
- Vision analyzer;
- reverse geocoding;
- background task integration;
- API client.

---

## 6. Các thành phần chính

### 6.1. PhotoAuthorizationService

Trách nhiệm:

- đọc trạng thái quyền;
- yêu cầu quyền;
- phân biệt Full/Limited/Denied;
- mở limited picker;
- phát sự kiện khi quyền thay đổi.

```swift
protocol PhotoAuthorizationService {
    func currentStatus() async -> PhotoAccessStatus
    func requestAccess() async -> PhotoAccessStatus
    func presentLimitedLibraryPicker()
}
```

### 6.2. PhotoAssetProvider

Lớp duy nhất giao tiếp trực tiếp với PhotoKit.

```swift
protocol PhotoAssetProvider {
    func fetchAssets(cursor: AssetCursor?) async throws -> AssetBatch
    func fetchAsset(id: String) async throws -> PhotoAssetDTO?
    func requestThumbnail(
        assetID: String,
        targetSize: CGSize,
        networkAllowed: Bool
    ) async throws -> PlatformImage
    func requestOriginal(
        assetID: String,
        networkAllowed: Bool
    ) async throws -> OriginalAssetResource
}
```

Không truyền `PHAsset` xuyên suốt toàn hệ thống.

### 6.3. LibraryScanner

Trách nhiệm:

- quét metadata theo batch;
- ghi index;
- lưu checkpoint;
- báo progress;
- retry theo batch;
- tiếp tục sau khi app bị đóng.

### 6.4. LocalMemoryIndex

Lưu metadata cục bộ.

Không lưu:

- ảnh gốc;
- toàn bộ thumbnail;
- binary dung lượng lớn.

### 6.5. EventDiscoveryEngine

Pipeline:

```text
Unclustered LocalAsset
→ Temporal Segmentation
→ Spatial Clustering
→ PhotoSession
→ Event Merging
→ Event Scoring
→ EventCandidate
```

### 6.6. PhotoAnalysisEngine

Chạy có chọn lọc sau khi đã có EventCandidate.

Các mức:

```text
Tier 0: metadata only
Tier 1: thumbnail nhỏ
Tier 2: preview vừa
Tier 3: original khi cần upload/in
```

### 6.7. AlbumDraftCoordinator

Chuyển EventCandidate sang AlbumDraft.

Không tạo Album server ngay khi người dùng mở candidate.

### 6.8. UploadHandoffService

Trách nhiệm:

- tạo album server;
- tạo upload session;
- kiểm tra asset còn khả dụng;
- tải ảnh gốc;
- upload theo queue;
- resume;
- đánh dấu complete.

---

## 7. Domain entities

### LocalAsset

```swift
struct LocalAsset {
    let id: String
    let creationDate: Date?
    let coordinate: Coordinate?
    let mediaType: MediaType
    let pixelWidth: Int
    let pixelHeight: Int
    let isFavorite: Bool
    let isScreenshot: Bool
    let burstIdentifier: String?
    var availability: AssetAvailability
    var discoveryStatus: DiscoveryStatus
    var analysisVersion: Int
}
```

### PhotoSession

```swift
struct PhotoSession {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let assetIDs: [String]
    let centerCoordinate: Coordinate?
    let densityScore: Double
}
```

### EventCandidate

```swift
struct EventCandidate {
    let id: UUID
    var titleSuggestion: String
    let startDate: Date
    let endDate: Date
    var primaryLocationLabel: String?
    var assetIDs: [String]
    var sessionIDs: [UUID]
    var coverAssetID: String?
    var confidence: Double
    var score: Double
    var status: EventCandidateStatus
    var reasons: [DiscoveryReason]
}
```

### AlbumDraft

```swift
struct AlbumDraft {
    let id: UUID
    let sourceCandidateID: UUID?
    var title: String
    var selectedAssetIDs: [String]
    var rejectedAssetIDs: [String]
    var coverAssetID: String?
    var sortMode: AlbumSortMode
    var uploadState: AlbumDraftUploadState
}
```

---

## 8. Event Discovery

## 8.1. Temporal segmentation

Mặc định ban đầu:

```text
0–30 phút: cùng phiên mạnh
30 phút–3 giờ: có thể cùng session
3–8 giờ: xét thêm vị trí và mật độ
> 8 giờ: ưu tiên session mới
```

Các ngưỡng phải cấu hình được.

## 8.2. Spatial clustering

Các tín hiệu:

- khoảng cách GPS;
- cùng thành phố;
- thời gian di chuyển;
- điểm dừng;
- chuỗi ảnh có GPS xen kẽ ảnh không GPS.

Không reverse geocode từng ảnh.

Chỉ reverse geocode:

- cluster center;
- candidate có điểm đủ cao;
- màn hình đang hiển thị.

## 8.3. Event merging

Gộp session khi:

- liên tục nhiều ngày;
- cùng hành trình;
- chuyển địa điểm hợp lý;
- không có khoảng nghỉ dài;
- có chung pattern ảnh.

## 8.4. Event scoring

```text
eventScore =
  timeCohesion
+ locationCohesion
+ density
+ durationValue
+ favoriteBonus
+ visualDiversity
- screenshotPenalty
- duplicatePenalty
- lowQualityPenalty
```

MVP chưa cần machine learning.

---

## 9. Concurrency và hiệu năng

### Quy tắc

- không quét trên main thread;
- không giữ toàn bộ asset trong RAM;
- ghi database theo batch;
- thumbnail chỉ tải gần viewport;
- Vision tối đa 1–2 tác vụ đồng thời;
- original chỉ tải khi upload;
- hủy request khi cell rời màn hình.

### Gợi ý batch ban đầu

```text
PhotoKit fetch batch: 500–1.000
DB write batch: 250–500
Vision concurrency: 1–2
Thumbnail prefetch: 1–2 màn hình
```

Các giá trị phải benchmark trên máy thật.

---

## 10. Background processing

App phải lưu checkpoint ngay khi:

- chuyển background;
- bị memory warning;
- người dùng pause;
- scan gặp lỗi;
- app chuẩn bị đóng.

Không cam kết scan sẽ chạy liên tục khi app đã đóng.

`BGProcessingTask` chỉ là tối ưu bổ sung.

---

## 11. Privacy boundary

```text
On-device:
- LocalAsset
- GPS chưa xác nhận
- EventCandidate
- SimilarityGroup
- quality score
- thumbnail cache
- dismissed history

Server:
- Album đã xác nhận
- ảnh đã chọn
- title
- date range
- location label tổng quát
- cover
- thứ tự
```

Phải có nút:

```text
Xóa dữ liệu khám phá trên thiết bị
```

Không xóa ảnh khỏi Apple Photos.

---

## 12. Error handling

Một ảnh lỗi không làm hỏng toàn bộ batch.

```swift
enum DiscoveryError {
    case permissionDenied
    case photoLibraryUnavailable
    case assetUnavailable
    case iCloudDownloadRequired
    case iCloudDownloadFailed
    case databaseFailure
    case scanInterrupted
    case insufficientStorage
    case analysisFailed
}
```

Mỗi batch cần:

- transaction;
- retry giới hạn;
- log;
- skip asset lỗi;
- checkpoint.

---

## 13. Folder structure

```text
nizi-ios/
├── NiziApp/
├── Features/
│   └── MemoryDiscovery/
│       ├── Presentation/
│       ├── Application/
│       ├── Domain/
│       ├── Infrastructure/
│       └── Tests/
├── Core/
│   ├── Networking/
│   ├── Persistence/
│   └── Logging/
└── Docs/
```

---

## 14. Architectural Decisions

Formal ADRs for this module now live in [docs/architecture/ADR/](../../architecture/ADR/) (ADR-MD-001 through ADR-MD-010).

---

## 15. Definition of Done kiến trúc

Kiến trúc được coi là đáp ứng khi:

- PhotoKit bị cô lập trong Infrastructure;
- Domain test được không cần thiết bị;
- scan theo batch và resume được;
- Limited Access được hỗ trợ;
- không có upload ngầm;
- EventCandidate tạo được từ metadata;
- AlbumDraft độc lập với server Album;
- app không giữ toàn bộ ảnh trong RAM;
- dữ liệu khảo sát xóa được;
- module tích hợp được với API Nizi Web.
