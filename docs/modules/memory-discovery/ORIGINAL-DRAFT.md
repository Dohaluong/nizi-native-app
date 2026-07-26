# NIZI NATIVE — PHOTO LIBRARY DISCOVERY MODULE

**Tên module đề xuất:** `Memory Discovery`\
**Tên kỹ thuật:** `PhotoLibraryDiscovery`\
**Nền tảng:** Native iOS\
**Công nghệ chính:** Swift, SwiftUI, PhotoKit, Vision, Core Location, SwiftData hoặc SQLite

---

# 1. Bối cảnh

Người dùng có thể sở hữu hàng nghìn hoặc hàng chục nghìn ảnh được chụp trong nhiều năm.

Phần lớn ảnh trong thư viện:

- chưa được tổ chức thành album;

- có nhiều ảnh gần giống nhau;

- có ảnh mờ, ảnh chụp thử hoặc ảnh không có giá trị;

- bị trộn lẫn với screenshot, ảnh tải về, ảnh tài liệu;

- rất khó tìm lại theo từng chuyến đi hoặc sự kiện;

- hiếm khi được xem lại sau nhiều năm.

Nếu yêu cầu người dùng tự chọn hàng trăm ảnh rồi upload lên Nizi, trải nghiệm sẽ rất nặng và người dùng khó bắt đầu.

Module `Memory Discovery` giải quyết vấn đề này bằng cách:

1. khảo sát thư viện ảnh trực tiếp trên iPhone;

2. lập chỉ mục metadata cục bộ;

3. phát hiện các cụm ảnh có liên hệ về thời gian và địa điểm;

4. đề xuất các sự kiện có thể tạo thành album;

5. hỗ trợ chọn ra những ảnh có giá trị;

6. chỉ upload ảnh khi người dùng chủ động tạo album.

---

# 2. Product Philosophy

## 2.1. Nizi không thay thế Apple Photos

Nizi không cần trở thành một ứng dụng quản lý toàn bộ ảnh.

Apple Photos tiếp tục là nơi:

- lưu thư viện ảnh gốc;

- đồng bộ iCloud;

- chỉnh sửa ảnh;

- xóa và quản lý ảnh;

- lưu ảnh trên các thiết bị Apple.

Nizi chỉ đóng vai trò:

> Khám phá những câu chuyện đang bị ẩn trong thư viện ảnh và giúp người dùng biến chúng thành album có ý nghĩa.

---

## 2.2. Local-first

Toàn bộ quá trình khảo sát ban đầu phải diễn ra trên thiết bị.

Không upload mặc định:

- ảnh gốc;

- thumbnail;

- tọa độ GPS;

- dữ liệu nhận diện;

- dữ liệu gương mặt;

- danh sách toàn bộ thư viện.

Server Nizi chỉ nhận ảnh khi người dùng xác nhận tạo album hoặc sử dụng một chức năng cần đồng bộ.

---

## 2.3. Metadata-first

Không đọc ảnh chất lượng cao ngay từ đầu.

Thứ tự xử lý phải là:

```text
Metadata
→ Phân cụm thời gian và địa điểm
→ Thumbnail nhỏ
→ Phân tích hình ảnh có chọn lọc
→ Ảnh gốc khi thực sự cần
```

Cách này giúp giảm:

- thời gian quét;

- bộ nhớ;

- CPU;

- nhiệt độ thiết bị;

- pin;

- lưu lượng iCloud;

- dữ liệu upload.

---

## 2.4. Suggest, not decide

Nizi chỉ đề xuất, không tự quyết định.

Nizi có thể nói:

> Có vẻ đây là chuyến đi Đà Nẵng từ ngày 8 đến ngày 11 tháng 6 năm 2024.

Nhưng người dùng phải có quyền:

- đổi tên sự kiện;

- tách sự kiện;

- gộp sự kiện;

- bỏ ảnh;

- thêm ảnh;

- bỏ qua đề xuất;

- yêu cầu không đề xuất lại.

---

## 2.5. Progressive intelligence

Phiên bản đầu không cần sử dụng mô hình AI phức tạp.

Có thể phát triển theo từng lớp:

```text
Phase 1: Metadata rules
Phase 2: Image quality
Phase 3: Similarity and duplicate detection
Phase 4: Scene and people understanding
Phase 5: Personalized album curation
```

Không nên đưa toàn bộ AI vào ngay từ đầu.

---

## 2.6. Explainable suggestions

Mỗi đề xuất nên giải thích được lý do:

- 126 ảnh;

- chụp trong 4 ngày;

- phần lớn tại Đà Nẵng và Hội An;

- ảnh tập trung theo từng buổi;

- có nhiều ảnh gia đình;

- hệ thống đã tìm thấy 35 ảnh nổi bật.

Không nên chỉ hiển thị một album do “AI tạo” mà không có ngữ cảnh.

---

# 3. Mục tiêu module

## 3.1. Mục tiêu chính

Module phải có khả năng:

 1. xin và quản lý quyền truy cập thư viện ảnh;

 2. đọc danh sách ảnh qua PhotoKit;

 3. lập chỉ mục metadata cục bộ;

 4. xử lý thư viện có thể kéo dài nhiều năm;

 5. phân nhóm ảnh theo thời gian;

 6. phân nhóm ảnh theo tọa độ;

 7. phát hiện các sự kiện tiềm năng;

 8. tải thumbnail theo nhu cầu;

 9. đánh giá chất lượng ảnh;

10. phát hiện ảnh gần giống nhau;

11. đề xuất ảnh nổi bật;

12. cho người dùng duyệt lại sự kiện;

13. chuyển sự kiện thành album Nizi;

14. theo dõi thay đổi trong thư viện;

15. cập nhật chỉ mục theo kiểu incremental.

PhotoKit cung cấp cơ chế truy vấn `PHAsset`, sắp xếp kết quả bằng `PHFetchOptions` và theo dõi thay đổi thư viện thông qua `PHPhotoLibraryChangeObserver`.

---

## 3.2. Ngoài phạm vi ban đầu

Phiên bản đầu chưa cần:

- thay thế giao diện Apple Photos;

- sao lưu toàn bộ ảnh lên Nizi;

- đồng bộ nhận diện gương mặt giữa các thiết bị;

- chỉnh sửa ảnh chuyên sâu;

- xóa ảnh khỏi thư viện Apple;

- tự động tạo album mà không hỏi người dùng;

- chạy phân tích toàn bộ thư viện bằng cloud AI;

- xây hệ thống tìm kiếm ảnh tổng quát như Google Photos.

---

# 4. Vị trí trong hệ thống Nizi

```text
Nizi Native App
│
├── Account
├── Album Management
├── Album Editor
├── Upload Manager
├── Sharing
├── Memory Discovery
│   ├── Photo Library Access
│   ├── Local Memory Index
│   ├── Event Discovery
│   ├── Photo Analysis
│   ├── Album Suggestions
│   └── Discovery UI
└── Nizi API
```

`Memory Discovery` phải là module độc lập.

Module Album không nên truy cập PhotoKit trực tiếp. Khi cần ảnh, Album module gọi các interface do `Memory Discovery` cung cấp.

---

# 5. Kiến trúc tổng thể

Áp dụng kiến trúc theo lớp:

```text
Presentation
    ↓
Application / Use Cases
    ↓
Domain
    ↓
Infrastructure
```

Kiến trúc đề xuất:

```text
┌─────────────────────────────────────────┐
│ Presentation                            │
│ SwiftUI Screens, ViewModels             │
├─────────────────────────────────────────┤
│ Application                             │
│ Scan, Discover, Review, Create Album    │
├─────────────────────────────────────────┤
│ Domain                                  │
│ Asset, Event, Cluster, Score, Rules     │
├─────────────────────────────────────────┤
│ Infrastructure                          │
│ PhotoKit, Vision, SwiftData, Location   │
└─────────────────────────────────────────┘
```

---

# 6. Các thành phần chính

## 6.1. Photo Library Access

### Trách nhiệm

- kiểm tra trạng thái quyền;

- yêu cầu quyền đọc ảnh;

- xử lý Full Access;

- xử lý Limited Access;

- xử lý Denied;

- hướng dẫn người dùng thay đổi quyền;

- cung cấp trạng thái quyền cho UI.

### Interface

```swift
protocol PhotoLibraryAuthorizationService {
    func currentStatus() async -> PhotoAccessStatus
    func requestAccess() async -> PhotoAccessStatus
    func presentLimitedLibraryPicker()
}
```

### Trạng thái domain

```swift
enum PhotoAccessStatus {
    case notDetermined
    case limited
    case full
    case denied
    case restricted
}
```

Nếu người dùng chỉ cấp Limited Access, module chỉ được khảo sát những asset đã được cấp quyền. Vì vậy, kết quả phải hiển thị rõ:

> Nizi hiện chỉ khảo sát 243 ảnh được cho phép.

Không được trình bày như thể Nizi đã khảo sát toàn bộ thư viện.

---

## 6.2. PhotoKit Asset Provider

Đây là lớp duy nhất giao tiếp trực tiếp với PhotoKit.

### Trách nhiệm

- lấy danh sách `PHAsset`;

- đọc metadata;

- lấy thumbnail;

- lấy ảnh preview;

- yêu cầu ảnh gốc;

- theo dõi thay đổi thư viện;

- hủy yêu cầu thumbnail khi cell rời màn hình;

- cache thumbnail đang hiển thị.

### Interface

```swift
protocol PhotoAssetProvider {
    func fetchAssets(
        after cursor: AssetCursor?
    ) async throws -> AssetBatch
```

```
func requestThumbnail(
    assetID: String,
    targetSize: CGSize
) async throws -&gt; PlatformImage

func requestPreview(
    assetID: String,
    targetSize: CGSize
) async throws -&gt; PlatformImage

func requestOriginal(
    assetID: String,
    networkAccessAllowed: Bool
) async throws -&gt; OriginalAssetResource
```

`}`

### Quy tắc

Không truyền `PHAsset` xuyên suốt toàn ứng dụng.

Ngay sau khi đọc từ PhotoKit, phải chuyển thành domain model hoặc DTO nội bộ.

Điều này giúp:

- cô lập phụ thuộc PhotoKit;

- dễ test;

- giảm coupling;

- dễ thay đổi cách lưu trữ;

- tránh để UI phụ thuộc trực tiếp framework của Apple.

---

## 6.3. Local Memory Index

Local Memory Index là trung tâm dữ liệu của module.

Nó không chứa ảnh gốc. Nó chứa thông tin cần thiết để hiểu thư viện.

### Dữ liệu đề xuất

```text
LocalAsset
```

- `localID`
- `cloudIdentifier nếu có`
- `creationDate`
- `modificationDate`
- `latitude`
- `longitude`
- `mediaType`
- `mediaSubtypes`
- `pixelWidth`
- `pixelHeight`
- `duration`
- `favorite`
- `hidden`
- `sourceType`
- `burstIdentifier`
- `estimatedLocationCell`
- `discoveryStatus`
- `qualityStatus`
- `analysisVersion`
- `lastSeenAt`

`PHCloudIdentifier` có thể đại diện cho asset hoặc collection được đồng bộ qua iCloud Photos, nhưng không nên coi nó là điều kiện bắt buộc cho phiên bản đầu.

### Không lưu

Không lưu vào index:

- binary ảnh gốc;

- thumbnail toàn thư viện;

- embedding không cần thiết;

- dữ liệu tạm có thể tạo lại dễ dàng.

### Cơ sở dữ liệu

Có thể dùng:

- SwiftData nếu muốn tích hợp thuần Apple;

- SQLite hoặc GRDB nếu cần kiểm soát query, migration và hiệu năng tốt hơn.

Đề xuất cho Nizi:

> Dùng SwiftData trong MVP. Chuyển sang GRDB chỉ khi benchmark cho thấy SwiftData không đáp ứng thư viện lớn.

---

## 6.4. Library Scanner

### Trách nhiệm

- thực hiện quét lần đầu;

- quét theo batch;

- lưu tiến độ;

- cho phép tạm dừng;

- tiếp tục từ vị trí cũ;

- không khóa UI;

- tự điều chỉnh tốc độ theo tình trạng máy.

### Pipeline

```text
Fetch PHAsset batch
↓
Map metadata
↓
Normalize metadata
↓
Save LocalAsset batch
↓
Update scan checkpoint
↓
Continue next batch
```

### Batch

Không lấy và xử lý toàn bộ thư viện trong một lần.

Gợi ý ban đầu:

```text
Fetch batch: 500–1.000 assets
Database write batch: 250–500 rows
UI progress update: mỗi 1–2 giây
```

Các con số phải được benchmark trên thiết bị thật, không coi là hằng số sản phẩm.

### Trạng thái quét

```swift
enum LibraryScanState {
case idle
case requestingPermission
case scanning(progress: Double)
case paused
case completed
case partiallyCompleted
case failed(reason: ScanFailure)
}
```

---

## 6.5. Change Observer

Sau lần quét đầu tiên, app không quét lại toàn bộ thư viện mỗi lần mở.

PhotoKit cho phép đăng ký observer để nhận thông báo khi kết quả truy vấn thay đổi.

### Xử lý thay đổi

```text
Inserted assets
→ index asset mới
→ chạy clustering cục bộ
```

`Updated assets
→ cập nhật metadata
→ đánh dấu cluster liên quan cần tính lại`

`Deleted assets
→ đánh dấu unavailable
→ loại khỏi suggestion`

Không nên xóa record khỏi database ngay lập tức.

Nên dùng:

```text
availabilityStatus:
```

- `available`

- `unavailable`

- `deleted`

- `accessRevoked`

Lý do: một asset có thể tạm thời không truy cập được do quyền hoặc trạng thái thư viện.

---

# 7. Domain Model

## 7.1. LocalAsset

Đại diện cho một ảnh hoặc video được khảo sát.

```swift
struct LocalAsset {
let id: String
let creationDate: Date?
let coordinate: Coordinate?
let mediaType: MediaType
let pixelSize: PixelSize
let isFavorite: Bool
let sourceCategory: SourceCategory
```

`var qualityScore: Double?
var relevanceScore: Double?
var clusterIDs: Set<String>
}`

---

## 7.2. PhotoSession

Một nhóm nhỏ các ảnh được chụp gần nhau.

Ví dụ:

- buổi sáng tại bãi biển;

- bữa tối;

- tiệc sinh nhật;

- buổi chụp sofa;

- một lượt chụp liên tiếp.

```text
PhotoSession
```

- `id`
- `startTime`
- `endTime`
- `centerCoordinate`
- `assetCount`
- `density`
- `representativeAssetIDs`

---

## 7.3. EventCandidate

Một đề xuất sự kiện lớn hơn, có thể gồm nhiều session.

```text
EventCandidate
```

- `id`
- `startDate`
- `endDate`
- `primaryLocation`
- `secondaryLocations`
- `assetIDs`
- `sessionIDs`
- `eventType`
- `confidence`
- `status`
- `titleSuggestion`
- `coverAssetID`
- `discoveryReasons`

### Trạng thái

```swift
enum EventCandidateStatus {
case new
case viewed
case accepted
case dismissed
case snoozed
case merged
case convertedToAlbum
}
```

---

## 7.4. AlbumDraft

Khi người dùng chấp nhận EventCandidate, hệ thống tạo `AlbumDraft`.

```text
AlbumDraft
```

- `id`
- `sourceEventCandidateID`
- `selectedAssetIDs`
- `rejectedAssetIDs`
- `title`
- `dateRange`
- `locationLabel`
- `coverAssetID`
- `sortingMode`
- `uploadStatus`

AlbumDraft chưa phải album server.

Nó là giai đoạn trung gian để người dùng rà soát trước khi upload.

---

# 8. Event Discovery Engine

Đây là bộ não của module.

Không nên bắt đầu bằng một mô hình AI duy nhất. Nên dùng pipeline kết hợp nhiều tín hiệu.

```text
Assets
↓
Temporal segmentation
↓
Spatial clustering
↓
Session building
↓
Event merging
↓
Event scoring
↓
Suggestion generation
```

---

## 8.1. Temporal Segmentation

Sắp xếp ảnh theo thời gian chụp.

Tạo ranh giới nếu:

- khoảng cách thời gian vượt ngưỡng;

- chuyển sang ngày khác;

- mật độ ảnh giảm mạnh;

- có hành trình địa lý mới.

Ngưỡng không nên cố định cho mọi trường hợp.

Ví dụ:

```text
< 30 phút: rất có thể cùng phiên
30 phút – 3 giờ: có thể cùng session
3 – 8 giờ: tùy địa điểm và mật độ
> 8 giờ: có thể bắt đầu session mới
```

---

## 8.2. Spatial Clustering

Nếu ảnh có tọa độ:

- gom ảnh gần nhau;

- xác định điểm dừng;

- nhận biết thay đổi thành phố;

- hỗ trợ nối nhiều session thành một chuyến đi.

Không nên lưu địa chỉ chi tiết ngay từ đầu.

Có thể chuẩn hóa GPS thành các cell địa lý:

```text
GeoCell:
```

- `approximate area`
- `city-level region`
- `cluster center`

Việc reverse geocoding chỉ thực hiện cho các cụm đáng chú ý, không gọi cho từng ảnh.

---

## 8.3. No-location fallback

Nhiều ảnh không có GPS.

Khi đó dùng:

- thời gian;

- mật độ ảnh;

- chuỗi ảnh trước và sau có GPS;

- tính tương đồng hình ảnh;

- tên album Apple nếu được sử dụng;

- loại ảnh;

- các session liền kề.

Ví dụ:

```text
Ảnh A: Hà Nội, 10:00
Ảnh B: không GPS, 10:05
Ảnh C: không GPS, 10:08
Ảnh D: Hà Nội, 10:12
```

Có thể suy luận B và C thuộc cùng session nhưng phải đánh dấu là vị trí suy ra, không phải vị trí gốc.

---

## 8.4. Event merging

Các session có thể được gộp nếu:

- nằm trong cùng chuyến đi;

- liên tục trong vài ngày;

- có địa điểm gần nhau;

- có nhiều chủ thể tương đồng;

- không có khoảng nghỉ bất thường;

- có cùng pattern chụp.

Ví dụ:

```text
Session 1: Sân bay Nội Bài
Session 2: Bãi biển Đà Nẵng
Session 3: Hội An
Session 4: Khách sạn Đà Nẵng
```

Không nên tạo bốn album riêng. Nên đề xuất một chuyến đi gồm nhiều chương.

---

# 9. Event Scoring

Mỗi EventCandidate nhận một điểm.

```text
eventScore =
timeCohesion
```

- `locationCohesion`
- `photoDensity`
- `durationValue`
- `peoplePresence`
- `visualQuality`
- `uniqueness`
- `userPreference`


- `noisePenalty`

## Các yếu tố tăng điểm

- nhiều ảnh trong khoảng thời gian ngắn;

- có nhiều ảnh chất lượng tốt;

- có gương mặt;

- có nhiều địa điểm liên quan;

- có ảnh được favorite;

- khác biệt rõ với sinh hoạt thường ngày;

- kéo dài từ một đến vài ngày;

- có nhiều ảnh ngang và dọc phù hợp làm album;

- có ảnh mở đầu, cao trào và kết thúc.

## Các yếu tố giảm điểm

- quá nhiều screenshot;

- ảnh tài liệu;

- ảnh tải về;

- ảnh trùng;

- ảnh mờ;

- ảnh hoàn toàn tối;

- ảnh quá ít;

- cụm chỉ gồm ảnh chụp sản phẩm hoặc công việc lặp lại;

- cụm đã bị người dùng từ chối.

---

# 10. Photo Analysis Engine

Photo Analysis chỉ chạy sau khi metadata đã tạo được những cụm đáng quan tâm.

## 10.1. Các tầng phân tích

### Tier 0 — Metadata only

Không tải pixel ảnh.

Dùng:

- thời gian;

- tọa độ;

- kích thước;

- loại media;

- favorite;

- burst;

- screenshot subtype.

### Tier 1 — Small thumbnail

Thumbnail nhỏ, ví dụ 160–300 px.

Dùng để:

- phát hiện ảnh tối;

- phát hiện ảnh gần giống;

- tính màu sắc tổng quát;

- phát hiện screenshot hoặc tài liệu;

- tính feature print nhẹ.

### Tier 2 — Medium preview

Preview khoảng 600–1.200 px.

Dùng để:

- đánh giá chất lượng;

- phát hiện gương mặt;

- saliency;

- chọn cover;

- crop suggestion;

- image aesthetics;

- kiểm tra độ rõ.

Vision hỗ trợ các tác vụ như phát hiện gương mặt, phân loại ảnh, tạo feature print để so sánh ảnh, phân tích saliency và image aesthetics.

### Tier 3 — Original

Chỉ dùng khi:

- chuẩn bị upload;

- kiểm tra ảnh in;

- xuất photobook;

- người dùng mở ảnh full-screen;

- cần quyết định cuối cùng giữa các ảnh rất giống nhau.

---

## 10.2. Quality score

Mỗi ảnh có thể được chấm theo:

```text
qualityScore =
sharpness
```

- `exposure`
- `aestheticScore`
- `faceQuality`
- `composition`
- `resolutionFitness`


- `blurPenalty`
- `darknessPenalty`
- `obstructionPenalty`

Không được tự động xóa ảnh có điểm thấp.

Điểm chỉ dùng để:

- sắp xếp;

- chọn đại diện;

- đề xuất loại bớt;

- ưu tiên upload;

- chọn cover.

---

## 10.3. Duplicate và near-duplicate

Phân biệt:

### Exact duplicate

Hai file giống nhau hoặc có nội dung giống nhau gần tuyệt đối.

### Near-duplicate

Nhiều ảnh chụp liên tiếp:

- cùng người;

- cùng góc;

- khác biểu cảm;

- thay đổi rất nhỏ;

- burst.

Nhóm near-duplicate nên tạo:

```text
SimilarityGroup
```

- `assetIDs`
- `recommendedAssetID`
- `confidence`
- `userSelection`

UI có thể hiển thị:

> 8 ảnh tương tự — Nizi đề xuất giữ 2 ảnh.

---

## 10.4. Face handling

Phiên bản đầu chỉ cần:

- phát hiện có người hay không;

- đếm số gương mặt;

- ước lượng ảnh nhóm hoặc ảnh chân dung;

- đánh giá gương mặt có bị cắt;

- hỗ trợ chọn ảnh rõ mặt.

Không nên triển khai ngay:

- nhận diện danh tính;

- đặt tên người;

- đồng bộ dữ liệu gương mặt lên server;

- xây cơ sở dữ liệu sinh trắc học.

Nếu sau này cần nhận biết một người xuất hiện nhiều lần, dữ liệu embedding nên:

- nằm trên thiết bị;

- được mã hóa;

- có sự đồng ý riêng;

- có nút xóa;

- không upload mặc định.

---

# 11. Thumbnail Architecture

## 11.1. Không lưu toàn bộ thumbnail vĩnh viễn

PhotoKit và `PHCachingImageManager` nên là nguồn thumbnail chính cho gallery đang hiển thị.

Nizi chỉ nên có cache giới hạn:

```text
Memory cache
→ thumbnail đang hiển thị và sắp hiển thị
```

`Disk cache
→ cover, candidate preview, album draft đang xử lý`

`No cache
→ ảnh ngoài vùng quan tâm`

## 11.2. Cache key

```text
assetID
```

- `targetWidth`
- `targetHeight`
- `contentMode`
- `imageVersion`

## 11.3. Hủy yêu cầu

Khi cell rời màn hình:

- hủy request;

- giải phóng image reference;

- không giữ thumbnail trong ViewModel lâu dài.

---

# 12. Background Processing

Module cần hỗ trợ xử lý nền, nhưng không được giả định rằng iOS sẽ cho phép quét liên tục vô hạn.

Background Tasks cho phép đăng ký các công việc cập nhật và xử lý nền, nhưng thời điểm chạy vẫn do hệ thống quyết định.

## Chiến lược đề xuất

### Khi app đang mở

- quét metadata;

- hiển thị tiến độ;

- chạy phân cụm;

- phân tích các candidate đầu tiên.

### Khi app vào background

- lưu checkpoint ngay;

- hủy những request không cần thiết;

- tiếp tục công việc nếu hệ thống cho phép;

- đăng ký `BGProcessingTask`;

- không cam kết với người dùng rằng quét chắc chắn hoàn thành khi app đã đóng.

### Khi app mở lại

- đọc checkpoint;

- tiếp tục batch chưa hoàn thành;

- không quét lại từ đầu.

---

# 13. Scheduling và Resource Control

Cần có `ResourceGovernor`.

### Trách nhiệm

- giới hạn concurrency;

- theo dõi memory pressure;

- theo dõi thermal state;

- giảm tải khi pin yếu;

- ưu tiên UI;

- dừng Vision khi app không active;

- không tải ảnh iCloud hàng loạt.

```swift
protocol ResourceGovernor {
var allowedConcurrency: Int { get }
var allowsHeavyAnalysis: Bool { get }
var allowsNetworkAssetDownload: Bool { get }
}
```

### Quy tắc ban đầu

```text
Metadata scan:
```

- `concurrency thấp đến vừa`

`Thumbnail request:`

- `chỉ prefetch gần viewport`

`Vision analysis:`

- `1–2 ảnh đồng thời`

`Original download:`

- `chỉ theo hành động người dùng hoặc upload queue`

---

# 14. iCloud Asset Policy

Không phải ảnh nào cũng có file gốc nằm trên thiết bị.

Cần phân biệt:

```text
localAvailable
cloudAvailable
downloadRequired
downloadFailed
unknown
```

### Quy tắc

Trong Discovery:

- ưu tiên metadata;

- cho phép thumbnail mạng nếu người dùng đồng ý;

- không tự tải hàng nghìn ảnh gốc;

- không ngăn tạo candidate chỉ vì ảnh gốc chưa local.

Trong Album Draft:

- đánh dấu ảnh cần tải;

- cho người dùng biết dung lượng dự kiến;

- chỉ tải những ảnh được chọn cuối cùng.

---

# 15. Privacy Architecture

## 15.1. Privacy boundary

```text
On-device private zone
```

- `asset metadata`
- `event clusters`
- `thumbnails`
- `feature prints`
- `face observations`
- `dismissed suggestions`
- `user preferences`

`Nizi cloud zone`

- `album metadata được xác nhận`
- `ảnh được người dùng chọn upload`
- `ảnh render hoặc sản phẩm photobook`
- `dữ liệu chia sẻ do người dùng chủ động tạo`

---

## 15.2. Không upload ngầm

Mọi hành động upload phải thuộc một trong các trường hợp:

- người dùng bấm tạo album;

- người dùng bật đồng bộ album;

- người dùng yêu cầu backup;

- người dùng chia sẻ album;

- người dùng yêu cầu AI cloud xử lý một nhóm ảnh cụ thể.

---

## 15.3. Xóa dữ liệu khảo sát

Phải có chức năng:

> Xóa dữ liệu khám phá trên thiết bị

Chức năng này xóa:

- Local Memory Index;

- EventCandidate;

- quality score;

- similarity group;

- cache thumbnail;

- dữ liệu phân tích;

- lịch sử đề xuất.

Không xóa ảnh trong Apple Photos.

---

# 16. Presentation Architecture

## 16.1. Các màn hình chính

```text
D0 — Discovery Onboarding
D1 — Permission State
D2 — Initial Library Scan
D3 — Memory Discovery Home
D4 — Timeline Explorer
D5 — Event Candidate Detail
D6 — Similar Photo Review
D7 — Album Draft Review
D8 — Upload Preparation
D9 — Discovery Settings
```

---

## 16.2. D0 — Onboarding

Thông điệp:

> Nizi giúp bạn tìm lại các chuyến đi, sự kiện và khoảnh khắc đáng nhớ từ thư viện ảnh trên iPhone.

Ba cam kết:

- Phân tích trên thiết bị.

- Không tự động upload ảnh.

- Bạn luôn là người quyết định.

CTA:

> Khám phá thư viện ảnh

Không xin quyền ngay khi app vừa mở lần đầu. Chỉ xin sau khi đã giải thích giá trị.

---

## 16.3. D2 — Initial Scan

Hiển thị:

```text
Đang khám phá thư viện của bạn
```

`Đã khảo sát: 12.450 / 28.300 ảnh
Đã tìm thấy: 46 sự kiện tiềm năng
Hiện đang xử lý: Ảnh từ năm 2022`

Người dùng có thể:

- tiếp tục dùng app;

- tạm dừng;

- chỉ khảo sát một số năm;

- dừng hoàn toàn.

---

## 16.4. D3 — Discovery Home

Các khối:

```text
Tiếp tục khám phá
Đề xuất mới
Các năm
Các chuyến đi
Gia đình
Ngày này năm xưa
Album đang chuẩn bị
```

Không nên hiển thị hàng trăm đề xuất cùng lúc.

Mỗi lần chỉ nên đưa ra một số đề xuất tốt nhất.

---

## 16.5. Event Candidate Card

Ví dụ:

```text
Đà Nẵng & Hội An
08–11/06/2024
```

`186 ảnh · 4 ngày · 3 địa điểm
Nizi đã chọn trước 42 ảnh nổi bật`

`[Xem lại] [Để sau]`

---

## 16.6. Event Detail

Các phần:

- tiêu đề đề xuất;

- khoảng thời gian;

- bản đồ hoặc tên khu vực;

- các session;

- ảnh nổi bật;

- ảnh tương tự;

- ảnh chất lượng thấp;

- số lượng ảnh đề xuất;

- nút tạo album.

Người dùng có thể:

- chọn tất cả;

- chỉ chọn ảnh nổi bật;

- sửa selection;

- đổi cover;

- tách ngày;

- gộp session;

- bỏ qua sự kiện.

---

# 17. Use Cases

## UC-01 — Request Photo Access

```text
User chọn Khám phá thư viện
→ app giải thích quyền riêng tư
→ yêu cầu quyền
→ nhận trạng thái
→ chuyển sang scan hoặc limited state
```

## UC-02 — Initial Metadata Scan

```text
Fetch assets theo batch
→ normalize
→ lưu LocalAsset
→ cập nhật tiến độ
→ tạo checkpoint
→ chạy event discovery sơ bộ
```

## UC-03 — Discover Events

```text
Load unclustered assets
→ temporal segmentation
→ spatial clustering
→ build sessions
→ merge events
→ score candidates
→ lưu EventCandidate
```

## UC-04 — Analyze Candidate

```text
User mở candidate
→ lấy thumbnail
→ quality analysis
→ similarity grouping
→ cover selection
→ cập nhật candidate
```

## UC-05 — Convert to Album Draft

```text
User chấp nhận candidate
→ tạo AlbumDraft
→ copy asset reference
→ user review
→ kiểm tra asset availability
→ chuẩn bị upload
```

## UC-06 — Incremental Library Update

```text
PhotoKit báo thay đổi
→ xác định insert/update/delete
→ cập nhật index
→ tính lại cluster bị ảnh hưởng
→ tạo hoặc cập nhật suggestion
```

---

# 18. Application Use Cases

```swift
protocol ScanPhotoLibraryUseCase {
func execute(mode: ScanMode) async throws
}
```

`protocol DiscoverEventsUseCase {
func execute(scope: DiscoveryScope) async throws
}`

`protocol AnalyzeEventCandidateUseCase {
func execute(candidateID: String) async throws
}`

`protocol ConvertCandidateToAlbumDraftUseCase {
func execute(candidateID: String) async throws -> AlbumDraft
}`

`protocol SynchronizePhotoLibraryChangesUseCase {
func execute(changeSet: PhotoLibraryChangeSet) async throws
}`

---

# 19. Folder Structure

```text
Nizi/
└── Features/
└── MemoryDiscovery/
├── Presentation/
│   ├── Screens/
│   ├── Components/
│   ├── ViewModels/
│   └── Navigation/
│
├── Application/
│   ├── UseCases/
│   ├── Coordinators/
│   └── DTOs/
│
├── Domain/
│   ├── Entities/
│   ├── ValueObjects/
│   ├── Repositories/
│   ├── Services/
│   └── Rules/
│
├── Infrastructure/
│   ├── PhotoKit/
│   ├── Vision/
│   ├── Persistence/
│   ├── Geocoding/
│   ├── BackgroundTasks/
│   └── Cache/
│
└── Tests/
├── Unit/
├── Integration/
├── Performance/
└── Fixtures/
```

---

# 20. Repository Interfaces

```swift
protocol LocalAssetRepository {
func upsert(_ assets: [LocalAsset]) async throws
func fetchUnclustered(limit: Int) async throws -> [LocalAsset]
func fetch(ids: [String]) async throws -> [LocalAsset]
func markUnavailable(ids: [String]) async throws
}
```

`protocol EventCandidateRepository {
func save(_ candidate: EventCandidate) async throws
func fetchSuggestions(limit: Int) async throws -> [EventCandidate]
func updateStatus(
id: String,
status: EventCandidateStatus
) async throws
}`

`protocol AlbumDraftRepository {
func create(from candidate: EventCandidate) async throws -> AlbumDraft
func update(_ draft: AlbumDraft) async throws
}`

---

# 21. State Management

Không để một ViewModel khổng lồ quản lý toàn bộ module.

Nên chia:

```text
DiscoveryPermissionViewModel
LibraryScanViewModel
DiscoveryHomeViewModel
EventCandidateViewModel
SimilarPhotosViewModel
AlbumDraftViewModel
```

Một `DiscoveryCoordinator` quản lý navigation và luồng liên màn hình.

---

# 22. Error Handling

Các nhóm lỗi:

```swift
enum DiscoveryError {
case permissionDenied
case permissionLimited
case photoLibraryUnavailable
case assetUnavailable
case iCloudDownloadRequired
case iCloudDownloadFailed
case databaseFailure
case analysisFailed
case scanInterrupted
case insufficientStorage
}
```

Nguyên tắc:

- lỗi một ảnh không được làm hỏng toàn bộ scan;

- ghi lại asset lỗi;

- retry có giới hạn;

- bỏ qua được;

- không lặp vô hạn;

- thông báo thân thiện;

- lưu technical log nội bộ.

---

# 23. Logging và Observability

Log các sự kiện kỹ thuật:

```text
permission_requested
permission_granted_full
permission_granted_limited
scan_started
scan_batch_completed
scan_paused
scan_resumed
scan_completed
candidate_created
candidate_viewed
candidate_dismissed
candidate_accepted
album_draft_created
asset_analysis_failed
icloud_download_failed
```

Không log:

- tọa độ chính xác;

- nội dung ảnh;

- tên người;

- embedding;

- thumbnail;

- metadata nhạy cảm.

---

# 24. Metrics sản phẩm

Các metric cần theo dõi:

```text
Tỷ lệ người cấp Full Access
Tỷ lệ hoàn thành lần quét đầu
Thời gian đến đề xuất đầu tiên
Số candidate trung bình mỗi người
Tỷ lệ mở candidate
Tỷ lệ chấp nhận candidate
Tỷ lệ candidate chuyển thành album
Số ảnh ban đầu / số ảnh cuối cùng
Tỷ lệ ảnh phải tải từ iCloud
Tỷ lệ bỏ ứng dụng trong lúc scan
```

Metric quan trọng nhất:

> Từ lúc cấp quyền đến lúc người dùng nhìn thấy một đề xuất album có ý nghĩa mất bao lâu?

Không nhất thiết phải quét toàn bộ thư viện trước khi hiển thị đề xuất đầu tiên.

---

# 25. Performance Targets

Các mục tiêu ban đầu cần kiểm thử trên thiết bị thật:

```text
Thư viện 10.000 ảnh:
```

- `UI không khóa`
- `có kết quả đầu tiên sớm`
- `scan có thể pause/resume`

`Thư viện 50.000 ảnh:`

- `không giữ toàn bộ thumbnail trong RAM`
- `không crash do memory`
- `không tải ảnh gốc hàng loạt`

`Scroll:`

- `thumbnail request được hủy khi cell biến mất`
- `prefetch có giới hạn`
- `không giữ UIImage trong entity hoặc database`

Không ghi cam kết thời gian tuyệt đối trước khi benchmark.

---

# 26. Testing Strategy

## 26.1. Unit tests

Kiểm thử:

- temporal segmentation;

- distance calculation;

- session boundary;

- event merging;

- event scoring;

- duplicate grouping;

- status transition;

- permission mapping;

- scan checkpoint.

## 26.2. Synthetic library tests

Tạo fixture metadata:

```text
Một chuyến đi 4 ngày
Sinh nhật 3 giờ
Ảnh hàng ngày kéo dài 6 tháng
Ảnh không GPS
Ảnh sai thời gian
Ảnh từ nhiều múi giờ
Screenshot dày đặc
Burst 50 ảnh
```

## 26.3. Device tests

Bắt buộc test trên:

- iPhone cấu hình thấp;

- iPhone mới;

- thư viện nhỏ;

- thư viện 20.000–50.000 ảnh;

- iCloud Optimize Storage;

- Full Access;

- Limited Access;

- quyền bị thu hồi;

- pin yếu;

- Low Power Mode;

- mạng yếu;

- app vào background;

- app bị đóng giữa scan.

## 26.4. Privacy tests

- không upload trước xác nhận;

- xóa index hoạt động đúng;

- Limited Access không đọc asset ngoài quyền;

- log không chứa GPS hoặc nội dung ảnh;

- cache được xóa;

- quyền bị thu hồi được phản ánh ngay.

---

# 27. Development Phases

## Phase 1 — Photo Library Foundation

Mục tiêu:

- xin quyền;

- fetch `PHAsset`;

- đọc metadata;

- lưu LocalAsset;

- hiển thị timeline thumbnail;

- scan theo batch;

- pause/resume;

- theo dõi thay đổi thư viện.

Chưa làm AI.

### Kết quả

Người dùng có thể duyệt ảnh nhiều năm trong Nizi mà không upload ảnh.

---

## Phase 2 — Metadata Event Discovery

Mục tiêu:

- temporal segmentation;

- spatial clustering;

- session;

- event candidate;

- title cơ bản theo ngày và địa điểm;

- giao diện suggestion;

- accept/dismiss;

- tạo AlbumDraft.

### Kết quả

Nizi có thể đề xuất:

> Chuyến đi Đà Nẵng, tháng 6 năm 2024.

---

## Phase 3 — Photo Quality and Similarity

Mục tiêu:

- thumbnail analysis;

- blur và exposure;

- feature print;

- near-duplicate;

- burst selection;

- chọn cover;

- đề xuất ảnh nổi bật.

### Kết quả

Nizi có thể rút 186 ảnh xuống khoảng 40–60 ảnh đáng xem.

---

## Phase 4 — Smart Curation

Mục tiêu:

- people presence;

- scene balance;

- visual diversity;

- album storytelling;

- cân bằng ảnh người, địa điểm và chi tiết;

- tránh ảnh lặp;

- bố cục album sơ bộ.

### Kết quả

Nizi không chỉ gom ảnh mà còn tạo một bộ ảnh có câu chuyện.

---

## Phase 5 — Personalization

Mục tiêu:

- học từ ảnh người dùng giữ hoặc bỏ;

- học loại sự kiện người dùng quan tâm;

- điều chỉnh số lượng ảnh;

- học sở thích cover;

- tránh đề xuất những nội dung đã bị từ chối.

### Kết quả

Hai người dùng có cùng thư viện mẫu nhưng nhận được đề xuất khác nhau.

---

# 28. MVP đề xuất

MVP không nên bao gồm toàn bộ nội dung trong tài liệu này.

MVP nên dừng ở:

```text
1. Photo permission
```

 2. `Metadata index`
 3. `Batch scan và checkpoint`
 4. `Timeline theo năm/tháng`
 5. `Time-based clustering`
 6. `Location-based clustering cơ bản`
 7. `EventCandidate`
 8. `Candidate review`
 9. `Chọn thủ công ảnh`
10. `Convert sang AlbumDraft`
11. `Chỉ upload ảnh được xác nhận`
12. `Incremental update`

Chưa cần trong MVP:

- nhận diện người;

- cloud AI;

- personalized learning;

- storytelling phức tạp;

- tự động thiết kế photobook;

- semantic search toàn thư viện;

- đồng bộ index nhiều thiết bị.

---

# 29. Các quyết định kiến trúc quan trọng

## ADR-MD-001

**Memory Discovery là module độc lập.**

Album Management không truy cập PhotoKit trực tiếp.

## ADR-MD-002

**Local-first và metadata-first.**

Không upload thư viện để khảo sát.

## ADR-MD-003

**Không lưu toàn bộ thumbnail.**

Dùng PhotoKit caching và disk cache giới hạn.

## ADR-MD-004

**Clustering bằng quy tắc trước, AI sau.**

MVP ưu tiên thuật toán có thể giải thích và kiểm thử.

## ADR-MD-005

**Mọi scan phải resumable.**

Không có quy trình nào phụ thuộc việc app phải chạy liên tục đến khi hoàn thành.

## ADR-MD-006

**EventCandidate không phải Album.**

Chỉ khi người dùng xác nhận mới tạo AlbumDraft.

## ADR-MD-007

**Không nhận diện danh tính trong MVP.**

Chỉ phát hiện sự hiện diện và chất lượng gương mặt nếu cần.

## ADR-MD-008

**Original asset chỉ được yêu cầu ở bước cuối.**

Discovery không tải ảnh gốc hàng loạt.

---

# 30. Định nghĩa hoàn thành module nền tảng

Module nền tảng được coi là hoàn thành khi:

- người dùng cấp được Full hoặc Limited Access;

- app khảo sát được thư viện lớn theo batch;

- scan có thể dừng và tiếp tục;

- app không upload ảnh trong quá trình khảo sát;

- metadata được lưu cục bộ;

- thư viện thay đổi được cập nhật incremental;

- ảnh được gom thành session;

- session được gom thành EventCandidate;

- người dùng có thể mở, bỏ qua hoặc chấp nhận candidate;

- candidate có thể chuyển thành AlbumDraft;

- chỉ những ảnh trong AlbumDraft được chuẩn bị upload;

- cache và dữ liệu khảo sát có thể xóa;

- ứng dụng không crash khi có hàng chục nghìn asset;

- Limited Access được xử lý đúng và minh bạch.

---

# 31. Tuyên bố sản phẩm

> Memory Discovery giúp Nizi hiểu cấu trúc của thư viện ảnh trên iPhone mà không lấy quyền sở hữu thư viện đó.

> Nizi không yêu cầu người dùng mang toàn bộ ảnh lên hệ thống. Nizi khảo sát trên thiết bị, phát hiện những cụm ký ức có ý nghĩa và chỉ đưa các ảnh được người dùng lựa chọn vào quy trình tạo album.

> Giá trị của module không nằm ở việc tìm thấy nhiều ảnh nhất, mà ở việc giúp người dùng nhìn lại đúng những khoảnh khắc đáng nhớ và biến chúng thành một câu chuyện có thể lưu giữ lâu dài.