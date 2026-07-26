

# SPEC — Album Draft Planner

## 1. Mục tiêu

Xây dựng module tự động tạo một **Album Draft** từ các Event đã có trong ứng dụng Nizi.

Hiện tại người dùng đã có luồng:

```text
Event
→ chọn ảnh
→ nhấn Create Album
```

Khi người dùng nhấn tạo Album, ứng dụng phải sử dụng dữ liệu hiện có để:

1. Tạo Album mới.
2. Chọn một ảnh làm ảnh bìa.
3. Sắp xếp các ảnh đã chọn theo thời gian và nhóm sự kiện.
4. Chia ảnh thành từng cụm hai trang liên tiếp, gọi là `Spread`.
5. Chọn hai layout phù hợp cho mỗi Spread.
6. Gán ảnh vào các slot phù hợp theo hướng ngang, dọc hoặc vuông.
7. Sinh ra Album Draft hoàn chỉnh để Layout Engine hiện tại render.

Module này không trực tiếp render giao diện.

Module chỉ tạo dữ liệu:

```text
Event data
    ↓
Album Draft Planner
    ↓
Album Draft
    ↓
Album Layout Renderer
```

---

# 2. Khái niệm chính

## 2.1 Album

Một Album gồm:

* thông tin tổng quát;
* ảnh bìa;
* danh sách trang;
* metadata tổng hợp từ các Event;
* danh sách nguồn Event đã dùng.

## 2.2 Page

Một Page là một trang Album độc lập.

Mỗi Page:

* sử dụng một `layoutId`;
* có từ 1 đến 4 ảnh theo thư viện layout hiện tại;
* chứa assignment giữa ảnh và slot.

## 2.3 Spread

Một Spread gồm hai trang liên tiếp:

```text
Spread 1
├── Page 1
└── Page 2

Spread 2
├── Page 3
└── Page 4
```

Album Planner làm việc chủ yếu theo Spread thay vì từng Page riêng lẻ.

Mỗi Spread:

* tối thiểu 2 ảnh;
* tối đa 6 ảnh;
* gồm đúng hai Page;
* mỗi Page ít nhất 1 ảnh;
* mỗi Page tối đa 4 ảnh;
* tổng số ảnh của hai Page từ 2 đến 6.

Các cách chia hợp lệ:

```text
2 ảnh:
1 + 1

3 ảnh:
1 + 2
2 + 1

4 ảnh:
1 + 3
2 + 2
3 + 1

5 ảnh:
1 + 4
2 + 3
3 + 2
4 + 1

6 ảnh:
2 + 4
3 + 3
4 + 2
```

Không sử dụng:

```text
5 + 1
6 + 0
0 + 6
```

vì thư viện layout hiện tại chỉ hỗ trợ tối đa 4 ảnh trên một Page.

---

# 3. Phạm vi triển khai

Sprint này triển khai:

1. Album Draft domain models.
2. Album Planner service.
3. Thu thập metadata từ Event và Photo.
4. Chọn ảnh bìa.
5. Sắp xếp ảnh theo timeline.
6. Nhóm ảnh theo Event hoặc sub-event.
7. Chia ảnh thành Spread.
8. Chọn cặp layout phù hợp.
9. Gán ảnh vào slot.
10. Sinh Album Draft.
11. Preview Album Draft.
12. Unit tests cho thuật toán chính.

Không triển khai:

* AI hoặc LLM.
* Nhận diện nội dung ảnh.
* Chấm điểm thẩm mỹ bằng Vision.
* Face recognition.
* Crop editor.
* Kéo thả ảnh giữa các trang.
* Layout Designer.
* Đồng bộ cloud.
* Export PDF.
* Tự loại bỏ ảnh xấu.
* Tự chọn lại ảnh ngoài tập ảnh người dùng đã chọn.

Planner chỉ dùng những ảnh người dùng đã chọn trong Event.

---

# 4. Kiến trúc tổng thể

```text
Selected Event Photos
        ↓
Album Input Builder
        ↓
Photo Metadata Analyzer
        ↓
Cover Photo Selector
        ↓
Photo Grouping
        ↓
Spread Builder
        ↓
Layout Pair Selector
        ↓
Photo-to-Slot Assigner
        ↓
Album Draft
```

Các thành phần đề xuất:

```text
Features/
└── AlbumCreation/
    ├── Domain/
    │   ├── AlbumDraft.swift
    │   ├── AlbumDraftPage.swift
    │   ├── AlbumDraftSpread.swift
    │   ├── AlbumSourceEvent.swift
    │   ├── AlbumPlanningPhoto.swift
    │   ├── PhotoOrientation.swift
    │   └── AlbumPlanningResult.swift
    │
    ├── Planning/
    │   ├── AlbumDraftPlanner.swift
    │   ├── AlbumCoverSelector.swift
    │   ├── AlbumPhotoGrouper.swift
    │   ├── AlbumSpreadBuilder.swift
    │   ├── AlbumLayoutPairSelector.swift
    │   ├── AlbumPhotoSlotAssigner.swift
    │   └── AlbumPlanningValidator.swift
    │
    ├── Preview/
    │   └── AlbumDraftPlanningPreview.swift
    │
    └── Tests/
        ├── AlbumCoverSelectorTests.swift
        ├── AlbumSpreadBuilderTests.swift
        ├── AlbumLayoutPairSelectorTests.swift
        └── AlbumPhotoSlotAssignerTests.swift
```

Điều chỉnh folder theo cấu trúc project hiện có nhưng giữ ranh giới trách nhiệm tương đương.

---

# 5. Input của Album Planner

Planner nhận danh sách Event và ảnh đã chọn.

```swift
struct AlbumPlanningInput {
    let albumTitle: String?
    let events: [AlbumPlanningEvent]
}
```

```swift
struct AlbumPlanningEvent: Identifiable {
    let id: String
    let title: String?
    let startDate: Date?
    let endDate: Date?
    let locationName: String?
    let latitude: Double?
    let longitude: Double?
    let selectedPhotos: [AlbumPlanningPhoto]
}
```

Mỗi ảnh dùng model trung gian dành cho planning:

```swift
struct AlbumPlanningPhoto: Identifiable, Hashable {
    let id: String
    let eventId: String

    let creationDate: Date?

    let pixelWidth: Int
    let pixelHeight: Int

    let latitude: Double?
    let longitude: Double?

    let isFavorite: Bool
    let isEdited: Bool

    let burstIdentifier: String?
    let originalFilename: String?

    let exif: AlbumPhotoEXIF?
}
```

Không truyền trực tiếp `PHAsset` vào core planning nếu có thể tránh.

Có thể xây adapter:

```text
PHAsset
→ AlbumPlanningPhoto
```

Module Planner nên có thể unit test mà không cần Photos Framework.

---

# 6. Metadata được sử dụng

Planner được phép sử dụng những dữ liệu đã có:

* Event ID.
* Event title.
* Event start date.
* Event end date.
* Event location.
* Photo creation date.
* Pixel width.
* Pixel height.
* Photo location.
* Favorite state.
* Edited state.
* EXIF nếu có.
* Filename nếu có.
* Burst identifier nếu có.

Không bắt buộc mọi ảnh đều có đầy đủ metadata.

Planner phải hoạt động khi:

* không có EXIF;
* không có location;
* không có creation date;
* không có favorite state;
* chỉ có width và height.

Dữ liệu tối thiểu cần có:

```text
photoId
pixelWidth
pixelHeight
```

---

# 7. Xác định hướng ảnh

Tạo enum:

```swift
enum PhotoOrientation: String, Codable {
    case landscape
    case portrait
    case square
}
```

Quy tắc:

```text
ratio = width / height
```

Khuyến nghị tolerance:

```text
0.90 ... 1.10
→ square

ratio > 1.10
→ landscape

ratio < 0.90
→ portrait
```

Hàm:

```swift
func orientation(
    width: Int,
    height: Int
) -> PhotoOrientation
```

Không dùng EXIF orientation trực tiếp để phân loại ngang hoặc dọc nếu pixel dimensions đã được normalize.

---

# 8. Bổ sung metadata cho Layout Slot

Layout Engine hiện tại cần bổ sung thuộc tính mô tả dạng khung.

Tạo enum:

```swift
enum AlbumSlotOrientation: String, Codable {
    case landscape
    case portrait
    case square
    case any
}
```

Trong `AlbumLayoutSlot` bổ sung:

```swift
let preferredOrientation: AlbumSlotOrientation
```

Ví dụ JSON:

```json
{
  "id": "photo-1",
  "order": 0,
  "role": "hero",
  "preferredOrientation": "landscape",
  "frame": {
    "x": 60,
    "y": 60,
    "width": 880,
    "height": 560
  },
  "contentMode": "fill",
  "cornerRadius": 0
}
```

## 8.1 Quy ước khung vuông

Slot có:

```json
"preferredOrientation": "square"
```

được phép nhận:

* ảnh vuông;
* ảnh ngang;
* ảnh dọc.

Slot vuông được xem là slot linh hoạt.

Ưu tiên gán:

```text
Ảnh vuông → slot vuông
Ảnh ngang → slot ngang
Ảnh dọc → slot dọc
```

Nhưng khi không có khớp hoàn hảo:

```text
Ảnh ngang hoặc dọc → slot vuông
```

## 8.2 Slot any

Slot `any` nhận mọi ảnh nhưng có điểm ưu tiên thấp hơn slot khớp chính xác.

---

# 9. Album Draft model

```swift
struct AlbumDraft: Identifiable, Codable {
    let id: String

    var title: String
    var subtitle: String?

    var coverPhotoId: String

    var startDate: Date?
    var endDate: Date?

    var primaryLocationName: String?

    var sourceEvents: [AlbumSourceEvent]

    var spreads: [AlbumDraftSpread]

    var createdAt: Date
}
```

```swift
struct AlbumSourceEvent: Identifiable, Codable {
    let id: String
    let title: String?
    let selectedPhotoCount: Int
}
```

```swift
struct AlbumDraftSpread: Identifiable, Codable {
    let id: String
    let order: Int

    let sourceEventIds: [String]

    var leftPage: AlbumDraftPage
    var rightPage: AlbumDraftPage
}
```

```swift
struct AlbumDraftPage: Identifiable, Codable {
    let id: String
    let order: Int

    var layoutId: String
    var format: AlbumPageFormat

    var assignments: [AlbumPhotoAssignment]

    var sourceEventIds: [String]
}
```

Album có thể không giới hạn số Spread.

Số trang:

```text
numberOfPages = spreads.count × 2
```

---

# 10. Tạo metadata Album

Planner tổng hợp metadata từ các Event.

## 10.1 Title

Ưu tiên:

1. Title người dùng cung cấp.
2. Title của Event nếu chỉ có một Event.
3. Location chung nếu có.
4. Ngày hoặc tháng của Event.
5. Fallback `"New Album"` qua localization.

Không cần dùng AI để đặt tiêu đề.

## 10.2 Date range

```text
startDate = ngày sớm nhất của Event hoặc Photo
endDate = ngày muộn nhất của Event hoặc Photo
```

Ưu tiên Event date trước, sau đó fallback sang Photo creation date.

## 10.3 Primary location

Nếu chỉ có một Event:

```text
primaryLocation = event.locationName
```

Nếu có nhiều Event:

* chọn location xuất hiện nhiều nhất;
* nếu không xác định được, để `nil`;
* không tự ghép chuỗi địa điểm dài.

## 10.4 Total photo count

Tổng số ảnh dùng trong Album:

```text
sum(selectedPhotos.count)
```

Ảnh bìa vẫn có thể tiếp tục xuất hiện trong nội dung Album.

Sprint này không bắt buộc loại ảnh bìa khỏi các trang.

---

# 11. Chọn ảnh bìa

Tạo service:

```swift
protocol AlbumCoverSelecting {
    func selectCover(
        from photos: [AlbumPlanningPhoto]
    ) throws -> AlbumPlanningPhoto
}
```

Phiên bản đầu tiên sử dụng deterministic scoring.

## 11.1 Tiêu chí

### Favorite

```text
isFavorite
+30
```

### Resolution

Tính:

```text
pixelCount = width × height
```

Chuẩn hóa tương đối trong tập ảnh.

Điểm tối đa:

```text
+25
```

### Orientation

Album hero hiện tại là hình vuông.

Không bắt buộc ảnh vuông.

Ưu tiên:

```text
landscape: +15
square:    +12
portrait:  +8
```

Ảnh ngang thường dễ crop làm cover hơn ảnh dọc.

### Timeline position

Ưu tiên ảnh không nằm quá sát đầu hoặc cuối Event.

Ảnh nằm trong khoảng giữa 20–80% timeline:

```text
+10
```

### Edited

```text
isEdited
+5
```

### Missing date

Không trừ điểm nặng.

## 11.2 Tie breaker

Nếu bằng điểm:

1. Resolution cao hơn.
2. Creation date sớm hơn.
3. Photo ID lexical order để kết quả deterministic.

## 11.3 Không làm trong Sprint này

Không dùng:

* face count;
* smile detection;
* blur detection;
* saliency;
* Vision aesthetics;
* AI ranking.

Có thể thay selector sau này mà không sửa Album Planner.

---

# 12. Sắp xếp ảnh

Trước khi chia Spread:

1. Group theo Event.
2. Event sắp theo `startDate`.
3. Trong Event, ảnh sắp theo `creationDate`.
4. Ảnh không có date đặt sau ảnh có date trong cùng Event.
5. Tie breaker theo photo ID.

Không trộn ngẫu nhiên.

Kết quả phải deterministic.

---

# 13. Nguyên tắc giữ nhóm Event trong Spread

Mục tiêu:

> Ảnh thuộc cùng một Event hoặc cùng một nhóm sự kiện nhỏ nên ưu tiên nằm trong cùng một Spread.

Đây là ưu tiên, không phải ràng buộc tuyệt đối.

## 13.1 Một Event nhỏ

Nếu Event có từ 2 đến 6 ảnh:

```text
Event
→ một Spread
```

## 13.2 Một Event lớn

Nếu Event có hơn 6 ảnh:

```text
Event
→ nhiều Spread liên tiếp
```

Ví dụ 14 ảnh:

```text
Spread 1: 6 ảnh
Spread 2: 6 ảnh
Spread 3: 2 ảnh
```

Nhưng cần tránh để cuối cùng chỉ còn một ảnh.

Ví dụ 13 ảnh không chia:

```text
6 + 6 + 1
```

Mà nên chia:

```text
6 + 5 + 2
```

hoặc:

```text
5 + 4 + 4
```

Ưu tiên số Spread ít nhất nhưng không để Spread có dưới 2 ảnh.

## 13.3 Event chỉ có một ảnh

Nếu một Event chỉ có một ảnh, nó không thể tạo một Spread riêng vì Spread cần tối thiểu 2 ảnh.

Planner phải thử:

1. Ghép với Event liền trước nếu Spread trước còn dưới 6 ảnh.
2. Nếu không, ghép với Event liền sau.
3. Nếu không thể, ghép vào Spread gần nhất theo timeline.
4. Ghi nhận nhiều `sourceEventIds` trong Spread.

Không loại bỏ ảnh.

## 13.4 Nhiều Event nhỏ

Ví dụ:

```text
Event A: 2 ảnh
Event B: 3 ảnh
```

Có thể:

```text
Spread 1:
Event A + Event B
Tổng 5 ảnh
```

nếu chúng gần nhau về thời gian.

Tuy nhiên, nếu mỗi Event đã có đủ ảnh để tạo Spread riêng, ưu tiên giữ riêng:

```text
Event A: 4 ảnh
→ Spread 1

Event B: 5 ảnh
→ Spread 2
```

Không ghép chỉ để đạt đủ 6 ảnh.

---

# 14. Chia ảnh thành Spread

Tạo service:

```swift
protocol AlbumSpreadBuilding {
    func buildSpreads(
        from groupedPhotos: [AlbumPhotoGroup]
    ) -> [AlbumPlanningSpread]
}
```

Model trung gian:

```swift
struct AlbumPlanningSpread: Identifiable {
    let id: String
    let sourceEventIds: [String]
    let photos: [AlbumPlanningPhoto]
}
```

Validation:

```text
2 ≤ photos.count ≤ 6
```

## 14.1 Chiến lược chia Event lớn

Với `n` ảnh:

* tìm số Spread nhỏ nhất;
* mỗi Spread từ 2 đến 6 ảnh;
* phân bố tương đối đều;
* giữ đúng thứ tự thời gian.

Ví dụ:

```text
7 → 4 + 3
8 → 4 + 4 hoặc 5 + 3
9 → 5 + 4
10 → 5 + 5
11 → 6 + 5
12 → 6 + 6
13 → 5 + 4 + 4
14 → 5 + 5 + 4 hoặc 6 + 4 + 4
15 → 5 + 5 + 5
```

Không cần tối ưu toán học phức tạp.

Có thể dùng hàm phân phối đều:

```text
spreadCount = ceil(photoCount / 6)

while photoCount / spreadCount < 2:
    giảm spreadCount nếu có thể
```

Sau đó phân phối phần dư đều giữa các Spread.

---

# 15. Chia ảnh giữa hai Page

Với một Spread từ 2 đến 6 ảnh, Planner phải tìm các partition hợp lệ.

```swift
struct AlbumPagePartition: Hashable {
    let leftCount: Int
    let rightCount: Int
}
```

Danh sách:

```swift
func validPartitions(
    totalPhotoCount: Int
) -> [AlbumPagePartition]
```

Kết quả:

```text
2 → 1+1

3 → 1+2, 2+1

4 → 1+3, 2+2, 3+1

5 → 1+4, 2+3, 3+2, 4+1

6 → 2+4, 3+3, 4+2
```

Không cần sinh partition mà một Page có trên 4 ảnh.

---

# 16. Phân tích orientation của Spread

Tạo summary:

```swift
struct AlbumPhotoOrientationSummary {
    let landscapeCount: Int
    let portraitCount: Int
    let squareCount: Int
}
```

Ví dụ:

```text
Spread có 6 ảnh:

Landscape: 3
Portrait: 2
Square: 1
```

Summary này chỉ là thông tin hỗ trợ.

Việc chọn layout phải xét từng ảnh và từng slot, không chỉ xét tổng count.

---

# 17. Chọn cặp layout

Tạo service:

```swift
protocol AlbumLayoutPairSelecting {
    func selectLayoutPair(
        for photos: [AlbumPlanningPhoto],
        format: AlbumPageFormat
    ) throws -> AlbumLayoutPairSelection
}
```

Output:

```swift
struct AlbumLayoutPairSelection {
    let leftLayout: AlbumPageLayout
    let rightLayout: AlbumPageLayout

    let leftPhotos: [AlbumPlanningPhoto]
    let rightPhotos: [AlbumPlanningPhoto]

    let score: Double
}
```

## 17.1 Candidate generation

Với mỗi partition:

```text
leftCount + rightCount = totalPhotos
```

Lấy layout từ repository:

```swift
layouts(
    photoCount: leftCount,
    format: .square
)
```

và:

```swift
layouts(
    photoCount: rightCount,
    format: .square
)
```

Tạo mọi cặp:

```text
left layout × right layout
```

Ví dụ:

```text
6 ảnh
partition 2 + 4

3 layout loại 2 ảnh
×
3 layout loại 4 ảnh

= 9 candidate pairs
```

Tiếp tục xét partition:

```text
3 + 3
4 + 2
```

## 17.2 Không random

Tất cả candidate được chấm điểm.

Candidate có điểm cao nhất được chọn.

Nếu bằng điểm:

1. Partition cân bằng hơn.
2. Layout ID lexical order.
3. Thứ tự candidate ổn định.

---

# 18. Chấm điểm cặp layout

Tổng điểm đề xuất:

```text
Orientation compatibility: 60%
Spread balance:           20%
Hero suitability:         10%
Layout variety:           10%
```

Không cần dùng đúng phần trăm trong code nếu dễ dùng điểm tuyệt đối hơn.

## 18.1 Orientation compatibility

Đây là tiêu chí chính.

Mỗi ảnh được thử gán vào slot phù hợp nhất.

Điểm gợi ý:

```text
Ảnh landscape → slot landscape: +100
Ảnh portrait  → slot portrait:  +100
Ảnh square    → slot square:    +100

Ảnh landscape → slot square:     +80
Ảnh portrait  → slot square:     +80

Ảnh square → slot landscape:     +65
Ảnh square → slot portrait:      +65

Bất kỳ ảnh → slot any:            +60

Ảnh landscape → slot portrait:   +20
Ảnh portrait → slot landscape:   +20
```

Slot vuông là slot linh hoạt theo yêu cầu sản phẩm.

## 18.2 Spread balance

Ưu tiên hai trang không quá lệch.

Ví dụ:

```text
3 + 3
điểm tốt hơn

2 + 4
vẫn hợp lệ

1 + 4
ít cân bằng hơn
```

Điểm gợi ý:

```text
difference = abs(leftCount - rightCount)

0 → +20
1 → +15
2 → +8
3 → +2
```

Không để tiêu chí cân bằng lấn át orientation.

Một cặp `2+4` có orientation phù hợp vẫn có thể thắng `3+3`.

## 18.3 Hero suitability

Nếu layout có slot role `hero`, ưu tiên:

* ảnh resolution cao;
* ảnh favorite;
* ảnh ngang;
* ảnh cover candidate;
* ảnh nằm gần đầu nhóm.

Không bắt buộc ảnh bìa xuất hiện ở hero slot.

## 18.4 Layout variety

Không nên lặp cùng một layout quá nhiều Spread liên tiếp.

Ví dụ:

```text
Spread 1:
square.3.hero-top + square.3.hero-top

Spread 2:
tránh tiếp tục dùng y hệt nếu có phương án gần điểm
```

Penalty nhỏ:

```text
layout trùng Page ngay trước: -5
cặp layout trùng Spread ngay trước: -10
```

Không hy sinh orientation tốt chỉ để tạo variety.

---

# 19. Gán ảnh vào hai Page

Có hai bài toán:

1. Chia ảnh nào sang Page trái và Page phải.
2. Gán ảnh nào vào slot nào trong từng Page.

Vì tổng tối đa chỉ 6 ảnh, có thể dùng thuật toán exhaustive search nhẹ.

## 19.1 Chia ảnh sang Page

Với một partition, ví dụ `2 + 4`:

* thử các tổ hợp 2 ảnh cho Page trái;
* 4 ảnh còn lại sang Page phải;
* giữ thứ tự timeline trong mỗi Page;
* tính tổng assignment score;
* chọn tổ hợp tốt nhất.

Số lượng ảnh tối đa 6 nên số tổ hợp nhỏ.

Ví dụ:

```text
C(6,2) = 15
C(6,3) = 20
```

Hoàn toàn phù hợp để brute-force trong core.

## 19.2 Gán ảnh vào slot

Với tối đa 4 ảnh trên Page:

* thử các permutation ảnh vào slot;
* tính orientation score;
* tính hero score;
* chọn assignment cao nhất.

Tối đa:

```text
4! = 24
```

Không cần thuật toán matching phức tạp.

## 19.3 Ưu tiên timeline

Sau orientation, ưu tiên ảnh sớm hơn ở Page trái và slot có order thấp hơn.

Timeline là soft preference, không phải bắt buộc.

Có thể cộng điểm:

```text
Ảnh sớm hơn nằm ở Page trái: +5
Ảnh theo đúng thứ tự slot:    +3
```

Không để timeline phá vỡ orientation match tốt.

---

# 20. Assignment output

Sau khi chọn xong:

```swift
struct AlbumPhotoAssignment: Identifiable, Codable, Hashable {
    let id: String
    let slotId: String
    let photoId: String
}
```

Ví dụ:

```json
{
  "layoutId": "square.3.hero-top",
  "assignments": [
    {
      "id": "assignment-1",
      "slotId": "photo-1",
      "photoId": "asset-101"
    },
    {
      "id": "assignment-2",
      "slotId": "photo-2",
      "photoId": "asset-104"
    },
    {
      "id": "assignment-3",
      "slotId": "photo-3",
      "photoId": "asset-103"
    }
  ]
}
```

Không phụ thuộc vào index ngầm.

---

# 21. Album Planner service

Định nghĩa:

```swift
protocol AlbumDraftPlanning {
    func createDraft(
        from input: AlbumPlanningInput
    ) throws -> AlbumDraft
}
```

Implementation:

```text
DefaultAlbumDraftPlanner
```

Luồng:

```swift
func createDraft(
    from input: AlbumPlanningInput
) throws -> AlbumDraft {

    // 1. Validate selected photos

    // 2. Build album metadata

    // 3. Select cover

    // 4. Sort events and photos

    // 5. Build event photo groups

    // 6. Build spreads of 2...6 photos

    // 7. For each spread:
    //    - generate page partitions
    //    - retrieve layouts
    //    - score layout pairs
    //    - split photos between pages
    //    - assign photos to slots

    // 8. Build AlbumDraft

    // 9. Validate final draft

    // 10. Return
}
```

Planner không được gọi SwiftUI renderer.

---

# 22. Validation đầu vào

Các lỗi cần xử lý:

```swift
enum AlbumPlanningError: Error {
    case noEvents
    case noSelectedPhotos
    case invalidPhotoDimensions(photoId: String)
    case coverSelectionFailed
    case noValidSpreadPartition(photoCount: Int)
    case noCompatibleLayout(photoCount: Int)
    case slotAssignmentFailed(layoutId: String)
    case invalidDraft
}
```

## 22.1 Một ảnh duy nhất

Nếu toàn bộ input chỉ có một ảnh:

* không thể tạo Spread hai trang tối thiểu 2 ảnh;
* không tự nhân đôi ảnh;
* không tạo Page rỗng;
* trả lỗi `insufficientPhotos`.

Bổ sung:

```swift
case insufficientPhotos(minimum: Int, actual: Int)
```

UI sẽ thông báo cần chọn tối thiểu 2 ảnh.

## 22.2 Thiếu layout

Nếu không tìm được layout cho count yêu cầu:

* thử partition khác;
* nếu tất cả đều thất bại, trả lỗi rõ ràng;
* không dùng fallback hardcode SwiftUI.

---

# 23. Trường hợp số ảnh lẻ và trang cuối

Album luôn tạo theo Spread hai trang.

Do mỗi Spread tối thiểu 2 ảnh nên không tạo trang cuối đơn lẻ.

Ví dụ:

```text
17 ảnh
```

Có thể chia:

```text
6 + 6 + 5
```

tạo:

```text
Spread 1: 6 ảnh
Spread 2: 6 ảnh
Spread 3: 5 ảnh
```

Tổng:

```text
6 Page
```

Không có Page rỗng.

---

# 24. Cover và nội dung trang

Ảnh bìa được chọn từ các ảnh đã chọn.

Sprint này:

```text
coverPhotoId
```

không làm thay đổi danh sách ảnh nội dung.

Nghĩa là ảnh bìa có thể xuất hiện lại trong một Page.

Lý do:

* tránh tự ý loại ảnh người dùng đã chọn;
* ảnh bìa có thể vẫn là khoảnh khắc quan trọng;
* đơn giản hóa version đầu.

Sau này có thể thêm setting:

```text
excludeCoverFromPages
```

Không triển khai trong Sprint này.

---

# 25. Preview cần tạo

Tạo:

```text
AlbumDraftPlanningPreview
```

Preview phải minh họa ít nhất ba trường hợp.

## Case 1 — 6 ảnh

```text
3 landscape
2 portrait
1 square
```

Kết quả dự kiến:

```text
1 Spread
2 Page
Tổng 6 ảnh
```

Hiển thị:

* ảnh bìa;
* layout ID Page trái;
* layout ID Page phải;
* orientation từng ảnh;
* slot assignment;
* tổng score.

## Case 2 — 13 ảnh trong một Event

Kết quả:

```text
3 Spread
```

Không được chia thành:

```text
6 + 6 + 1
```

Mà phải là các nhóm hợp lệ, ví dụ:

```text
5 + 4 + 4
```

## Case 3 — nhiều Event nhỏ

```text
Event A: 1 ảnh
Event B: 3 ảnh
Event C: 2 ảnh
```

Planner phải ghép Event A với nhóm gần nhất để không tạo Spread một ảnh.

Preview sử dụng mock photos, không cần Photos Library.

---

# 26. Tích hợp với nút Create Album

Luồng hiện tại:

```text
Event Detail
→ selectedPhotos
→ Create Album
```

Thay đổi thành:

```text
Create Album
    ↓
Build AlbumPlanningInput
    ↓
DefaultAlbumDraftPlanner.createDraft(...)
    ↓
Save AlbumDraft
    ↓
Open Album Detail
```

Không thay đổi cơ chế chọn ảnh hiện tại.

## 26.1 Trạng thái UI

Khi tạo Draft:

```text
idle
planning
success
failure
```

Planning là xử lý local và dự kiến nhanh.

Không cần progress chi tiết theo phần trăm.

Có thể hiển thị:

```text
Creating album…
```

qua localization.

## 26.2 Không chạy trên main thread

Planning có thể chạy ngoài main actor.

Chỉ update UI trên `MainActor`.

Không gọi Photos image loading full-resolution trong quá trình planning.

Planner chỉ cần metadata.

---

# 27. Lưu Album Draft

Sử dụng persistence hiện có của project.

Nếu chưa có model Album đầy đủ, cần tạo cấu trúc tối thiểu hỗ trợ:

* album ID;
* cover photo ID;
* title;
* date range;
* location;
* source Event IDs;
* spreads;
* pages;
* layout IDs;
* assignments.

Không lưu toàn bộ layout JSON vào từng Page.

Chỉ lưu:

```text
layoutId
```

Layout geometry lấy từ Layout Repository.

Không duplicate frame tọa độ vào Album Draft.

---

# 28. Deterministic result

Cùng một input và cùng một layout library phải tạo cùng một Album Draft.

Không dùng:

* random;
* shuffled;
* UUID làm tie breaker;
* thời gian hiện tại trong scoring.

UUID có thể dùng cho ID output, nhưng không được ảnh hưởng việc chọn layout.

Unit tests phải có thể dự đoán kết quả.

---

# 29. Hiệu năng

Album thông thường có thể có hàng chục hoặc hàng trăm ảnh.

Nguyên tắc:

* chia ảnh thành Spread trước;
* mỗi Spread chỉ tối đa 6 ảnh;
* exhaustive search chỉ chạy trong từng Spread;
* không thử permutation trên toàn Album;
* cache layouts theo `photoCount`;
* chuyển slots thành dữ liệu đã sort trước;
* không decode JSON trong mỗi Spread;
* không load bitmap để chọn layout.

Với một Spread tối đa 6 ảnh, brute-force tổ hợp và permutation là an toàn.

---

# 30. Unit tests

## 30.1 Orientation

* ảnh ngang đúng;
* ảnh dọc đúng;
* ảnh gần vuông được xác định square;
* width hoặc height bằng 0 trả lỗi.

## 30.2 Cover selection

* favorite được ưu tiên;
* resolution được xét;
* tie breaker deterministic;
* không có ảnh trả lỗi.

## 30.3 Spread building

* 2 ảnh → 1 Spread.
* 6 ảnh → 1 Spread.
* 7 ảnh → 2 Spread hợp lệ.
* 13 ảnh không tạo Spread một ảnh.
* mọi Spread từ 2 đến 6 ảnh.
* tổng ảnh sau chia bằng tổng ảnh đầu vào.
* thứ tự timeline được giữ.

## 30.4 Event grouping

* một Event nhỏ giữ trong một Spread.
* một Event lớn chia thành nhiều Spread liên tiếp.
* Event một ảnh được ghép với Event gần nhất.
* ảnh không bị mất.
* ảnh không bị duplicate.

## 30.5 Partition

Kiểm tra đúng:

```text
2 → 1+1
3 → 1+2, 2+1
4 → 1+3, 2+2, 3+1
5 → 1+4, 2+3, 3+2, 4+1
6 → 2+4, 3+3, 4+2
```

## 30.6 Layout pair selection

* chỉ lấy layout đúng photo count;
* chỉ lấy layout đúng page format;
* chọn cặp orientation score cao hơn;
* có fallback khi không khớp hoàn hảo;
* square slot nhận portrait và landscape;
* kết quả deterministic.

## 30.7 Slot assignment

* landscape ưu tiên landscape slot;
* portrait ưu tiên portrait slot;
* square ưu tiên square slot;
* landscape có thể vào square slot;
* portrait có thể vào square slot;
* mọi slot được assignment đúng một ảnh;
* không duplicate ảnh;
* không assignment vào slot không tồn tại.

## 30.8 Final draft validation

* có cover;
* có ít nhất một Spread;
* mỗi Spread đúng hai Page;
* mỗi Page có từ 1 đến 4 ảnh;
* mỗi Spread có từ 2 đến 6 ảnh;
* mọi layout ID tồn tại;
* mọi assignment trỏ đến slot hợp lệ;
* tổng ảnh đúng với input.

---

# 31. Acceptance criteria

Task hoàn thành khi:

1. Có module Album Draft Planner riêng.
2. Nút Create Album sử dụng Planner.
3. Planner lấy đúng các ảnh đã chọn trong Event.
4. Planner tổng hợp title, date và location nếu có.
5. Có thuật toán chọn ảnh bìa.
6. Ảnh được sắp theo Event và timeline.
7. Ảnh được chia thành Spread.
8. Mỗi Spread có đúng hai Page.
9. Mỗi Spread có từ 2 đến 6 ảnh.
10. Mỗi Page có từ 1 đến 4 ảnh.
11. Một Event được ưu tiên nằm trong cùng Spread.
12. Event lớn được chia thành nhiều Spread liên tiếp.
13. Không có Spread chỉ một ảnh.
14. Planner tìm cặp layout có tổng slot bằng số ảnh của Spread.
15. Layout được chọn dựa trên orientation của ảnh và slot.
16. Slot vuông nhận được ảnh ngang, dọc hoặc vuông.
17. Ảnh được assignment linh hoạt vào slot.
18. Không dùng random.
19. Không hardcode layout bằng SwiftUI.
20. Album Draft chỉ lưu `layoutId` và assignments.
21. Layout Renderer hiện tại render được Draft.
22. Có Preview cho các trường hợp chính.
23. Unit tests pass.
24. App build pass.
25. Không chạy simulator.
26. Không triển khai AI hoặc Layout Designer.

---

# 32. Quy tắc không được vi phạm

* Không tạo thêm ảnh giả để đủ trang.
* Không bỏ ảnh người dùng đã chọn.
* Không duplicate ảnh giữa các Page.
* Không tạo Page rỗng.
* Không tạo Spread một ảnh.
* Không để Page có trên 4 ảnh.
* Không để Spread có trên 6 ảnh.
* Không phụ thuộc bitmap full-resolution.
* Không để Planner phụ thuộc SwiftUI.
* Không để Renderer quyết định chọn layout.
* Không lưu geometry layout vào Album Draft.
* Không sửa Layout Engine thành logic planner.
* Không sử dụng AI trong version này.

---

# 33. Báo cáo sau khi triển khai

Claude cần báo cáo rõ:

```text
1. Files created
2. Files modified
3. Domain models added
4. Album planning pipeline
5. Cover selection rules
6. Spread building rules
7. Layout-pair scoring rules
8. Slot assignment algorithm
9. Create Album integration
10. Preview cases
11. Tests executed
12. Build result
13. Known limitations
```

Không chỉ trả lời “done”.

---

## Tóm tắt logic cốt lõi

```text
Ảnh đã chọn trong Event
        ↓
Phân tích metadata và orientation
        ↓
Chọn ảnh bìa
        ↓
Sắp xếp theo Event và thời gian
        ↓
Chia thành từng Spread 2–6 ảnh
        ↓
Với mỗi Spread:
    tìm các partition hợp lệ
    tìm các cặp layout
    thử chia ảnh sang hai Page
    thử gán ảnh vào các slot
    chấm điểm orientation và cân bằng
    chọn phương án tốt nhất
        ↓
Sinh Album Draft
        ↓
Layout Engine render
```

Điểm quan trọng nhất của thuật toán là:

> Planner không cố định trước mỗi trang bao nhiêu ảnh. Planner xét toàn bộ cụm hai trang, sau đó tìm cặp layout và cách gán ảnh có tổng điểm phù hợp nhất.
