# MODULE — PHOTO EDITOR

## 1. Tổng quan

Photo Editor là module chỉnh sửa ảnh độc lập của ứng dụng Nizi.

Module cho phép người dùng:

* Mở và chỉnh sửa một ảnh riêng lẻ.
* Áp preset màu với cường độ từ `0–100%`.
* Điều chỉnh một số thông số ảnh cơ bản.
* Tự động cải thiện ảnh bằng Auto Enhance.
* So sánh ảnh đã chỉnh với ảnh gốc.
* Lưu chỉnh sửa theo cơ chế không phá hủy ảnh gốc.
* Áp phong cách màu cho toàn bộ Album hoặc Event.

Photo Editor không phụ thuộc trực tiếp vào giao diện Album hoặc Event.

Album, Event hoặc các module khác chỉ cần truyền ảnh và ngữ cảnh chỉnh sửa vào Photo Editor.

---

# 2. Mục tiêu

## 2.1. Mục tiêu chính

* Cung cấp trải nghiệm chỉnh ảnh đơn giản, dễ hiểu.
* Người dùng không phải thao tác với quá nhiều thông số chuyên nghiệp.
* Tập trung vào preset và cường độ preset.
* Bảo toàn ảnh gốc.
* Cho phép áp dụng phong cách đồng nhất cho một Album hoặc Event.
* Có thể tái sử dụng Photo Editor từ nhiều vị trí trong ứng dụng.

## 2.2. Không thuộc phạm vi ban đầu

Photo Editor V1 không nhằm trở thành ứng dụng chỉnh ảnh chuyên nghiệp như Lightroom hoặc VSCO.

Không phát triển trong V1:

* HSL theo từng màu.
* Tone curve chỉnh thủ công.
* Mask theo vùng.
* Brush.
* Xóa vật thể.
* Thay nền.
* Retouch khuôn mặt.
* Layer.
* Text hoặc sticker.
* Ghép ảnh.
* Preset marketplace.
* Người dùng tự tạo preset.

---

# 3. Nguyên tắc thiết kế

## 3.1. Chỉnh sửa không phá hủy ảnh gốc

Photo Editor không ghi đè lên ảnh gốc trong thư viện Photos.

App chỉ lưu thông tin chỉnh sửa dưới dạng `edit recipe`.

Ví dụ:

```json
{
  "photoId": "photo_123",
  "presetId": "warm-memory",
  "presetIntensity": 0.65,
  "adjustments": {
    "exposure": 0.08,
    "contrast": 0.04,
    "highlights": -0.15,
    "shadows": 0.12,
    "warmth": 0.03,
    "saturation": 0.02
  },
  "autoEnhanceApplied": true,
  "updatedAt": "2026-07-26T08:30:00+07:00"
}
```

Ảnh hoàn chỉnh chỉ được render khi:

* Hiển thị preview chất lượng cao.
* Xuất ảnh.
* Chia sẻ ảnh.
* Tạo photobook.
* Lưu một bản mới vào thư viện Photos, nếu người dùng yêu cầu.

## 3.2. Preset là trải nghiệm chính

Preset là công cụ chỉnh màu chính.

Người dùng chỉ cần:

1. Chọn preset.
2. Chỉnh cường độ từ `0–100%`.
3. Lưu.

Các thông số Adjust là phần hỗ trợ, không phải trọng tâm.

## 3.3. Auto Enhance xử lý riêng từng ảnh

Auto Enhance được tính toán dựa trên đặc điểm của từng ảnh.

Không sao chép nguyên thông số Auto Enhance của một ảnh sang tất cả ảnh khác.

## 3.4. Áp dụng toàn bộ chỉ mặc định áp phong cách

Khi áp dụng cho toàn bộ Album hoặc Event, mặc định chỉ áp:

* Preset.
* Cường độ preset.

Không mặc định áp đồng loạt:

* Exposure.
* Highlights.
* Shadows.
* White balance.
* Crop.
* Rotate.

---

# 4. Cách truy cập Photo Editor

Photo Editor phải có thể được mở từ nhiều nguồn.

## 4.1. Từ Album

Flow:

```text
Album
→ Mở ảnh
→ Full-screen Photo Viewer
→ Edit
→ Photo Editor
```

Context truyền vào:

```swift
EditorContext(
    sourceType: .album,
    sourceId: albumId,
    photoId: photoId,
    photoIds: albumPhotoIds
)
```

## 4.2. Từ Event

Flow:

```text
Event
→ Mở ảnh
→ Full-screen Photo Viewer
→ Edit
→ Photo Editor
```

Context truyền vào:

```swift
EditorContext(
    sourceType: .event,
    sourceId: eventId,
    photoId: photoId,
    photoIds: eventPhotoIds
)
```

## 4.3. Mở độc lập

Photo Editor có thể được mở trực tiếp với một ảnh mà không cần Album hoặc Event.

Ví dụ:

```swift
EditorContext(
    sourceType: .standalone,
    sourceId: nil,
    photoId: photoId,
    photoIds: [photoId]
)
```

Trong chế độ độc lập:

* Cho phép chỉnh ảnh.
* Cho phép lưu chỉnh sửa cho ảnh hiện tại.
* Không hiển thị tùy chọn áp dụng toàn Album hoặc Event.

## 4.4. Khả năng mở rộng

Sau này Photo Editor có thể được gọi từ:

* Search.
* Memory Candidate.
* Favorites.
* Photobook Builder.
* Photo Detail.
* AI Suggestion.
* Shared Collection.

Các module gọi không cần biết cách editor render ảnh.

---

# 5. Editor Context

Photo Editor nhận vào một `EditorContext`.

```swift
enum EditorSourceType: String, Codable {
    case standalone
    case album
    case event
}

struct EditorContext: Codable {
    let sourceType: EditorSourceType
    let sourceId: String?
    let photoId: String
    let photoIds: [String]
}
```

## 5.1. Ý nghĩa

* `sourceType`: nguồn mở editor.
* `sourceId`: ID của Album hoặc Event.
* `photoId`: ảnh đang được chỉnh.
* `photoIds`: danh sách ảnh trong phạm vi hiện tại.

`photoIds` được dùng khi người dùng chọn:

* Áp dụng cho toàn bộ.
* Áp dụng cho các ảnh phù hợp.
* Chuyển qua lại giữa các ảnh trong editor, nếu hỗ trợ sau này.

---

# 6. Giao diện Photo Editor

## 6.1. Cấu trúc tổng thể

```text
┌────────────────────────────────────┐
│ Hủy          Chỉnh sửa        Lưu  │
├────────────────────────────────────┤
│                                    │
│                                    │
│              Ảnh lớn               │
│                                    │
│                                    │
├────────────────────────────────────┤
│   Preset       Adjust       Auto   │
├────────────────────────────────────┤
│                                    │
│         Nội dung công cụ            │
│                                    │
└────────────────────────────────────┘
```

## 6.2. Thanh điều hướng

### Hủy

Khi chưa có thay đổi:

* Đóng editor ngay.

Khi đã có thay đổi chưa lưu:

Hiển thị xác nhận:

```text
Hủy các thay đổi?

[Tiếp tục chỉnh] [Hủy thay đổi]
```

### Lưu

Lưu chỉnh sửa hiện tại.

Nếu editor được mở từ Album hoặc Event, sau khi bấm Lưu có thể hiển thị lựa chọn phạm vi áp dụng.

## 6.3. Khu vực hiển thị ảnh

Yêu cầu:

* Ảnh nằm giữa màn hình.
* Giữ đúng tỷ lệ.
* Có nền tối hoặc trung tính.
* Hỗ trợ zoom và pan nếu cần.
* Preview cập nhật gần như tức thì khi chọn preset hoặc kéo slider.

Tương tác:

* Chạm giữ để xem ảnh gốc.
* Nhả tay để quay lại ảnh đã chỉnh.
* Có thể có nút Before/After nhỏ nếu chạm giữ không đủ rõ.

## 6.4. Thanh công cụ

V1 gồm ba nhóm:

```text
Preset | Adjust | Auto
```

Mặc định khi mở editor:

* Hiển thị tab Preset.
* Nếu ảnh đã có chỉnh sửa trước đó, phục hồi trạng thái đã lưu.

---

# 7. Preset

## 7.1. Danh sách preset

V1 sử dụng dưới 10 preset.

Danh sách đề xuất:

1. Original
2. Ký ức ấm
3. Mùa hè
4. Dịu nhẹ
5. Film
6. Điện ảnh
7. Đêm phố
8. Đen trắng

Tên preset có thể được thay đổi trong quá trình thiết kế bộ màu.

## 7.2. Giao diện

```text
[Gốc] [Ký ức] [Mùa hè] [Dịu nhẹ] [Film] ...

Cường độ                              65%
────────────────●────────────────────────
```

Mỗi preset hiển thị:

* Thumbnail preview.
* Tên ngắn.
* Trạng thái đang chọn.

## 7.3. Cường độ preset

Mỗi preset hỗ trợ cường độ từ `0–100%`.

Ý nghĩa:

* `0%`: ảnh gốc.
* `100%`: toàn bộ hiệu ứng preset.
* Giá trị giữa: trộn ảnh gốc và ảnh đã áp preset.

Công thức khái niệm:

```text
Output = Original × (1 - intensity)
       + PresetResult × intensity
```

## 7.4. Cường độ mặc định

Mỗi preset có thể có cường độ mặc định riêng.

Ví dụ:

```json
{
  "id": "warm-memory",
  "name": "Ký ức ấm",
  "defaultIntensity": 0.65
}
```

Khi chọn preset lần đầu:

* Slider chuyển đến cường độ mặc định của preset.
* Người dùng có thể thay đổi.

Preset Original luôn có intensity bằng `0`.

## 7.5. Chọn lại preset

Khi người dùng đổi preset:

* Giữ nguyên các Adjust thủ công.
* Chỉ thay preset và cường độ.
* Preview cập nhật ngay.

Có thể hỗ trợ double tap vào preset để đưa intensity về giá trị mặc định.

---

# 8. Adjust

## 8.1. Phạm vi V1

V1 chỉ cung cấp các thông số cơ bản:

* Exposure.
* Contrast.
* Highlights.
* Shadows.
* Warmth.
* Saturation.

Tên hiển thị tiếng Việt:

* Sáng.
* Tương phản.
* Vùng sáng.
* Vùng tối.
* Độ ấm.
* Màu sắc.

## 8.2. Giao diện

```text
Sáng        Tương phản      Vùng sáng
Vùng tối    Độ ấm           Màu sắc
```

Khi chọn một thông số:

```text
Sáng                                     +8
────────────────────●──────────────────────
```

## 8.3. Giá trị

Nên lưu dưới dạng giá trị chuẩn hóa.

Ví dụ:

```swift
struct PhotoAdjustments: Codable, Equatable {
    var exposure: Float = 0
    var contrast: Float = 0
    var highlights: Float = 0
    var shadows: Float = 0
    var warmth: Float = 0
    var saturation: Float = 0
}
```

Giá trị UI có thể hiển thị từ `-100` đến `+100`, nhưng engine chuyển sang phạm vi phù hợp với từng Core Image filter.

## 8.4. Reset

Cần có:

* Đặt lại thông số hiện tại.
* Đặt lại toàn bộ Adjust.
* Đặt lại toàn bộ ảnh về Original.

---

# 9. Auto Enhance

## 9.1. Vai trò

Auto Enhance tự động cải thiện ảnh bằng cách phân tích các đặc điểm cơ bản như:

* Độ sáng tổng thể.
* Vùng bị tối.
* Vùng highlight quá mạnh.
* Độ tương phản.
* Độ bão hòa.
* Cân bằng màu cơ bản.

V1 ưu tiên sử dụng:

* Core Image.
* Histogram.
* Các heuristic/rule-based adjustments.
* API tự động điều chỉnh có sẵn của iOS nếu phù hợp.

Không bắt buộc sử dụng Generative AI hoặc gọi server.

## 9.2. Giao diện

```text
✨ Tự động cải thiện

Nizi sẽ cân bằng sáng, vùng tối và màu sắc cho ảnh này.

[Áp dụng]
```

Sau khi áp dụng:

```text
Đã tự động cải thiện

Sáng        +8
Vùng sáng  -15
Vùng tối   +12
Màu sắc     +4

[Hoàn tác]
```

## 9.3. Auto Enhance phải minh bạch

Auto Enhance không nên là một hiệu ứng ẩn không thể chỉnh lại.

Sau khi chạy:

* Các giá trị Adjust được cập nhật.
* Người dùng có thể vào tab Adjust để xem và thay đổi.
* Có thể hoàn tác Auto Enhance.

## 9.4. Quan hệ với preset

Pipeline đề xuất:

```text
Ảnh gốc
→ Auto Enhance / Adjust
→ Preset
→ Preset intensity
→ Texture cuối
→ Preview
```

Auto Enhance xử lý chất lượng cơ bản của từng ảnh.

Preset tạo phong cách chung.

---

# 10. Thứ tự xử lý ảnh

Pipeline V1:

```text
Original CIImage
    ↓
Orientation normalization
    ↓
Auto Enhance values
    ↓
Manual Adjust
    ↓
Preset LUT / color processing
    ↓
Preset intensity blending
    ↓
Optional grain / bloom / vignette
    ↓
Preview hoặc Export
```

## 10.1. Quy tắc

* Auto Enhance và Manual Adjust thuộc cùng nhóm correction.
* Preset thuộc nhóm style.
* Các hiệu ứng texture thuộc preset nhưng có thể được điều chỉnh nội bộ theo intensity.
* Không render và ghi đè ảnh gốc.

---

# 11. Lưu chỉnh sửa

## 11.1. Lưu một ảnh

Khi mở độc lập:

```text
[Lưu chỉnh sửa]
```

Khi bấm:

* Lưu edit recipe cho ảnh hiện tại.
* Đóng editor.
* Trả kết quả về màn hình gọi.

## 11.2. Khi mở từ Album hoặc Event

Sau khi bấm Lưu, hiển thị bottom sheet:

```text
Lưu chỉnh sửa

[Chỉ ảnh này]

[Áp phong cách cho toàn bộ Album]

[Hủy]
```

Nếu mở từ Event:

```text
[Áp phong cách cho toàn bộ Event]
```

## 11.3. Chỉ ảnh này

Lưu đầy đủ:

* Preset.
* Preset intensity.
* Adjust.
* Auto Enhance state.
* Các dữ liệu chỉnh sửa riêng của ảnh.

## 11.4. Áp phong cách cho toàn bộ

Mặc định chỉ áp:

* Preset.
* Preset intensity.

Hiển thị xác nhận:

```text
Áp phong cách cho toàn bộ Album?

Preset: Ký ức ấm
Cường độ: 65%

Các điều chỉnh sáng và màu riêng của ảnh này
sẽ không được sao chép.

[Hủy] [Áp dụng]
```

## 11.5. Tùy chọn nâng cao

Có thể cung cấp thêm:

```text
☑ Áp preset và cường độ
☐ Tự động cải thiện riêng từng ảnh
```

Không nên cho phép sao chép Adjust thủ công sang toàn bộ theo mặc định.

---

# 12. Áp dụng cho toàn Album hoặc Event

## 12.1. Album style

Album có thể lưu phong cách mặc định:

```swift
struct CollectionStyle: Codable {
    var presetId: String?
    var presetIntensity: Float
    var autoEnhanceMode: AutoEnhanceMode
}
```

Ví dụ:

```json
{
  "presetId": "warm-memory",
  "presetIntensity": 0.65,
  "autoEnhanceMode": "perPhoto"
}
```

## 12.2. Event style

Event có cấu trúc style tương tự Album.

## 12.3. Kế thừa

Một ảnh có thể:

* Kế thừa style của Album/Event.
* Có chỉnh sửa riêng.
* Hoàn toàn bỏ qua style chung.

Ví dụ:

```text
Album:
Ký ức ấm 65%

Ảnh A:
Dùng style của Album

Ảnh B:
Preset intensity 45%
Exposure +10

Ảnh C:
Original
```

## 12.4. Thứ tự ưu tiên

```text
Photo override
→ Collection style
→ Original
```

Nếu ảnh có `photo override`, cấu hình riêng của ảnh được ưu tiên.

Nếu không có override, ảnh sử dụng style của Album hoặc Event.

---

# 13. Mô hình dữ liệu đề xuất

## 13.1. PhotoEditRecipe

```swift
struct PhotoEditRecipe: Codable, Equatable {
    let photoId: String

    var presetId: String?
    var presetIntensity: Float

    var adjustments: PhotoAdjustments

    var autoEnhanceApplied: Bool
    var autoEnhanceVersion: String?

    var inheritsCollectionStyle: Bool

    var createdAt: Date
    var updatedAt: Date
}
```

## 13.2. CollectionEditStyle

Dùng chung cho Album và Event:

```swift
enum CollectionType: String, Codable {
    case album
    case event
}

struct CollectionEditStyle: Codable, Equatable {
    let collectionType: CollectionType
    let collectionId: String

    var presetId: String?
    var presetIntensity: Float

    var autoEnhanceEachPhoto: Bool

    var createdAt: Date
    var updatedAt: Date
}
```

## 13.3. PresetDefinition

```swift
struct PresetDefinition: Codable, Identifiable {
    let id: String
    let name: String

    let lutResource: String?
    let defaultIntensity: Float

    let grainAmount: Float
    let bloomAmount: Float
    let vignetteAmount: Float

    let isMonochrome: Bool
    let sortOrder: Int
    let isActive: Bool
}
```

Preset có thể được định nghĩa bằng JSON và resource trong app bundle.

---

# 14. Kiến trúc module

## 14.1. Các thành phần chính

```text
PhotoEditor
├── UI
│   ├── PhotoEditorView
│   ├── PresetPanel
│   ├── AdjustPanel
│   ├── AutoEnhancePanel
│   └── SaveScopeSheet
│
├── State
│   ├── PhotoEditorViewModel
│   └── PhotoEditSession
│
├── Rendering
│   ├── PhotoRenderEngine
│   ├── PresetRenderer
│   ├── AdjustmentRenderer
│   └── PreviewRenderer
│
├── AutoEnhance
│   ├── AutoEnhanceService
│   ├── ImageAnalyzer
│   └── AutoEnhanceRules
│
├── Data
│   ├── PhotoEditRepository
│   ├── CollectionStyleRepository
│   └── PresetRepository
│
└── Models
    ├── EditorContext
    ├── PhotoEditRecipe
    ├── PhotoAdjustments
    ├── PresetDefinition
    └── CollectionEditStyle
```

## 14.2. Trách nhiệm

### PhotoEditorView

* Hiển thị giao diện.
* Nhận thao tác người dùng.
* Không trực tiếp xử lý Core Image.

### PhotoEditorViewModel

* Quản lý trạng thái phiên chỉnh sửa.
* Chọn preset.
* Cập nhật intensity.
* Cập nhật Adjust.
* Gọi Auto Enhance.
* Gọi render preview.
* Lưu recipe.

### PhotoRenderEngine

* Xây pipeline Core Image.
* Render preview.
* Render ảnh full resolution khi cần.
* Không quản lý database.

### AutoEnhanceService

* Phân tích ảnh.
* Trả về các giá trị Adjust đề xuất.
* Không tự lưu dữ liệu.

### Repository

* Đọc và ghi edit recipe.
* Đọc và ghi style của Album/Event.
* Không xử lý hình ảnh.

---

# 15. Render preview và ảnh đầy đủ

## 15.1. Preview

Khi chỉnh sửa:

* Sử dụng ảnh preview có độ phân giải vừa đủ theo màn hình.
* Không tải ảnh gốc full resolution cho mỗi thay đổi slider.
* Debounce các thay đổi slider nếu cần.
* Ưu tiên GPU qua Core Image.

## 15.2. Full resolution

Chỉ render full resolution khi:

* Xuất ảnh.
* Chia sẻ.
* Lưu bản mới.
* Tạo photobook.
* Cần cache ảnh chất lượng cao.

## 15.3. iCloud Photos

Nếu ảnh gốc chưa có trên thiết bị:

* Editor có thể bắt đầu với preview local.
* Hiển thị trạng thái tải bản gốc khi cần export.
* Không chặn toàn bộ giao diện chỉ vì ảnh gốc chưa tải xong.

---

# 16. Quản lý trạng thái phiên chỉnh sửa

Khi mở editor, tạo một `PhotoEditSession`.

```swift
struct PhotoEditSession {
    let originalRecipe: PhotoEditRecipe?
    var workingRecipe: PhotoEditRecipe
    var hasUnsavedChanges: Bool
}
```

## 16.1. Hủy

Khôi phục `originalRecipe`.

## 16.2. Reset

Đưa `workingRecipe` về trạng thái Original.

## 16.3. Undo/Redo

V1 không bắt buộc có undo nhiều bước.

Tối thiểu cần:

* Undo Auto Enhance.
* Reset Adjust.
* Reset toàn bộ.

V2 có thể bổ sung lịch sử thao tác.

---

# 17. Trạng thái đặc biệt

## 17.1. Ảnh chụp màn hình

Có thể hiển thị cảnh báo nhẹ:

```text
Preset màu có thể không phù hợp với ảnh chụp màn hình.
```

Không bắt buộc chặn chỉnh sửa.

Khi áp toàn Album/Event, mặc định có thể bỏ qua screenshot.

## 17.2. Video

Photo Editor V1 chỉ xử lý ảnh tĩnh.

Nếu asset là video:

* Không hiển thị nút Edit ảnh.
* Hoặc chuyển sang Video Editor sau này.

## 17.3. Live Photo

V1 có thể chỉnh phần ảnh đại diện tĩnh.

Không xử lý màu cho toàn bộ chuyển động của Live Photo.

Cần ghi rõ trong UI nếu lưu thành ảnh tĩnh.

## 17.4. RAW

V1 không cần giao diện chỉnh RAW chuyên sâu.

Có thể sử dụng ảnh đã render từ Photos framework.

## 17.5. Ảnh đã chỉnh trong Apple Photos

Photo Editor sử dụng phiên bản ảnh mà Photos framework cung cấp theo cấu hình đã chọn.

Cần thống nhất một trong hai:

* Dùng current version đã được chỉnh trong Apple Photos.
* Dùng original resource.

Khuyến nghị V1 dùng current version để kết quả phù hợp với những gì người dùng đang nhìn thấy trong Photos.

---

# 18. Hiệu năng

## 18.1. Yêu cầu trải nghiệm

* Chọn preset: preview phản hồi nhanh.
* Kéo intensity: ảnh cập nhật liên tục hoặc gần liên tục.
* Kéo Adjust: không giật rõ rệt.
* Không giữ nhiều ảnh full resolution trong RAM.
* Hủy render cũ khi có yêu cầu mới.
* Cache thumbnail preset cho ảnh hiện tại.

## 18.2. Preset thumbnail

Khi mở tab Preset:

* Sinh thumbnail nhỏ cho từng preset.
* Chỉ render dưới 10 thumbnail.
* Cache trong phiên chỉnh sửa.
* Không lưu cache lâu dài nếu không cần.

## 18.3. Memory

* Dùng autorelease pool tại các đoạn render nặng.
* Không chuyển đổi liên tục giữa `UIImage` và `CIImage`.
* Tái sử dụng `CIContext`.
* Release preview cũ khi có preview mới.

---

# 19. Quy tắc UX

* Preset là tab mặc định.
* Không hiển thị quá nhiều thông số.
* Mỗi màn hình chỉ có một hành động chính rõ ràng.
* Luôn cho phép xem ảnh gốc.
* Không ghi đè ảnh gốc.
* Không mặc định áp Adjust của một ảnh cho toàn bộ.
* Luôn giải thích rõ phạm vi khi người dùng chọn áp dụng toàn bộ.
* Nếu áp dụng cho nhiều ảnh, hiển thị tiến trình nhưng không khóa toàn bộ app nếu có thể.
* Sau khi lưu, cập nhật ảnh hiển thị tại màn hình gọi.

---

# 20. API nội bộ đề xuất

## 20.1. Mở editor

```swift
protocol PhotoEditorCoordinator {
    func openEditor(context: EditorContext)
}
```

## 20.2. Render preview

```swift
protocol PhotoRendering {
    func renderPreview(
        photoId: String,
        recipe: PhotoEditRecipe,
        targetSize: CGSize
    ) async throws -> CGImage
}
```

## 20.3. Auto Enhance

```swift
protocol AutoEnhancing {
    func analyze(photoId: String) async throws -> PhotoAdjustments
}
```

## 20.4. Lưu một ảnh

```swift
protocol PhotoEditRepository {
    func getRecipe(photoId: String) async throws -> PhotoEditRecipe?
    func saveRecipe(_ recipe: PhotoEditRecipe) async throws
    func deleteRecipe(photoId: String) async throws
}
```

## 20.5. Lưu style collection

```swift
protocol CollectionStyleRepository {
    func getStyle(
        type: CollectionType,
        id: String
    ) async throws -> CollectionEditStyle?

    func saveStyle(_ style: CollectionEditStyle) async throws
}
```

---

# 21. Kết quả trả về màn hình gọi

Khi editor đóng sau khi lưu:

```swift
struct PhotoEditorResult {
    let photoId: String
    let didSave: Bool
    let collectionStyleChanged: Bool
    let affectedPhotoIds: [String]
}
```

Album hoặc Event nhận kết quả để:

* Refresh ảnh hiện tại.
* Refresh thumbnail.
* Refresh cover nếu cần.
* Hiển thị badge hoặc trạng thái đã chỉnh sửa.

---

# 22. Các bước triển khai đề xuất

## Sprint 1 — Editor foundation

* Tạo module Photo Editor độc lập.
* EditorContext.
* PhotoEditorView.
* PhotoEditorViewModel.
* Load ảnh preview.
* Hủy và Lưu.
* Chạm giữ xem ảnh gốc.
* Lưu edit recipe cơ bản.

## Sprint 2 — Preset

* Preset repository.
* Dưới 10 preset.
* Thumbnail preset.
* Chọn preset.
* Intensity 0–100%.
* Render bằng Core Image.
* Reset về Original.

## Sprint 3 — Adjust

* Exposure.
* Contrast.
* Highlights.
* Shadows.
* Warmth.
* Saturation.
* Reset từng thông số.
* Reset toàn bộ Adjust.

## Sprint 4 — Auto Enhance

* Phân tích histogram cơ bản.
* Sinh Adjust đề xuất.
* Hiển thị kết quả.
* Cho phép chỉnh tiếp.
* Hoàn tác Auto Enhance.

## Sprint 5 — Album/Event integration

* Mở Photo Editor từ Album.
* Mở Photo Editor từ Event.
* Lưu chỉ ảnh hiện tại.
* Áp preset và intensity cho toàn bộ.
* Lưu CollectionEditStyle.
* Ảnh hỗ trợ kế thừa hoặc override.

## Sprint 6 — Performance and export

* Preview resize phù hợp màn hình.
* Cache preset thumbnail.
* Hủy render cũ.
* Full-resolution render.
* Export/share integration.
* Kiểm tra memory với ảnh lớn.

---

# 23. Tiêu chí hoàn thành V1

Photo Editor V1 được coi là hoàn thành khi:

* Có thể mở độc lập với một ảnh.
* Có thể mở từ Album.
* Có thể mở từ Event.
* Có dưới 10 preset.
* Mỗi preset có intensity `0–100%`.
* Có sáu Adjust cơ bản.
* Có Auto Enhance cơ bản.
* Có thể xem ảnh gốc.
* Không ghi đè ảnh gốc.
* Lưu được recipe riêng cho từng ảnh.
* Có thể áp preset và intensity cho toàn bộ Album hoặc Event.
* Auto Enhance được tính riêng theo từng ảnh.
* Chỉnh sửa riêng của ảnh có thể override style của Album/Event.
* Preview hoạt động ổn định và không gây tăng RAM bất thường.

---

# 24. Kết luận kiến trúc

Photo Editor là một module độc lập, không đặt logic chỉnh ảnh bên trong Album hoặc Event.

Album và Event chỉ chịu trách nhiệm:

* Cung cấp ảnh.
* Cung cấp danh sách ảnh trong phạm vi.
* Mở Photo Editor.
* Nhận kết quả sau khi lưu.
* Hiển thị ảnh đã được render theo recipe.

Photo Editor chịu trách nhiệm toàn bộ:

* Preset.
* Intensity.
* Adjust.
* Auto Enhance.
* Render.
* Lưu recipe.
* Áp phong cách cho phạm vi Album hoặc Event.

Cấu trúc này giúp Photo Editor có thể được tái sử dụng ở bất kỳ vị trí nào trong Nizi mà không phải viết lại logic chỉnh ảnh.
