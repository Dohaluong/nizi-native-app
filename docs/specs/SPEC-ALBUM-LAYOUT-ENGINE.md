Mục tiêu là xây dựng **Layout Engine độc lập**, không gắn chặt vào màn hình Album Detail hiện tại và không sa đà làm trình thiết kế layout trong Sprint này.


---

# 1SPEC — Album Page Layout Engine

## 1. Mục tiêu

Xây dựng hệ thống layout trang Album cho ứng dụng Nizi.

Mỗi Album gồm nhiều trang. Mỗi trang có thể chứa từ 1 đến 4 ảnh và sử dụng một layout được chọn từ thư viện layout JSON.

Hệ thống phải đáp ứng:

* Layout được mô tả bằng JSON, không hardcode riêng từng layout trong SwiftUI.
* Một renderer chung có thể hiển thị tất cả layout.
* Layout không phụ thuộc trực tiếp vào kích thước màn hình.
* Layout có thể render trên trang vuông, trang đứng hoặc trang ngang.
* Mỗi trang Album chỉ lưu `layoutId` và danh sách ảnh được gán vào các slot.
* Có thư viện layout mẫu cho trang từ 1 đến 4 ảnh.
* Mỗi số lượng ảnh có từ 2 đến 4 phương án layout.
* Module thiết kế và chỉnh sửa layout sẽ được xây riêng sau.
* Sprint hiện tại không xây dựng Layout Editor.

Không thay đổi pipeline phát hiện Event, chọn ảnh hoặc tạo Album hiện tại ngoài phần tích hợp tối thiểu cần thiết.

---

# 2. Nguyên tắc kiến trúc

Tách hệ thống thành bốn phần:

```text
Layout JSON Library
        ↓
Layout Domain Models
        ↓
Layout Repository
        ↓
Generic Page Renderer
```

Dữ liệu Album riêng:

```text
Album
 └── AlbumPage
      ├── layoutId
      └── photoAssignments
```

Layout template và nội dung trang là hai loại dữ liệu khác nhau.

## 2.1 Layout template

Layout template định nghĩa:

* kích thước canvas tham chiếu;
* tỷ lệ trang;
* các slot;
* vị trí và kích thước của từng slot;
* hành vi ảnh trong slot.

Layout template không chứa ID ảnh cụ thể.

## 2.2 Album page content

Album page content định nghĩa:

* trang đang dùng layout nào;
* ảnh nào nằm trong slot nào;
* thứ tự trang.

Album page content không chứa tọa độ layout.

---

# 3. Phạm vi Sprint hiện tại

Triển khai:

1. Domain models cho layout.
2. JSON schema thực tế.
3. File thư viện layout mẫu.
4. Loader và repository.
5. Validation.
6. Generic SwiftUI renderer.
7. Models cho nội dung một Album page.
8. Preview gallery để xem toàn bộ layout.
9. Preview một Album gồm nhiều trang.
10. Unit test cho parsing và validation.
11. Tài liệu hướng dẫn bổ sung layout mới.

Không triển khai:

* Layout Editor.
* Kéo, thả hoặc resize slot.
* Lưu layout do người dùng tự thiết kế.
* Đồng bộ layout từ server.
* AI tự sinh tọa độ layout.
* Text box, sticker, map, QR hoặc video.
* Export PDF hoặc in photobook.
* Crop editor thủ công.
* Animation phức tạp.

Kiến trúc phải cho phép mở rộng các phần trên sau này nhưng không được xây trước.

---

# 4. Cấu trúc module

Tạo module hoặc feature folder riêng, ví dụ:

```text
Features/
└── AlbumLayout/
    ├── Domain/
    │   ├── AlbumPageLayout.swift
    │   ├── AlbumLayoutSlot.swift
    │   ├── AlbumPageContent.swift
    │   ├── AlbumPhotoAssignment.swift
    │   ├── AlbumPageFormat.swift
    │   └── AlbumLayoutValidationError.swift
    │
    ├── Data/
    │   ├── AlbumLayoutLibraryDTO.swift
    │   ├── BundleAlbumLayoutRepository.swift
    │   └── album-layouts.json
    │
    ├── Rendering/
    │   ├── AlbumPageRenderer.swift
    │   ├── AlbumPhotoSlotView.swift
    │   └── AlbumPageCanvas.swift
    │
    ├── Preview/
    │   ├── AlbumLayoutGalleryPreview.swift
    │   └── AlbumPagesPreview.swift
    │
    └── Tests/
        ├── AlbumLayoutDecodingTests.swift
        └── AlbumLayoutValidationTests.swift
```

Điều chỉnh theo cấu trúc project hiện tại nếu cần, nhưng giữ ranh giới trách nhiệm tương đương.

Không đặt toàn bộ hệ thống trong một file Swift lớn.

---

# 5. Hệ tọa độ layout

Sử dụng canvas tham chiếu thay vì lưu trực tiếp giá trị từ `0...1`.

Ví dụ:

```json
{
  "referenceCanvas": {
    "width": 1000,
    "height": 1000
  }
}
```

Một slot:

```json
{
  "frame": {
    "x": 60,
    "y": 60,
    "width": 880,
    "height": 880
  }
}
```

Renderer tính:

```text
scaleX = actualCanvasWidth / referenceCanvasWidth
scaleY = actualCanvasHeight / referenceCanvasHeight
```

Sau đó:

```text
actualX      = frame.x × scaleX
actualY      = frame.y × scaleY
actualWidth  = frame.width × scaleX
actualHeight = frame.height × scaleY
```

## 5.1 Quy tắc thích ứng tỷ lệ trang

Layout được thiết kế cho một nhóm tỷ lệ trang cụ thể, không nên kéo méo tùy ý giữa mọi tỷ lệ.

Mỗi layout phải khai báo:

```json
"supportedFormats": ["square"]
```

hoặc:

```json
"supportedFormats": ["portrait"]
```

hoặc:

```json
"supportedFormats": ["landscape"]
```

Có thể khai báo nhiều format nếu layout thực sự phù hợp:

```json
"supportedFormats": [
  "square",
  "portrait"
]
```

Không được mặc định cho rằng một layout vuông sẽ có chất lượng thiết kế tốt khi kéo thành trang đứng hoặc trang ngang.

Renderer có thể render bằng scale nhưng repository phải lọc layout phù hợp với format trang.

Đây là điểm quan trọng:

> Hệ tọa độ không phụ thuộc pixel hoặc màn hình, nhưng chất lượng bố cục vẫn phụ thuộc tỷ lệ trang.

---

# 6. Page format

Tạo enum:

```swift
enum AlbumPageFormat: String, Codable, CaseIterable {
    case square
    case portrait
    case landscape
}
```

Các kích thước tham chiếu ban đầu:

```text
square:
1000 × 1000

portrait:
1000 × 1400

landscape:
1400 × 1000
```

Sprint hiện tại ưu tiên `square`, vì giao diện Album Nizi đang hiển thị trang vuông.

Tuy vậy models và renderer phải hỗ trợ đủ cả ba format.

---

# 7. JSON schema

File:

```text
album-layouts.json
```

Cấu trúc cấp cao:

```json
{
  "schemaVersion": 1,
  "layouts": []
}
```

Mỗi layout:

```json
{
  "id": "square.3.hero-top",
  "name": "Hero Top",
  "photoCount": 3,
  "supportedFormats": [
    "square"
  ],
  "referenceCanvas": {
    "width": 1000,
    "height": 1000
  },
  "background": {
    "type": "solid",
    "value": "#FFFFFF"
  },
  "slots": [
    {
      "id": "photo-1",
      "order": 0,
      "role": "hero",
      "frame": {
        "x": 60,
        "y": 60,
        "width": 880,
        "height": 540
      },
      "contentMode": "fill",
      "cornerRadius": 0
    }
  ]
}
```

---

# 8. Domain models

## 8.1 Layout library

```swift
struct AlbumLayoutLibrary: Codable {
    let schemaVersion: Int
    let layouts: [AlbumPageLayout]
}
```

## 8.2 Page layout

```swift
struct AlbumPageLayout: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let photoCount: Int
    let supportedFormats: [AlbumPageFormat]
    let referenceCanvas: AlbumReferenceCanvas
    let background: AlbumLayoutBackground
    let slots: [AlbumLayoutSlot]
}
```

## 8.3 Reference canvas

```swift
struct AlbumReferenceCanvas: Codable, Hashable {
    let width: Double
    let height: Double
}
```

## 8.4 Frame

```swift
struct AlbumLayoutFrame: Codable, Hashable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}
```

## 8.5 Slot

```swift
struct AlbumLayoutSlot: Identifiable, Codable, Hashable {
    let id: String
    let order: Int
    let role: AlbumLayoutSlotRole
    let frame: AlbumLayoutFrame
    let contentMode: AlbumSlotContentMode
    let cornerRadius: Double
}
```

## 8.6 Slot role

```swift
enum AlbumLayoutSlotRole: String, Codable {
    case hero
    case supporting
}
```

Role hiện tại chỉ phục vụ:

* mô tả semantic;
* layout recommendation sau này;
* giúp xác định ảnh nổi bật.

Không dùng role để thay đổi tọa độ trong renderer.

## 8.7 Content mode

```swift
enum AlbumSlotContentMode: String, Codable {
    case fill
    case fit
}
```

Mặc định các layout mẫu dùng `fill`.

## 8.8 Background

```swift
struct AlbumLayoutBackground: Codable, Hashable {
    let type: AlbumLayoutBackgroundType
    let value: String
}

enum AlbumLayoutBackgroundType: String, Codable {
    case solid
}
```

Sprint này chỉ hỗ trợ `solid`.

---

# 9. Dữ liệu nội dung Album Page

Không gán ảnh dựa trên vị trí ngầm trong array nếu có thể tránh.

Dùng assignment rõ ràng theo `slotId`.

```swift
struct AlbumPageContent: Identifiable, Codable, Hashable {
    let id: String
    var layoutId: String
    var format: AlbumPageFormat
    var assignments: [AlbumPhotoAssignment]
}
```

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
  "id": "page-001",
  "layoutId": "square.3.hero-top",
  "format": "square",
  "assignments": [
    {
      "id": "assignment-001",
      "slotId": "photo-1",
      "photoId": "asset-101"
    },
    {
      "id": "assignment-002",
      "slotId": "photo-2",
      "photoId": "asset-102"
    },
    {
      "id": "assignment-003",
      "slotId": "photo-3",
      "photoId": "asset-103"
    }
  ]
}
```

Lợi ích:

* đổi ảnh giữa các slot không cần đổi layout;
* thiếu ảnh ở slot nào có thể phát hiện rõ;
* sau này drag-and-drop ảnh giữa slot dễ hơn;
* thứ tự slot không phụ thuộc thứ tự decode JSON.

---

# 10. Layout repository

Định nghĩa protocol:

```swift
protocol AlbumLayoutRepository {
    func loadLibrary() throws -> AlbumLayoutLibrary

    func layout(
        id: String
    ) throws -> AlbumPageLayout

    func layouts(
        photoCount: Int,
        format: AlbumPageFormat
    ) throws -> [AlbumPageLayout]
}
```

Implementation hiện tại:

```text
BundleAlbumLayoutRepository
```

Repository:

1. Đọc `album-layouts.json` từ app bundle.
2. Decode bằng `JSONDecoder`.
3. Validate thư viện.
4. Cache kết quả trong memory.
5. Trả layout theo ID.
6. Lọc theo `photoCount` và `supportedFormats`.

Không đọc JSON lại mỗi lần SwiftUI render.

Không đặt logic đọc bundle trực tiếp trong View.

---

# 11. Validation

Sau khi decode, phải validate.

Một layout không hợp lệ không được silently render.

## 11.1 Quy tắc chung

* `schemaVersion` phải được hỗ trợ.
* ID layout không được trùng.
* `photoCount` phải từ 1 đến 4.
* `slots.count` phải bằng `photoCount`.
* ID slot trong cùng layout không được trùng.
* `order` không được trùng.
* Canvas width và height phải lớn hơn 0.
* Slot width và height phải lớn hơn 0.
* `x` và `y` không được âm.
* Slot không được vượt canvas.
* `cornerRadius` không được âm.
* `supportedFormats` không được rỗng.
* Tỷ lệ reference canvas phải phù hợp với format khai báo.

## 11.2 Quy tắc tỷ lệ format

Có tolerance nhỏ, ví dụ 5%.

```text
square:
width / height ≈ 1.0

portrait:
width / height < 1.0

landscape:
width / height > 1.0
```

Không cần over-engineer việc kiểm tra chính xác các tỷ lệ in ấn trong Sprint này.

## 11.3 Slot overlap

Không bắt buộc cấm mọi overlap ở tầng core vì sau này layout sáng tạo có thể cần overlap.

Tuy nhiên các layout mẫu Sprint này không được overlap.

Có thể thêm metadata sau này:

```json
"allowsOverlap": false
```

Không cần triển khai trong Sprint hiện tại.

---

# 12. Renderer

Tạo:

```text
AlbumPageRenderer
```

Renderer nhận:

```swift
struct AlbumPageRenderer: View {
    let layout: AlbumPageLayout
    let assignments: [AlbumPhotoAssignment]
    let photoProvider: AlbumPhotoProviding
}
```

Hoặc dùng closure đơn giản hơn nếu phù hợp codebase:

```swift
let photoView: (String) -> AnyView
```

Ưu tiên protocol hoặc generic closure không dùng `AnyView` nếu có thể.

## 12.1 Trách nhiệm renderer

* Nhận kích thước canvas thực tế.
* Tính `scaleX` và `scaleY`.
* Vẽ background.
* Render từng slot theo `order`.
* Tìm assignment dựa trên `slot.id`.
* Hiển thị ảnh hoặc placeholder.
* Clip ảnh đúng slot.
* Áp dụng content mode.
* Áp dụng corner radius.
* Không quyết định layout.
* Không tự sắp xếp ảnh.
* Không load JSON.
* Không chứa business logic Album.

## 12.2 Container owns size

Tuân thủ nguyên tắc:

```text
Canvas quyết định kích thước
→ Slot quyết định frame
→ Image chỉ fill hoặc fit trong slot
```

Ảnh không được dùng intrinsic size để đẩy layout.

Mỗi slot phải dùng frame rõ ràng.

## 12.3 Cách đặt slot

Có thể dùng:

```swift
.position(
    x: actualX + actualWidth / 2,
    y: actualY + actualHeight / 2
)
```

thay vì chuỗi nested `HStack`, `VStack` hoặc `GeometryReader`.

Khuyến nghị:

```swift
ZStack(alignment: .topLeading)
```

Sau đó đặt từng slot bằng frame và position/offset.

## 12.4 Placeholder

Khi photo không tồn tại hoặc chưa được resolve:

* hiển thị nền `secondarySystemFill`;
* icon `photo`;
* có thể hiện `slot.id` trong Debug/Preview;
* production không cần hiện slot ID.

Renderer không được crash khi thiếu assignment.

---

# 13. Photo provider

Renderer không nên phụ thuộc trực tiếp vào Apple Photos hoặc `PHAsset`.

Định nghĩa abstraction tối thiểu:

```swift
protocol AlbumPhotoProviding {
    associatedtype PhotoContent: View

    @ViewBuilder
    func photoView(
        photoId: String,
        contentMode: AlbumSlotContentMode
    ) -> PhotoContent
}
```

Nếu associated type làm tích hợp quá phức tạp, có thể dùng generic closure truyền từ bên ngoài.

Mục tiêu:

* Preview dùng ảnh Assets hoặc placeholder.
* Production dùng photo thumbnail provider hiện tại.
* Renderer không biết ảnh đến từ `PHAsset`, cache hay app bundle.

Không xây photo loading pipeline mới trong task này.

---

# 14. Thư viện layout mẫu

Chủ động tạo ít nhất 12 layout vuông.

## 14.1 Một ảnh — 3 layout

### `square.1.full-bleed`

Một ảnh phủ toàn bộ canvas.

```text
┌──────────────┐
│              │
│    PHOTO     │
│              │
└──────────────┘
```

* 1 slot.
* Không margin.
* Role: hero.

### `square.1.inset`

Một ảnh có margin đều bốn phía.

```text
┌──────────────┐
│  ┌────────┐  │
│  │ PHOTO  │  │
│  └────────┘  │
└──────────────┘
```

* Margin khoảng 6%.
* Nền trắng.
* Role: hero.

### `square.1.landscape-center`

Ảnh ngang đặt giữa trang, để khoảng trắng trên và dưới.

```text
┌──────────────┐
│              │
│██████████████│
│██████████████│
│              │
└──────────────┘
```

* Slot khoảng 88% chiều rộng.
* Slot khoảng 56% chiều cao.
* Role: hero.

---

## 14.2 Hai ảnh — 3 layout

### `square.2.vertical-split`

Hai ảnh chia trái và phải.

```text
┌──────┬───────┐
│      │       │
│  1   │   2   │
│      │       │
└──────┴───────┘
```

### `square.2.horizontal-split`

Hai ảnh chia trên và dưới.

```text
┌──────────────┐
│      1       │
├──────────────┤
│      2       │
└──────────────┘
```

### `square.2.hero-top`

Ảnh chính lớn phía trên, ảnh phụ nhỏ phía dưới.

```text
┌──────────────┐
│              │
│      1       │
│              │
├──────────────┤
│      2       │
└──────────────┘
```

Ảnh 1 role `hero`, ảnh 2 role `supporting`.

Có thể thêm phương án thứ tư nếu dễ:

### `square.2.hero-left`

Ảnh chính lớn bên trái, ảnh phụ hẹp bên phải.

---

## 14.3 Ba ảnh — 3 layout

### `square.3.hero-top`

Ảnh chính lớn phía trên, hai ảnh dưới.

```text
┌──────────────┐
│      1       │
│              │
├──────┬───────┤
│  2   │   3   │
└──────┴───────┘
```

### `square.3.hero-left`

Ảnh chính lớn bên trái, hai ảnh xếp bên phải.

```text
┌────────┬─────┐
│        │  2  │
│   1    ├─────┤
│        │  3  │
└────────┴─────┘
```

### `square.3.equal-columns`

Ba ảnh cột đều nhau.

```text
┌────┬────┬────┐
│ 1  │ 2  │ 3  │
│    │    │    │
└────┴────┴────┘
```

Có thể dùng margin ngoài để layout không quá chật.

---

## 14.4 Bốn ảnh — 3 layout

### `square.4.grid`

Lưới 2×2.

```text
┌──────┬───────┐
│  1   │   2   │
├──────┼───────┤
│  3   │   4   │
└──────┴───────┘
```

### `square.4.hero-top`

Ảnh chính lớn phía trên, ba ảnh đều phía dưới.

```text
┌──────────────┐
│      1       │
│              │
├────┬────┬────┤
│ 2  │ 3  │ 4  │
└────┴────┴────┘
```

### `square.4.hero-left`

Ảnh chính lớn bên trái, ba ảnh nhỏ xếp dọc bên phải.

```text
┌────────┬─────┐
│        │  2  │
│        ├─────┤
│   1    │  3  │
│        ├─────┤
│        │  4  │
└────────┴─────┘
```

Có thể thêm phương án thứ tư:

### `square.4.one-plus-three`

Ảnh lớn chiếm khoảng 60% trang, ba ảnh phụ theo bố cục bất đối xứng nhưng vẫn không overlap.

Không cần cố tạo phương án thứ tư nếu bố cục không đẹp hoặc làm tăng phạm vi không cần thiết. Yêu cầu tối thiểu là 3 layout mỗi số lượng ảnh.

Tổng tối thiểu:

```text
1 ảnh: 3 layout
2 ảnh: 3 layout
3 ảnh: 3 layout
4 ảnh: 3 layout

Tổng: 12 layout
```

---

# 15. Quy chuẩn tọa độ mẫu

Với canvas vuông `1000 × 1000`:

## 15.1 Margin

Các layout inset dùng:

```text
outer margin: 50–70
```

Khuyến nghị mặc định:

```text
60
```

## 15.2 Gap

Khoảng cách giữa các ảnh:

```text
12–24
```

Khuyến nghị mặc định:

```text
16
```

## 15.3 Full bleed

Layout full bleed:

```text
x = 0
y = 0
width = 1000
height = 1000
```

## 15.4 Không sinh tọa độ lỗi

Mọi slot phải nằm hoàn toàn trong canvas:

```text
x + width ≤ canvasWidth
y + height ≤ canvasHeight
```

Các gap nhìn phải đều nhau.

Không dùng số thập phân không cần thiết trong JSON mẫu.

---

# 16. Ví dụ JSON

File thực tế phải chứa đủ 12 layout. Đây là cấu trúc mẫu cho một layout:

```json
{
  "id": "square.3.hero-top",
  "name": "Hero Top",
  "photoCount": 3,
  "supportedFormats": [
    "square"
  ],
  "referenceCanvas": {
    "width": 1000,
    "height": 1000
  },
  "background": {
    "type": "solid",
    "value": "#FFFFFF"
  },
  "slots": [
    {
      "id": "photo-1",
      "order": 0,
      "role": "hero",
      "frame": {
        "x": 60,
        "y": 60,
        "width": 880,
        "height": 560
      },
      "contentMode": "fill",
      "cornerRadius": 0
    },
    {
      "id": "photo-2",
      "order": 1,
      "role": "supporting",
      "frame": {
        "x": 60,
        "y": 636,
        "width": 432,
        "height": 304
      },
      "contentMode": "fill",
      "cornerRadius": 0
    },
    {
      "id": "photo-3",
      "order": 2,
      "role": "supporting",
      "frame": {
        "x": 508,
        "y": 636,
        "width": 432,
        "height": 304
      },
      "contentMode": "fill",
      "cornerRadius": 0
    }
  ]
}
```

---

# 17. Layout Gallery Preview

Tạo màn hình Preview riêng:

```text
AlbumLayoutGalleryPreview
```

Yêu cầu:

* Hiển thị tất cả layout trong thư viện.
* Group theo `photoCount`.
* Mỗi layout hiển thị:

  * preview thumbnail;
  * layout name;
  * layout ID;
  * số ảnh;
  * supported formats.
* Dùng ảnh placeholder có số thứ tự `1`, `2`, `3`, `4`.
* Có thể tap một layout để mở preview lớn.
* Không phụ thuộc Photos Library.
* Không cần simulator.
* Phải hoạt động trong Xcode Preview.

Ví dụ:

```text
1 Photo

[preview] Full Bleed
          square.1.full-bleed

[preview] Inset
          square.1.inset
```

Mục đích của màn hình này là cùng người dùng đánh giá và chỉnh thư viện layout trước khi tích hợp sâu vào Album.

---

# 18. Album Pages Preview

Tạo một preview minh họa Album:

```text
AlbumPagesPreview
```

Yêu cầu:

* Có hero cover vuông đã thiết kế.
* Phần dưới hiển thị các trang bằng horizontal paging.
* Mỗi trang dùng một layout lấy từ repository.
* Không hardcode layout SwiftUI riêng.
* Mỗi trang dùng `AlbumPageRenderer`.
* Có page indicator.
* Có thông tin:

  * số trang hiện tại;
  * tổng số trang;
  * layout ID hiện tại.
* Preview dùng placeholder hoặc local assets.
* Không lệch trái.
* Không để nội dung vượt viewport.
* Kích thước trang được xác định bởi container.
* Ảnh không quyết định kích thước layout.

---

# 19. Chọn layout mặc định

Tạo selector tối thiểu:

```swift
protocol AlbumLayoutSelecting {
    func defaultLayout(
        photoCount: Int,
        format: AlbumPageFormat
    ) throws -> AlbumPageLayout
}
```

Phiên bản đầu dùng quy tắc deterministic:

```text
1 ảnh → square.1.inset
2 ảnh → square.2.vertical-split
3 ảnh → square.3.hero-top
4 ảnh → square.4.grid
```

Không dùng random làm mặc định.

Có thể có hàm:

```swift
func alternativeLayouts(
    photoCount: Int,
    format: AlbumPageFormat,
    excluding currentLayoutId: String?
) throws -> [AlbumPageLayout]
```

Mục đích để UI sau này cho người dùng đổi mẫu trang.

Không triển khai AI layout selection trong task này.

---

# 20. Chuẩn bị cho module Layout Designer sau này

Layout Designer sẽ là module riêng.

Hệ thống hiện tại chỉ cần chuẩn bị bằng cách:

* models có thể encode/decode;
* layout ID ổn định;
* frame dùng canvas reference;
* repository không phụ thuộc bundle về mặt protocol;
* renderer không phụ thuộc nguồn layout;
* validation có thể dùng lại;
* JSON schema có `schemaVersion`.

Không xây:

* editor UI;
* drag handles;
* resize;
* snap grid;
* export JSON;
* layout authoring tools.

Không thêm code giả hoặc màn hình rỗng cho Layout Designer trong task này.

Chỉ ghi rõ extension point trong tài liệu.

---

# 21. Error handling

Các lỗi cần có dạng rõ ràng:

```swift
enum AlbumLayoutError: Error {
    case resourceNotFound
    case unsupportedSchemaVersion(Int)
    case duplicateLayoutId(String)
    case layoutNotFound(String)
    case invalidPhotoCount(layoutId: String)
    case slotCountMismatch(layoutId: String)
    case duplicateSlotId(layoutId: String, slotId: String)
    case invalidCanvas(layoutId: String)
    case invalidFrame(layoutId: String, slotId: String)
    case slotOutsideCanvas(layoutId: String, slotId: String)
    case unsupportedFormat(layoutId: String)
}
```

Có thể điều chỉnh tên case cho phù hợp codebase.

Không dùng `fatalError` trong production loader.

Xcode Preview có thể hiển thị error state dễ đọc.

---

# 22. Tests

Viết unit tests tối thiểu:

## Decode

* Decode file JSON thành công.
* Có đúng ít nhất 12 layout.
* Có layout cho 1, 2, 3 và 4 ảnh.

## Identity

* Không trùng layout ID.
* Không trùng slot ID trong cùng layout.

## Slot count

* `slots.count == photoCount`.

## Frames

* Canvas hợp lệ.
* Frame có width/height dương.
* Frame nằm trong canvas.

## Filtering

* Lọc đúng theo `photoCount`.
* Lọc đúng theo `format`.
* Không trả layout portrait khi yêu cầu square nếu layout không hỗ trợ square.

## Lookup

* Tìm layout theo ID thành công.
* ID không tồn tại trả lỗi đúng.

## Assignment validation

* Assignment trỏ đến slot hợp lệ.
* Không có hai assignment cùng một slot.
* Có thể thiếu assignment và renderer dùng placeholder.
* Assignment thừa hoặc slot không tồn tại phải được phát hiện ở validation layer.

Không viết snapshot test hoặc ImageRenderer test.

---

# 23. Performance

* JSON chỉ decode một lần.
* Repository cache library trong memory.
* Renderer không tìm kiếm tuyến tính lặp lại nhiều lần trong body nếu có thể tránh.
* Chuyển assignments thành dictionary theo `slotId` trước khi render.
* Dùng `ForEach` với ID ổn định.
* Không sử dụng nested `GeometryReader`.
* Một `GeometryReader` ở cấp canvas là đủ.
* Không load full-resolution image trong Preview hoặc thumbnail page.
* Không xây cache ảnh mới trong task này.

---

# 24. Accessibility

Mỗi slot ảnh cần có accessibility label từ photo metadata nếu caller cung cấp.

Nếu chưa có metadata:

```text
Photo 1
Photo 2
```

Các layout thumbnail trong gallery:

```text
Three-photo layout, Hero Top
```

Không dùng slot ID kỹ thuật làm accessibility label trong production.

---

# 25. Localization

Code và model dùng tiếng Anh.

Các chuỗi UI trong gallery hoặc preview phải đi qua hệ thống localization hiện tại:

```text
album.layout.gallery.title
album.layout.photo_count
album.layout.page
album.layout.format.square
album.layout.format.portrait
album.layout.format.landscape
```

Không hardcode chuỗi UI mới nếu project đã có `Localizable.xcstrings`.

Tên layout trong JSON hiện có thể dùng tên tiếng Anh phục vụ development. Để chuẩn bị localization tốt hơn, ưu tiên trường:

```json
"nameKey": "album.layout.square.3.hero_top"
```

thay vì chỉ có:

```json
"name": "Hero Top"
```

Domain model nên dùng:

```swift
let nameKey: String
```

Preview lấy:

```swift
String(localized: String.LocalizationValue(layout.nameKey))
```

Nếu cách tạo localization key động không phù hợp với hệ thống hiện tại, giữ `nameKey` như metadata và dùng mapping localization ở UI layer. Không tạo custom localization manager.

---

# 26. Quy ước ID

Dùng dạng:

```text
{format}.{photoCount}.{variant}
```

Ví dụ:

```text
square.1.full-bleed
square.1.inset
square.2.vertical-split
square.3.hero-top
square.4.grid
```

ID:

* lowercase;
* dùng dấu gạch ngang;
* không chứa khoảng trắng;
* không đổi sau khi đã có album sử dụng;
* không dùng tên mang tính UI có thể thay đổi.

`layoutId` là persistent identifier.

---

# 27. Acceptance criteria

Task chỉ hoàn thành khi:

1. Có module Album Layout riêng.
2. Có file JSON hợp lệ.
3. Có ít nhất 12 layout vuông.
4. Có từ 1 đến 4 ảnh.
5. Mỗi nhóm có ít nhất 3 phương án.
6. Không có `switch photoCount` để tự dựng layout bằng SwiftUI.
7. Mọi layout được render bằng một renderer chung.
8. Layout lookup sử dụng repository.
9. JSON được decode và validate.
10. Album page lưu `layoutId` và slot assignments.
11. Preview Gallery hiển thị toàn bộ layout.
12. Album Pages Preview dùng layout thật từ JSON.
13. Preview không lệch trái và không overflow.
14. Placeholder hiển thị khi thiếu ảnh.
15. Unit tests parsing và validation pass.
16. App build pass.
17. Không chạy simulator.
18. Không dùng ImageRenderer.
19. Không viết snapshot tests.
20. Có tài liệu mô tả cách thêm layout mới.

---

# 28. Development constraints

* Không sửa kiến trúc Album ngoài phạm vi cần thiết.
* Không đổi tên persistent fields hiện có nếu chưa đánh giá migration.
* Không thêm dependency bên thứ ba.
* Không dùng framework layout JSON bên ngoài.
* Không xây Layout Designer.
* Không làm drag-and-drop.
* Không over-engineer một hệ thống xuất bản photobook đầy đủ.
* Không đặt tất cả code trong Preview file.
* Không hardcode 12 layout bằng các `VStack/HStack` riêng.
* Không chạy simulator.
* Chỉ build và chạy unit tests phù hợp.
* Không thay đổi hero cover đã được người dùng xác nhận là ổn, ngoài tích hợp phần page phía dưới.

---

# 29. Tài liệu đầu ra

Tạo:

```text
docs/ALBUM_LAYOUT_SYSTEM.md
```

Nội dung:

* kiến trúc;
* JSON schema;
* cách renderer hoạt động;
* page format;
* cách thêm layout mới;
* quy tắc canvas;
* validation;
* persistent ID;
* extension point cho Layout Designer;
* danh sách layout hiện có.

---

# 30. Báo cáo hoàn thành

Khi hoàn thành, báo cáo:

```text
1. Files created
2. Files modified
3. Layout IDs created
4. JSON schema summary
5. Renderer architecture
6. Validation rules implemented
7. Preview screens created
8. Tests executed
9. Build result
10. Known limitations
```

Không chỉ trả lời “done”.

---

## Ghi chú quyết định kiến trúc

Hệ tọa độ canvas tham chiếu giúp layout độc lập với độ phân giải và kích thước hiển thị. Tuy nhiên, nó không có nghĩa rằng một layout duy nhất luôn đẹp trên mọi tỷ lệ trang.

Do đó:

```text
Layout coordinates
→ resolution-independent

supportedFormats
→ aspect-ratio compatibility
```

Hai khái niệm này phải được giữ riêng.

Sprint hiện tại tập trung vào layout trang vuông. Portrait và landscape được chuẩn bị ở model và renderer nhưng chưa cần tạo đầy đủ thư viện mẫu.
