

# SPEC — Album Planner Completion

## 1. Mục tiêu

Hoàn thiện Album Draft Planner hiện có bằng ba phần còn thiếu:

1. **Photo Location & Place Resolver**
2. **Photo Importance**
3. **Planning Log**

Đồng thời bổ sung metadata cần thiết cho:

* Album Draft
* Spread
* Page
* Source Event

Mục tiêu không phải mở rộng thành AI Photobook hoàn chỉnh. Đây là bước củng cố nền tảng để:

* Album có tên địa danh thực tế;
* Planner biết ảnh nào quan trọng hơn;
* Có thể giải thích vì sao chọn ảnh bìa, layout và assignment;
* Sau này thay thuật toán heuristic bằng AI mà không phải đổi kiến trúc.

---

# 2. Phạm vi

Triển khai:

* Lấy GPS từ `PHAsset.location`.
* Gom các tọa độ gần nhau thành location cluster.
* Reverse geocoding bằng Apple Core Location.
* Cache kết quả địa danh.
* Bổ sung `PhotoPlace`.
* Đưa place metadata vào planning input và Album Draft.
* Bổ sung `importanceScore` cho ảnh.
* Dùng importance trong cover selection, hero assignment và layout scoring.
* Tạo Planning Log có cấu trúc.
* Lưu metadata chính của Spread và Page.
* Cập nhật Preview để hiển thị place, importance và log.
* Bổ sung unit tests.

Không triển khai:

* AI nhận diện cảnh vật.
* Visual Look Up.
* Face recognition.
* Blur detection.
* Cloud geocoding.
* Google Maps API.
* Map UI.
* Chỉnh sửa vị trí thủ công.
* Tạo địa danh từ nội dung ảnh khi ảnh không có GPS.
* Layout Editor.
* Album Editor.
* Export PDF.
* Migration sang relational page store đầy đủ.

---

# 3. Kiến trúc hoàn chỉnh

Pipeline sau khi hoàn thiện:

```text
PHAsset
    ↓
Planning Photo Adapter
    ├── dimensions
    ├── creation date
    ├── favorite
    ├── location
    └── metadata
    ↓
Location Clusterer
    ↓
Place Resolver
    ↓
Photo Importance Evaluator
    ↓
Album Draft Planner
    ├── cover selection
    ├── event grouping
    ├── spread building
    ├── layout pair selection
    ├── photo-slot assignment
    └── planning log
    ↓
Album Draft
    ↓
Layout Renderer
```

Giữ rõ ranh giới:

```text
Location module
→ chỉ xử lý tọa độ và địa danh

Importance module
→ chỉ chấm điểm ảnh

Planner
→ dùng dữ liệu đã chuẩn bị để tạo Draft

Renderer
→ chỉ hiển thị Draft
```

---

# 4. Module 1 — Photo Location & Place Resolver

## 4.1 Mục tiêu

Lấy tên địa danh từ GPS metadata của ảnh.

Nguồn tọa độ ưu tiên:

```swift
PHAsset.location
```

Không tự đọc file ảnh gốc chỉ để lấy GPS nếu `PHAsset.location` đã có.

Không phân tích nội dung ảnh để đoán địa điểm.

---

## 4.2 Cấu trúc thư mục

```text
Features/
└── PhotoLocation/
    ├── Domain/
    │   ├── PhotoCoordinate.swift
    │   ├── PhotoPlace.swift
    │   ├── PhotoLocationCluster.swift
    │   └── PhotoLocationError.swift
    │
    ├── Application/
    │   ├── PhotoLocationClustering.swift
    │   ├── PhotoPlaceResolving.swift
    │   ├── PhotoPlaceDisplayNameBuilder.swift
    │   └── PhotoLocationEnricher.swift
    │
    ├── Infrastructure/
    │   ├── ApplePhotoPlaceResolver.swift
    │   └── InMemoryPhotoPlaceCache.swift
    │
    └── Tests/
        ├── PhotoLocationClustererTests.swift
        ├── PhotoPlaceDisplayNameBuilderTests.swift
        └── PhotoLocationEnricherTests.swift
```

Có thể điều chỉnh theo cấu trúc project hiện tại.

---

## 4.3 Domain model

### PhotoCoordinate

```swift
struct PhotoCoordinate: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
}
```

Validation:

```text
-90...90 latitude
-180...180 longitude
```

### PhotoPlace

```swift
struct PhotoPlace: Codable, Hashable, Sendable {
    let coordinate: PhotoCoordinate

    let name: String?
    let subLocality: String?
    let locality: String?
    let subAdministrativeArea: String?
    let administrativeArea: String?
    let country: String?
    let isoCountryCode: String?

    let displayName: String
}
```

Ý nghĩa:

```text
name
→ điểm cụ thể nếu Apple trả về

subLocality
→ phường, khu vực nhỏ hoặc district

locality
→ thành phố

administrativeArea
→ tỉnh, bang

country
→ quốc gia
```

Không giả định mọi quốc gia đều có cùng cấu trúc hành chính.

### PhotoLocationCluster

```swift
struct PhotoLocationCluster: Identifiable, Sendable {
    let id: String
    let representativeCoordinate: PhotoCoordinate
    let photoIds: [String]
}
```

---

## 4.4 Clustering

Tạo protocol:

```swift
protocol PhotoLocationClustering {
    func clusters(
        from photos: [AlbumPlanningPhoto],
        maximumDistance: CLLocationDistance
    ) -> [PhotoLocationCluster]
}
```

Ngưỡng mặc định:

```text
100 mét
```

Hai ảnh nằm trong khoảng cách dưới hoặc bằng 100 mét được ưu tiên nằm cùng cluster.

Yêu cầu:

* ảnh không có tọa độ không tham gia clustering;
* mỗi photo ID chỉ thuộc tối đa một cluster;
* kết quả deterministic;
* thứ tự cluster theo thời gian ảnh đại diện, sau đó lexical ID;
* không cần thuật toán clustering phức tạp;
* số ảnh trong một Event thường nhỏ nên greedy clustering chấp nhận được.

Có thể dùng:

```swift
CLLocation.distance(from:)
```

Không tự viết công thức khoảng cách nếu không cần thiết.

---

## 4.5 Reverse geocoding

Protocol:

```swift
protocol PhotoPlaceResolving: Sendable {
    func resolvePlace(
        for coordinate: PhotoCoordinate
    ) async throws -> PhotoPlace
}
```

Implementation:

```text
ApplePhotoPlaceResolver
```

Dùng Apple Core Location reverse geocoding.

Không để Planner phụ thuộc trực tiếp vào `CLGeocoder`.

### Error handling

```swift
enum PhotoLocationError: Error {
    case invalidCoordinate
    case placeNotFound
    case geocodingFailed
}
```

Nếu reverse geocoding thất bại:

* không làm hỏng toàn bộ Album creation;
* trả `nil` place cho cluster đó;
* ghi log warning;
* tiếp tục tạo Album.

---

## 4.6 Cache

Không geocode lại các tọa độ gần như giống nhau.

Tạo:

```swift
protocol PhotoPlaceCaching: Sendable {
    func place(for key: PhotoPlaceCacheKey) async -> PhotoPlace?
    func store(_ place: PhotoPlace, for key: PhotoPlaceCacheKey) async
}
```

Cache key nên dùng bucket tọa độ, không dùng trực tiếp `Double`.

Ví dụ:

```swift
struct PhotoPlaceCacheKey: Hashable, Codable, Sendable {
    let latitudeBucket: Int
    let longitudeBucket: Int
}
```

Có thể làm tròn khoảng:

```text
4 chữ số thập phân
```

Mức này chỉ dùng cache, không dùng làm cluster chính xác.

Sprint này có thể dùng in-memory cache.

Không cần persistence nếu làm tăng phạm vi đáng kể.

Kiến trúc phải cho phép thay bằng persistent cache sau.

---

## 4.7 Display name

Tạo builder riêng:

```swift
struct PhotoPlaceDisplayNameBuilder {
    func makeDisplayName(
        name: String?,
        subLocality: String?,
        locality: String?,
        administrativeArea: String?,
        country: String?
    ) -> String
}
```

Quy tắc:

1. Loại bỏ chuỗi rỗng.
2. Loại bỏ giá trị trùng.
3. Ưu tiên địa điểm cụ thể.
4. Giữ tối đa 2 phần cho UI chính.
5. Không tạo dấu phẩy thừa.

Ví dụ:

```text
Sydney Opera House + Sydney
→ Sydney Opera House, Sydney
```

```text
Hà Nội + Hà Nội + Việt Nam
→ Hà Nội, Việt Nam
```

```text
nil + Sydney + Australia
→ Sydney, Australia
```

Nếu không có gì:

```text
displayName = ""
```

Không dùng `"Unknown Location"` trong domain.

UI tự quyết định fallback localization.

---

## 4.8 PhotoLocationEnricher

Tạo service điều phối:

```swift
protocol PhotoLocationEnriching {
    func enrich(
        photos: [AlbumPlanningPhoto]
    ) async -> PhotoLocationEnrichmentResult
}
```

Output:

```swift
struct PhotoLocationEnrichmentResult {
    let photos: [AlbumPlanningPhoto]
    let resolvedPlaces: [PhotoPlace]
    let warnings: [AlbumPlanningLogEntry]
}
```

Luồng:

```text
lọc ảnh có coordinate
→ cluster
→ kiểm tra cache
→ reverse geocode cluster chưa có
→ gán PhotoPlace cho tất cả ảnh trong cluster
→ trả ảnh đã enrich
```

Không gọi reverse geocoding cho từng ảnh nếu chúng cùng cluster.

---

# 5. Cập nhật AlbumPlanningPhoto

Mở rộng model hiện tại:

```swift
struct AlbumPlanningPhoto: Identifiable, Hashable, Sendable {
    let id: String
    let eventId: String

    let creationDate: Date?

    let pixelWidth: Int
    let pixelHeight: Int

    let coordinate: PhotoCoordinate?
    var place: PhotoPlace?

    let isFavorite: Bool
    let isEdited: Bool

    let burstIdentifier: String?
    let originalFilename: String?
    let exif: AlbumPhotoEXIF?

    var importance: PhotoImportance
}
```

Nếu hiện tại đang dùng `latitude` và `longitude` riêng lẻ, được phép migration sang `PhotoCoordinate?`.

Không lưu đồng thời hai cách biểu diễn nếu không cần.

---

# 6. Module 2 — Photo Importance

## 6.1 Mục tiêu

Tạo một lớp đánh giá mức độ quan trọng của ảnh.

Phiên bản hiện tại chỉ dùng heuristic metadata.

Sau này có thể thay bằng AI hoặc Vision mà không sửa Planner.

---

## 6.2 Domain model

```swift
struct PhotoImportance: Codable, Hashable, Sendable {
    let totalScore: Double
    let reasons: [PhotoImportanceReason]
}
```

```swift
enum PhotoImportanceReason: Codable, Hashable, Sendable {
    case favorite(Double)
    case resolution(Double)
    case edited(Double)
    case timelinePosition(Double)
    case orientation(Double)
    case hasLocation(Double)
}
```

Nếu enum associated values gây khó encode, có thể dùng:

```swift
struct PhotoImportanceReason: Codable, Hashable, Sendable {
    let code: String
    let score: Double
}
```

Ưu tiên cấu trúc ổn định cho persistence.

---

## 6.3 Evaluator

```swift
protocol PhotoImportanceEvaluating: Sendable {
    func evaluate(
        photos: [AlbumPlanningPhoto]
    ) -> [String: PhotoImportance]
}
```

Implementation:

```text
DefaultPhotoImportanceEvaluator
```

### Scoring ban đầu

Dùng các tiêu chí hiện có, nhưng tách khỏi Cover Selector.

```text
Favorite:
+30

Resolution normalized:
0...25

Edited:
+5

Timeline middle 20–80%:
+10

Orientation:
landscape +15
square +12
portrait +8

Has resolved place:
+3
```

Tổng điểm không bắt buộc chuẩn hóa về 100.

Điểm phải deterministic.

### Resolution normalization

Trong chính tập ảnh cần plan:

```text
score = photoPixelCount / maxPixelCount × 25
```

Nếu `maxPixelCount == 0`, cho 0.

### Timeline position

Chỉ dùng ảnh có date.

Nếu không đủ dữ liệu timeline:

```text
0 điểm
```

Không trừ điểm.

---

## 6.4 Cover Selector refactor

Hiện Cover Selector đang tự tính các tiêu chí tương tự.

Refactor để dùng:

```swift
photo.importance.totalScore
```

Cover selection:

1. importance cao nhất;
2. resolution cao hơn;
3. creation date sớm hơn;
4. lexical ID.

Không tính scoring lần thứ hai trong Cover Selector.

Cover Selector chỉ chọn từ importance đã có.

---

## 6.5 Hero assignment

Trong `AlbumPhotoSlotAssigner`, khi slot có:

```text
role == hero
```

thêm bonus dựa trên:

```swift
photo.importance.totalScore
```

Khuyến nghị normalization trong phạm vi Page hoặc Spread:

```text
0...20 bonus
```

Không để importance vượt qua orientation mismatch nghiêm trọng.

Quy tắc:

```text
orientation compatibility
→ tiêu chí chính

importance
→ tie breaker hoặc secondary score
```

Ảnh portrait rất quan trọng không nên tự động bị ép vào khung landscape nếu có khung portrait phù hợp khác.

---

## 6.6 Layout pair scoring

Layout pair selector dùng importance để đánh giá:

* ảnh quan trọng có slot hero phù hợp không;
* ảnh quan trọng có bị đẩy vào slot orientation xấu không;
* hai trang có phân bố hero hợp lý không.

Không cần thêm AI logic.

---

# 7. Module 3 — Planning Log

## 7.1 Mục tiêu

Ghi lại các quyết định chính của Planner bằng dữ liệu có cấu trúc.

Log phục vụ:

* debug;
* Preview;
* kiểm tra thuật toán;
* giải thích kết quả;
* tuning scoring;
* chuẩn bị cho analytics.

Không dùng chuỗi tự do làm nguồn dữ liệu chính.

---

## 7.2 Domain model

```swift
struct AlbumPlanningLog: Codable, Hashable, Sendable {
    var entries: [AlbumPlanningLogEntry]
}
```

```swift
struct AlbumPlanningLogEntry: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let stage: AlbumPlanningStage
    let level: AlbumPlanningLogLevel

    let subjectId: String?
    let code: String
    let message: String

    let metadata: [String: String]
}
```

```swift
enum AlbumPlanningStage: String, Codable, Sendable {
    case input
    case location
    case importance
    case cover
    case grouping
    case spread
    case layoutSelection
    case assignment
    case validation
    case persistence
}
```

```swift
enum AlbumPlanningLogLevel: String, Codable, Sendable {
    case info
    case warning
    case error
}
```

`message` phục vụ debug.

`code` và `metadata` phục vụ logic ổn định.

Không parse lại message để lấy dữ liệu.

---

## 7.3 Log bắt buộc

### Input

```text
selected_photos_received
events_received
missing_dates_count
missing_locations_count
```

### Location

```text
location_clusters_created
place_resolved
place_cache_hit
place_resolution_failed
```

### Importance

```text
importance_evaluated
```

Metadata:

```text
photoId
totalScore
topReasons
```

### Cover

```text
cover_selected
```

Metadata:

```text
photoId
score
orientation
resolution
favorite
place
```

### Grouping

```text
singleton_event_merged
event_group_created
```

### Spread

```text
spread_created
large_event_split
```

Metadata:

```text
photoCount
sourceEventIds
orientationSummary
```

### Layout selection

```text
layout_pair_selected
```

Metadata:

```text
spreadId
leftLayoutId
rightLayoutId
partition
score
orientationScore
balanceScore
heroScore
varietyPenalty
```

### Assignment

```text
photo_assigned_to_slot
```

Metadata:

```text
photoId
pageId
layoutId
slotId
photoOrientation
slotOrientation
assignmentScore
```

### Validation

```text
draft_validation_succeeded
draft_validation_failed
```

---

## 7.4 Planning result

Thay vì Planner chỉ trả `AlbumDraft`, tạo:

```swift
struct AlbumPlanningResult {
    let draft: AlbumDraft
    let log: AlbumPlanningLog
}
```

Protocol:

```swift
protocol AlbumDraftPlanning {
    func createDraft(
        from input: AlbumPlanningInput
    ) async throws -> AlbumPlanningResult
}
```

Nếu không muốn đổi protocol hiện có quá rộng, có thể tạo overload mới nhưng tránh duplicate logic.

---

# 8. Bổ sung metadata cho Album Draft

## 8.1 AlbumDraft

Bổ sung:

```swift
struct AlbumDraft {
    // existing fields

    var primaryPlace: PhotoPlace?
    var totalPhotoCount: Int

    var planningVersion: Int
    var planningLog: AlbumPlanningLog?
}
```

Dùng:

```text
planningVersion = 1
```

Mục đích để sau này biết Album được tạo bởi phiên bản Planner nào.

---

## 8.2 AlbumSourceEvent

Mở rộng:

```swift
struct AlbumSourceEvent {
    let id: String
    let title: String?

    let selectedPhotoCount: Int

    let startDate: Date?
    let endDate: Date?

    let place: PhotoPlace?
}
```

Không lưu lại toàn bộ ảnh trong source event metadata.

---

## 8.3 AlbumDraftSpread

Bổ sung:

```swift
struct AlbumDraftSpread {
    // existing fields

    let photoCount: Int
    let orientationSummary: AlbumPhotoOrientationSummary
    let primaryPlace: PhotoPlace?
    let heroPhotoId: String?
    let planningScore: Double?
}
```

`heroPhotoId` của Spread:

* ảnh được gán vào hero slot có importance cao nhất;
* nếu không có hero slot, ảnh importance cao nhất trong Spread.

---

## 8.4 AlbumDraftPage

Bổ sung:

```swift
struct AlbumDraftPage {
    // existing fields

    let heroPhotoId: String?
    let primaryPlace: PhotoPlace?

    let layoutScore: Double?
    let assignmentScore: Double?
}
```

Không bắt buộc UI production hiển thị các score.

Chúng dùng cho Preview và debug.

---

# 9. Xác định primary place

## 9.1 Photo

Photo dùng place được resolve từ location cluster.

## 9.2 Page

Chọn place xuất hiện nhiều nhất trong ảnh của Page.

Tie breaker:

1. Place của hero photo.
2. Place của ảnh có importance cao hơn.
3. Display name lexical order.

## 9.3 Spread

Chọn place xuất hiện nhiều nhất trong toàn Spread.

Tie breaker tương tự Page.

## 9.4 Album

Ưu tiên:

1. Place xuất hiện nhiều nhất trong toàn bộ ảnh.
2. Place của cover photo.
3. Place của Event chính.
4. `nil`.

Không dùng location của một ảnh đơn lẻ nếu đa số Album ở địa điểm khác.

---

# 10. Tích hợp vào Create Album

Luồng mới:

```text
Create Album
    ↓
Build AlbumPlanningInput từ PHAsset
    ↓
LocationEnricher.enrich
    ↓
ImportanceEvaluator.evaluate
    ↓
Gán place + importance vào planning photos
    ↓
AlbumDraftPlanner.createDraft
    ↓
Save draft + planning log
    ↓
Open AlbumDraftResultView
```

Không load full-resolution image.

Chỉ dùng metadata.

---

# 11. Concurrency

Yêu cầu:

* reverse geocoding không chạy trên main actor;
* importance evaluation không cần main actor;
* planner không cần main actor;
* UI state update trên main actor;
* tránh gọi nhiều geocoder request song song không kiểm soát.

Có thể resolve lần lượt từng cluster hoặc giới hạn concurrency thấp.

Không cần xây queue phức tạp.

Nếu geocoding lâu:

```text
Creating album…
```

vẫn giữ nguyên.

Không cần progress chi tiết.

---

# 12. SwiftData persistence

Hiện Draft đang encode thành JSON trong một row.

Sprint này được phép giữ cách đó.

Cần đảm bảo các model mới đều `Codable`.

Bổ sung flat columns nếu hữu ích:

```text
primaryPlaceName
totalPhotoCount
planningVersion
```

Không bắt buộc relational migration.

Nếu schema thay đổi, xử lý migration an toàn theo cơ chế hiện có.

Không xóa dữ liệu Draft cũ một cách im lặng.

---

# 13. Preview

Cập nhật `AlbumDraftPlanningPreview`.

Mỗi case phải hiển thị:

* cover photo;
* cover importance score;
* primary place;
* source Events;
* số Spread;
* mỗi Spread:

  * photo count;
  * orientation summary;
  * primary place;
  * hero photo;
  * planning score;
* mỗi Page:

  * layout ID;
  * hero photo ID;
  * page place;
  * layout score;
  * assignment score;
* Planning Log.

Planning Log có thể dùng `DisclosureGroup`.

Group theo stage:

```text
Location
Importance
Cover
Spread
Layout Selection
Assignment
Validation
```

Không làm UI production phức tạp.

---

# 14. Diagnostics

Trong Diagnostics, bổ sung màn hình kiểm tra location resolver.

Ví dụ:

```text
Photo Location Diagnostics
```

Hiển thị:

* photo ID;
* coordinate;
* cluster ID;
* resolved display name;
* cache hit hoặc geocode;
* error nếu có.

Không hiển thị toàn bộ EXIF thô.

Không yêu cầu map.

---

# 15. Tests

## 15.1 Location cluster

* hai ảnh cách nhau dưới 100 m cùng cluster;
* hai ảnh cách xa nhau khác cluster;
* ảnh không có coordinate bị bỏ qua;
* không duplicate photo;
* kết quả deterministic.

## 15.2 Display name

* loại bỏ chuỗi trùng;
* không có dấu phẩy thừa;
* tối đa hai thành phần;
* fallback đúng khi thiếu `name`;
* hỗ trợ locality và country.

## 15.3 Place enricher

Dùng mock resolver:

* một cluster chỉ gọi resolver một lần;
* cache hit không gọi resolver;
* resolver failure không làm hỏng toàn bộ kết quả;
* tất cả ảnh trong cluster nhận cùng place;
* ảnh không tọa độ có place nil.

Không gọi geocoder thật trong unit tests.

## 15.4 Importance

* favorite cộng đúng điểm;
* resolution normalize đúng;
* landscape, square, portrait có điểm đúng;
* timeline middle có bonus;
* thiếu date không crash;
* kết quả deterministic;
* cùng input cho cùng output.

## 15.5 Cover selector

* sử dụng importance đã tính;
* không tự tính lại score cũ;
* tie breaker đúng;
* place không làm thay đổi tie breaker ngoài score đã định nghĩa.

## 15.6 Hero assignment

* ảnh importance cao ưu tiên hero khi orientation tương đương;
* orientation tốt vẫn thắng importance cao nhưng mismatch nặng;
* không duplicate assignment.

## 15.7 Primary place

* chọn place xuất hiện nhiều nhất;
* tie breaker theo hero photo;
* Album ưu tiên majority place trước cover place;
* no place trả nil.

## 15.8 Planning Log

* có log cover selected;
* có log spread created;
* có log layout pair selected;
* có log assignment;
* có validation success;
* geocoding failure tạo warning;
* log không ảnh hưởng kết quả scoring.

## 15.9 Persistence

* encode/decode Draft mới thành công;
* planning log encode/decode thành công;
* place encode/decode thành công;
* importance encode/decode thành công.

---

# 16. Acceptance criteria

Task hoàn thành khi:

1. Có module Photo Location riêng.
2. Adapter lấy `PHAsset.location`.
3. Ảnh gần nhau được gom cluster.
4. Mỗi cluster chỉ reverse geocode một lần.
5. Có cache place tối thiểu trong memory.
6. Reverse geocoding thất bại không làm hỏng Album creation.
7. `AlbumPlanningPhoto` có `place`.
8. Có `PhotoImportance`.
9. Importance được tính trước Planner.
10. Cover Selector dùng importance.
11. Hero assignment dùng importance.
12. Layout scoring dùng importance ở mức secondary.
13. Có `AlbumPlanningLog`.
14. Planner trả `AlbumPlanningResult`.
15. Log ghi cover, spread, layout và assignment.
16. Album Draft có `primaryPlace`.
17. Spread có place, orientation summary và hero photo.
18. Page có hero photo và place.
19. Có planning version.
20. Draft persistence vẫn hoạt động.
21. Preview hiển thị place, importance và log.
22. Diagnostics có location inspection.
23. Unit tests compile.
24. App build pass.
25. Không dùng AI.
26. Không dùng API bên thứ ba.
27. Không load bitmap full-resolution.
28. Không thay đổi Layout Renderer ngoài phần cần để đọc metadata mới.
29. Không triển khai Album Editor.
30. Không chạy simulator nếu người dùng chưa yêu cầu.

---

# 17. Quy tắc không được vi phạm

* Không đoán địa danh khi ảnh không có GPS.
* Không gọi reverse geocoder cho từng ảnh cùng vị trí.
* Không để geocoding failure làm mất ảnh.
* Không trộn geocoding logic vào Planner.
* Không trộn importance scoring vào Cover Selector.
* Không dùng random.
* Không để Planning Log quyết định logic.
* Không lưu chuỗi log làm dữ liệu business duy nhất.
* Không đưa `CLPlacemark` trực tiếp vào domain model.
* Không để domain model phụ thuộc Core Location.
* Không dùng Google Maps hoặc dịch vụ ngoài.
* Không xây thêm UI ngoài Preview và Diagnostics cần thiết.
* Không refactor persistence thành hệ thống lớn trong Sprint này.

---

# 18. Báo cáo hoàn thành

Claude cần báo cáo:

```text
1. Files created
2. Files modified
3. Location architecture
4. Clustering rules
5. Reverse geocoding and cache behavior
6. PhotoPlace fields
7. Importance scoring
8. Cover Selector refactor
9. Hero and layout scoring integration
10. Planning Log structure
11. Album/Spread/Page metadata changes
12. Create Album integration
13. Preview and Diagnostics changes
14. Tests written
15. Tests executed
16. Build result
17. Persistence compatibility
18. Known limitations
```

Không chỉ trả lời “done”.

---

# 19. Thứ tự triển khai đề xuất

Claude nên làm theo thứ tự:

```text
Step 1
Domain models:
PhotoCoordinate
PhotoPlace
PhotoImportance
Planning Log

Step 2
PHAsset adapter location support

Step 3
Location clustering

Step 4
Place resolver + cache

Step 5
Location enrichment

Step 6
Importance evaluator

Step 7
Refactor Cover Selector

Step 8
Integrate importance into hero assignment and layout scoring

Step 9
Add Album/Spread/Page metadata

Step 10
Add Planning Log

Step 11
Update Create Album flow

Step 12
Update persistence

Step 13
Update Preview and Diagnostics

Step 14
Add tests

Step 15
Build
```

---

## Kết quả mong đợi

Sau khi hoàn thành, một Album Draft phải có dạng:

```text
Album
Title: Sydney
Primary place: Sydney Opera House, Sydney
Cover: IMG_3021
Cover importance: 83.4
Planning version: 1

Spread 1
6 photos
Primary place: Sydney Opera House, Sydney
Hero: IMG_3021
Landscape: 3
Portrait: 2
Square: 1

Page 1
Layout: square.3.hero-top
Hero: IMG_3021

Page 2
Layout: square.3.equal-columns
Hero: IMG_3056
```

Và Planning Log phải giải thích được:

```text
Cover IMG_3021 selected
- favorite
- landscape
- highest normalized resolution
- importance score 83.4

Spread 1 selected layouts:
- square.3.hero-top
- square.3.equal-columns
- orientation score 560
- balance score 20
- hero score 17
- total score 597
```

Đây là mức hoàn thiện đủ tốt để chuyển sang bước tiếp theo: **Album Detail thật với ảnh thật, chỉnh cover, đổi layout và hoán đổi ảnh giữa các slot**.
