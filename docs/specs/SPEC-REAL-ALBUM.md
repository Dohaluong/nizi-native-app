

# SPEC — Real Album Experience

## 1. Mục tiêu

Biến kết quả của Album Draft Planner thành một Album thực tế mà người dùng có thể:

* xem bằng ảnh thật từ Apple Photos;
* xem bìa Album;
* lật qua từng Spread gồm hai trang;
* xem toàn bộ Album dưới dạng photobook;
* chỉnh sửa cơ bản;
* đóng app và mở lại Album mà không mất cấu trúc;
* xử lý an toàn khi một ảnh không còn tồn tại hoặc chưa tải từ iCloud.

Sprint này không tiếp tục mở rộng Planner.

Planner hiện tại được coi là đủ dùng cho phiên bản đầu:

```text
Selected Photos
    ↓
Album Draft Planner
    ↓
Album Draft
    ↓
Real Album Viewer
```

Trọng tâm Sprint:

```text
Photo Resolution
Rendering
Viewing
Editing
Persistence
```

---

# 2. Kết quả cuối cùng mong muốn

Khi người dùng nhấn **Create Album**:

```text
Event Detail
    ↓
Planner
    ↓
Save Album Draft
    ↓
Open Album Detail
```

Màn hình Album Detail phải có:

```text
Book Cover

Album Information

Two-page Spread Viewer

Edit Album
```

Ví dụ:

```text
Sydney
14–18 January 2026
32 photos
6 spreads
Sydney Opera House
```

Khi mở Spread:

```text
┌───────────────┬───────────────┐
│               │               │
│    Page 1     │    Page 2     │
│               │               │
└───────────────┴───────────────┘
```

Tất cả slot phải hiển thị ảnh thật, không còn placeholder mock trong production.

---

# 3. Phạm vi triển khai

## Có trong Sprint

1. Production Album Photo Provider.
2. PHAsset lookup bằng local identifier.
3. Thumbnail và display image loading.
4. iCloud-aware loading.
5. Caching và request cancellation.
6. Real Album Detail.
7. Book-style cover.
8. Two-page Spread Viewer.
9. Page indicator và navigation.
10. Album overview metadata.
11. Chỉnh cover.
12. Đổi layout của Page.
13. Hoán đổi ảnh giữa các slot.
14. Xóa ảnh khỏi Page.
15. Xóa Page hoặc Spread theo quy tắc an toàn.
16. Lưu thay đổi vào SwiftData.
17. Xử lý missing asset.
18. Preview và Diagnostics cho ảnh thật.

## Chưa làm trong Sprint

* Export PDF.
* Đặt in photobook.
* Upload Album lên server.
* Đồng bộ nhiều thiết bị.
* AI crop.
* Nhận diện khuôn mặt.
* Chỉnh màu ảnh.
* Filter ảnh.
* Chèn text tự do vào Page.
* Kéo ảnh từ Event khác vào Album.
* Tạo layout tùy chỉnh bằng editor.
* Animation lật trang 3D.
* Undo history phức tạp.
* Collaboration.
* Relational database đầy đủ cho từng Page.

---

# 4. Nguyên tắc kiến trúc

Phải giữ ranh giới:

```text
Photos Framework
    ↓
AlbumPhotoProvider
    ↓
AlbumPhotoView
    ↓
AlbumPageRenderer
```

`AlbumPageRenderer` không được:

* gọi `PHAsset.fetchAssets`;
* sử dụng trực tiếp `PHImageManager`;
* yêu cầu quyền Photos;
* biết ảnh đến từ Apple Photos hay nguồn khác.

Renderer chỉ yêu cầu:

```text
photoReference
targetSize
contentMode
```

Photo Provider chịu trách nhiệm trả ảnh.

---

# 5. Chuyển từ photoId sang AlbumPhotoReference

## 5.1 Vấn đề hiện tại

Draft hiện chủ yếu tham chiếu:

```swift
photoId: String
```

Trong production, cần biết chính xác ảnh nào trong Photos Library.

Không nên giả định `photoId` luôn bằng `PHAsset.localIdentifier`.

---

## 5.2 Domain model mới

Tạo:

```swift
struct AlbumPhotoReference: Codable, Hashable, Sendable {
    let id: String
    let source: AlbumPhotoSource
    let sourceIdentifier: String
    let originalFilename: String?
}
```

```swift
enum AlbumPhotoSource: String, Codable, Hashable, Sendable {
    case applePhotos
}
```

Trong phiên bản đầu:

```text
id
→ ID nội bộ của Album

source
→ applePhotos

sourceIdentifier
→ PHAsset.localIdentifier
```

Không cần thêm Files hoặc Cloud source trong Sprint này, nhưng model phải cho phép mở rộng sau này.

---

## 5.3 Assignment model

Cập nhật:

```swift
struct AlbumPhotoAssignment: Codable, Hashable, Sendable {
    let slotId: String
    var photo: AlbumPhotoReference
    var crop: AlbumPhotoCrop
}
```

Không còn chỉ lưu:

```swift
photoId
```

Nếu việc migration ảnh hưởng quá rộng, có thể tạm giữ computed property:

```swift
var photoId: String {
    photo.id
}
```

Không lưu trùng hai ID trong JSON nếu không cần thiết.

---

## 5.4 Crop model chuẩn bị sẵn

Sprint này chưa cần UI crop thủ công hoàn chỉnh, nhưng nên lưu cấu trúc:

```swift
struct AlbumPhotoCrop: Codable, Hashable, Sendable {
    var normalizedOffsetX: Double
    var normalizedOffsetY: Double
    var scale: Double

    static let centered = AlbumPhotoCrop(
        normalizedOffsetX: 0,
        normalizedOffsetY: 0,
        scale: 1
    )
}
```

Giá trị:

```text
offset X, Y: -1...1
scale: >= 1
```

Trong Sprint hiện tại tất cả assignment mới có:

```swift
crop = .centered
```

Không bắt buộc triển khai crop editor ngay.

---

# 6. Migration Draft cũ

Draft cũ chỉ có `photoId`.

Cần giải mã an toàn.

Có thể dùng custom `init(from:)`:

```text
Nếu có photo:
    decode AlbumPhotoReference

Nếu chỉ có photoId:
    tạo AlbumPhotoReference:
        id = photoId
        source = applePhotos
        sourceIdentifier = photoId
```

Điều này chỉ đúng nếu trước đây `photoId` được lấy từ `PHAsset.localIdentifier`.

Nếu project hiện dùng ID khác, adapter phải bổ sung mapping chính xác trước khi migration.

Không được âm thầm giả định nếu dữ liệu hiện tại không hỗ trợ.

---

# 7. Module Production Album Photo Provider

## 7.1 Cấu trúc thư mục

```text
Features/
└── AlbumPhotos/
    ├── Domain/
    │   ├── AlbumPhotoReference.swift
    │   ├── AlbumPhotoCrop.swift
    │   ├── AlbumPhotoRequest.swift
    │   ├── AlbumPhotoLoadState.swift
    │   └── AlbumPhotoProviderError.swift
    │
    ├── Application/
    │   ├── AlbumPhotoProviding.swift
    │   └── AlbumPhotoRequesting.swift
    │
    ├── Infrastructure/
    │   ├── ApplePhotosAlbumPhotoProvider.swift
    │   ├── PHAssetRepository.swift
    │   └── AlbumImageCache.swift
    │
    └── Presentation/
        ├── AlbumPhotoView.swift
        ├── AlbumMissingPhotoView.swift
        └── AlbumPhotoLoadingView.swift
```

Có thể điều chỉnh tên theo cấu trúc hiện tại.

---

## 7.2 Photo request

```swift
struct AlbumPhotoRequest: Hashable, Sendable {
    let reference: AlbumPhotoReference
    let targetPixelSize: CGSize
    let contentMode: AlbumPhotoContentMode
    let deliveryMode: AlbumPhotoDeliveryMode
}
```

```swift
enum AlbumPhotoContentMode: String, Sendable {
    case fit
    case fill
}
```

```swift
enum AlbumPhotoDeliveryMode: String, Sendable {
    case fast
    case opportunistic
    case highQuality
}
```

---

## 7.3 Load state

```swift
enum AlbumPhotoLoadState {
    case idle
    case loading
    case degraded(UIImage)
    case success(UIImage)
    case missing
    case failure(AlbumPhotoProviderError)
}
```

Ý nghĩa:

```text
degraded
→ ảnh preview nhanh, chưa phải ảnh tốt nhất

success
→ ảnh đủ chất lượng cho kích thước yêu cầu
```

Đây chính là hành vi người dùng thường thấy trong Apple Photos:

```text
ảnh xem được xuất hiện trước
→ ảnh nét hơn được thay vào sau
```

---

## 7.4 Protocol

```swift
protocol AlbumPhotoProviding: Sendable {
    func loadImage(
        request: AlbumPhotoRequest
    ) -> AsyncStream<AlbumPhotoLoadState>

    func cancelRequest(for requestId: UUID) async
}
```

Nếu `AsyncStream` làm implementation quá phức tạp, có thể dùng:

```swift
func loadImage(
    request: AlbumPhotoRequest
) async throws -> AlbumPhotoResult
```

Nhưng ưu tiên cơ chế có thể nhận:

```text
degraded image
final image
```

vì `PHImageManager` hỗ trợ nhiều callback cho cùng một request.

---

## 7.5 PHAsset repository

Tách lookup:

```swift
protocol PHAssetResolving: Sendable {
    func asset(
        localIdentifier: String
    ) async -> PHAsset?
}
```

Production implementation:

```text
PHAssetRepository
```

Dùng:

```swift
PHAsset.fetchAssets(
    withLocalIdentifiers: [identifier],
    options: nil
)
```

Không fetch toàn bộ Photo Library để tìm một asset.

---

# 8. ApplePhotosAlbumPhotoProvider

## 8.1 PHImageManager

Dùng:

```swift
PHCachingImageManager
```

Không tạo `PHImageManager` mới cho từng ảnh.

Provider nên là một instance dùng chung trong môi trường Album.

---

## 8.2 Request options

Cho Album Viewer:

```swift
PHImageRequestOptions()
```

Thiết lập:

```text
isNetworkAccessAllowed = true
resizeMode = fast
deliveryMode = opportunistic
version = current
```

Cho ảnh bìa full screen:

```text
deliveryMode = highQualityFormat
resizeMode = exact hoặc fast tùy kích thước
```

Không yêu cầu original full-resolution cho thumbnail nhỏ.

---

## 8.3 iCloud progress

Dùng:

```swift
options.progressHandler
```

`AlbumPhotoLoadState` có thể mở rộng:

```swift
case downloading(progress: Double, degradedImage: UIImage?)
```

Hoặc giữ progress trong ViewModel.

UI tối thiểu:

```text
ảnh preview nếu có
+
progress indicator nhỏ
```

Không thay toàn bộ ảnh bằng màn hình trống khi tải từ iCloud.

---

## 8.4 Degraded result

Đọc:

```swift
PHImageResultIsDegradedKey
```

Nếu `true`:

```text
emit .degraded(image)
```

Nếu `false`:

```text
emit .success(image)
```

Không coi degraded image là lỗi.

---

## 8.5 Cancellation

Mỗi slot có thể biến mất khi người dùng lật Spread.

Khi View biến mất:

```text
cancel image request
```

Không để hàng chục request cũ tiếp tục chạy.

Cần map:

```swift
UUID → PHImageRequestID
```

Dùng actor hoặc khóa phù hợp để tránh race condition.

---

# 9. Image cache

## 9.1 Cache key

```swift
struct AlbumImageCacheKey: Hashable {
    let sourceIdentifier: String
    let widthBucket: Int
    let heightBucket: Int
    let contentMode: AlbumPhotoContentMode
}
```

Không cache chỉ theo photo ID vì cùng ảnh có thể được yêu cầu ở:

* thumbnail nhỏ;
* Page Viewer;
* cover lớn.

---

## 9.2 Cache implementation

Dùng:

```swift
NSCache
```

Không tự xây disk cache trong Sprint này.

Giới hạn theo:

* tổng cost;
* memory warning;
* ảnh thumbnail.

Khi có memory warning:

```text
clear hoặc giảm cache
```

---

## 9.3 Không cache ảnh gốc

Chỉ cache ảnh đã resize cho UI.

Không giữ full-resolution `UIImage` trong memory.

---

# 10. AlbumPhotoView

## 10.1 API

```swift
struct AlbumPhotoView: View {
    let reference: AlbumPhotoReference
    let crop: AlbumPhotoCrop
    let contentMode: AlbumPhotoContentMode
    let targetSize: CGSize?
}
```

View lấy Provider qua Environment:

```swift
@Environment(\.albumPhotoProvider)
```

Hoặc qua dependency injection hiện có.

---

## 10.2 Rendering state

### Loading

Hiển thị:

* màu nền trung tính;
* shimmer nhẹ hoặc `ProgressView`;
* không hiển thị mock photo ID trong production.

### Degraded

Hiển thị ngay ảnh degraded.

Không phủ loading placeholder lên toàn bộ ảnh.

Nếu đang tải iCloud:

```text
progress indicator nhỏ ở góc
```

### Success

Transition nhẹ:

```swift
.opacity
```

Không animation quá mạnh trong từng slot.

### Missing

Hiển thị:

```text
Photo unavailable
```

kèm icon ảnh bị thiếu.

Không crash hoặc giữ ô trắng.

### Failure

Hiển thị:

```text
Unable to load photo
```

Có nút retry nếu phù hợp.

---

## 10.3 Crop

Hiện tại:

```swift
Image(uiImage: image)
    .resizable()
    .scaledToFill()
```

Sau đó áp dụng:

```text
scale
offset
clip
```

theo `AlbumPhotoCrop`.

Mọi slot phải:

```swift
.clipped()
```

---

# 11. Tích hợp với AlbumPageRenderer

## 11.1 Không sửa layout geometry

Renderer vẫn dùng:

```text
layoutId
normalized slot frame
assignment
```

Chỉ thay content provider của slot:

```text
Mock tile
→ AlbumPhotoView
```

---

## 11.2 API Renderer

Có thể dùng:

```swift
AlbumPageRenderer(
    page: page,
    pageSize: pageSize,
    photoContent: { assignment, slot in
        AlbumPhotoView(
            reference: assignment.photo,
            crop: assignment.crop,
            contentMode: .fill,
            targetSize: calculatedPixelSize
        )
    }
)
```

Renderer không cần biết implementation của ảnh.

---

## 11.3 Pixel target size

Target cần tính theo:

```text
slot size in points
× screen scale
```

Ví dụ:

```swift
let pixelWidth = slotWidth * UIScreen.main.scale
```

Có thể tăng nhẹ để tránh mờ:

```text
1.1–1.25 lần target
```

Không yêu cầu kích thước 4K cho một slot nhỏ.

---

# 12. Album Detail production

## 12.1 Màn hình chính

Tạo hoặc refactor:

```text
AlbumDetailView
```

Cấu trúc:

```text
NavigationStack

Book Cover

Album Metadata

Open Album button

Spread thumbnails hoặc Page overview

Edit button
```

---

## 12.2 Header

Hiển thị:

```text
Album title
Date range
Primary place
Photo count
Spread count
```

Ví dụ:

```text
Sydney
14–18 January 2026
Sydney Opera House, Sydney
32 photos · 6 spreads
```

Không hiển thị:

* planning score;
* layout score;
* technical ID;
* log;
* orientation summary.

Các thông tin đó chỉ ở Diagnostics.

---

## 12.3 Hero image

Dùng ảnh bìa thật.

Layout:

```text
square hoặc gần vuông
corner radius vừa phải
ảnh full bleed
gradient phía dưới
title
date/place
```

Không chồng quá nhiều metadata lên hero.

Khuyến nghị:

```text
Title
Date
```

Place có thể để dưới hero nếu text dài.

---

# 13. Book-style Cover

## 13.1 Cover model

Bổ sung:

```swift
struct AlbumCoverConfiguration: Codable, Hashable, Sendable {
    var photo: AlbumPhotoReference
    var title: String
    var subtitle: String?
    var dateText: String?
    var placeText: String?
    var styleId: String
}
```

Trong giai đoạn đầu:

```text
styleId = cover.classic
```

---

## 13.2 Cover appearance

Cover nên có:

* khung sách;
* khoảng margin;
* shadow nhẹ;
* ảnh bìa;
* title;
* subtitle hoặc date;
* background phù hợp.

Ví dụ:

```text
┌────────────────────────┐
│                        │
│       COVER PHOTO      │
│                        │
│       SYDNEY           │
│    JANUARY 2026        │
│                        │
└────────────────────────┘
```

Không cần dựng spine 3D.

Chỉ cần một dải nhỏ bên trái hoặc shadow để gợi cảm giác sách.

---

## 13.3 Cover fallback

Nếu cover photo bị missing:

1. tìm ảnh tồn tại đầu tiên trong Album;
2. dùng làm fallback tạm thời;
3. không tự thay đổi `coverPhoto` trong database nếu chưa có hành động người dùng;
4. hiển thị cảnh báo ở Edit mode.

---

# 14. Two-page Spread Viewer

## 14.1 Màn hình

Tạo:

```text
AlbumSpreadViewer
```

Hiển thị:

* Cover như một màn riêng;
* sau Cover là từng Spread;
* mỗi Spread có đúng hai Page;
* swipe ngang.

---

## 14.2 Data source

```swift
enum AlbumViewerItem: Identifiable {
    case cover(AlbumCoverConfiguration)
    case spread(AlbumDraftSpread)
}
```

Không biến Cover thành một Page layout thông thường.

---

## 14.3 Navigation

Có:

* swipe ngang;
* nút trái/phải trên iPad hoặc màn hình rộng;
* page indicator;
* tap giữa màn hình để ẩn/hiện controls nếu cần.

Không cần animation lật trang 3D.

---

## 14.4 Transition

Dùng:

```text
slide
spring nhẹ
shadow chuyển tiếp
```

Có thể dùng `TabView` với `.page` ở bản đầu nếu được bọc trong Book UI.

Điểm quan trọng không phải hiệu ứng phức tạp mà là:

```text
mỗi item = một Spread hai trang
```

Không còn mỗi Page là một màn riêng.

---

## 14.5 Responsive behavior

### Portrait iPhone

Vẫn hiển thị hai trang cạnh nhau, nhưng viewer có thể:

* giữ tỷ lệ book;
* có margin nhỏ;
* cho phép double tap để zoom;
* hoặc xoay ngang để xem lớn hơn.

Không tự chuyển thành một Page nếu không có yêu cầu rõ.

### Landscape iPhone / iPad

Hiển thị Spread lớn hơn.

### Accessibility

Nếu Dynamic Type không phù hợp với text nằm trong Cover, giới hạn text theo thiết kế nhưng cung cấp accessibility label đầy đủ.

---

# 15. Book sizing

Layout Library hiện dùng normalized coordinates.

Giữ nguyên.

Mỗi Page render trong một kích thước tính toán:

```text
spread width
= left page + gutter + right page
```

Ví dụ:

```swift
let gutter: CGFloat = 4
let pageWidth = (availableWidth - gutter) / 2
let pageHeight = pageWidth
```

Nếu Album hỗ trợ format không vuông:

```text
pageHeight = pageWidth / pageAspectRatio
```

Không đổi Layout Library sang canvas 1000 × 1000.

---

# 16. Spread appearance

Thêm:

* nền ngoài sách;
* page background;
* gutter giữa hai trang;
* shadow trong gáy;
* outer shadow nhẹ.

Không thêm texture giấy nặng.

Mục tiêu:

```text
clean
premium
modern photobook
```

Gutter có thể dùng gradient nhỏ ở giữa để tạo chiều sâu.

---

# 17. Album overview

Dưới Cover hoặc trong Sheet thông tin:

```text
32 Photos
6 Spreads
3 Events
14–18 Jan 2026
Sydney Opera House, Sydney
```

Có thể thêm danh sách Event nguồn:

```text
Morning Walk
Opera House
Harbour Evening
```

Chỉ hiển thị nếu có title tốt.

Không hiển thị Event ID.

---

# 18. Editing architecture

## 18.1 Không sửa trực tiếp persisted object khi người dùng đang chỉnh

Tạo editing session:

```swift
struct AlbumEditingSession {
    var workingDraft: AlbumDraft
    let originalDraft: AlbumDraft

    var hasChanges: Bool
}
```

Luồng:

```text
Open Edit
    ↓
Copy AlbumDraft vào workingDraft
    ↓
User edits
    ↓
Save
    ↓
Validate
    ↓
Persist
```

Cancel:

```text
discard workingDraft
```

Không ghi từng thao tác ngay lập tức vào SwiftData trong version đầu.

---

## 18.2 Edit actions

Tạo enum:

```swift
enum AlbumEditAction {
    case changeCover(photo: AlbumPhotoReference)
    case changePageLayout(pageId: String, layoutId: String)
    case swapPhotos(firstAssignmentId: String, secondAssignmentId: String)
    case removePhoto(pageId: String, slotId: String)
    case removeSpread(spreadId: String)
}
```

Không bắt buộc dùng reducer architecture, nhưng action phải có logic tập trung.

---

# 19. Chỉnh cover

## 19.1 UI

Trong Edit mode:

```text
Change Cover
```

Mở sheet hiển thị các ảnh đã có trong Album.

Không cần truy cập lại toàn bộ Event hoặc Photos Library.

Grid dùng thumbnail nhỏ.

---

## 19.2 Quy tắc

* chỉ chọn ảnh còn tồn tại;
* ảnh đã chọn phải thuộc Album;
* cập nhật `coverPhotoReference`;
* cập nhật hero hiển thị;
* không chạy lại Planner;
* không thay đổi thứ tự Page.

---

# 20. Đổi layout Page

## 20.1 Layout choices

Khi người dùng chọn một Page:

```text
Change Layout
```

Chỉ hiển thị layout có:

```text
photoCount == số ảnh hiện có trên Page
```

Ví dụ Page có 3 ảnh:

```text
three.heroTop
three.heroLeft
three.equalColumns
```

---

## 20.2 Reassignment

Khi đổi layout:

1. giữ nguyên tập ảnh;
2. chạy lại `AlbumPhotoSlotAssigner` cho riêng Page;
3. ưu tiên orientation và importance;
4. không chạy lại toàn bộ Planner;
5. cập nhật assignments;
6. reset hoặc giữ crop phù hợp.

Trong version đầu:

```text
crop reset về centered nếu slot thay đổi đáng kể
```

---

## 20.3 Preview layout

Sheet chọn layout phải render thumbnail thực bằng ảnh hiện tại.

Không chỉ hiển thị tên layout.

---

# 21. Hoán đổi ảnh

## 21.1 Interaction

Version đầu có thể dùng:

```text
Tap ảnh A
→ chọn Swap
→ tap ảnh B
```

Hoặc context menu:

```text
Swap Photo
```

Không cần drag-and-drop ngay.

---

## 21.2 Rules

* được swap trong cùng Page;
* được swap giữa hai Page cùng Spread;
* có thể cho swap giữa các Spread nếu logic đơn giản;
* giữ nguyên crop theo ảnh hoặc theo slot phải được xác định rõ.

Khuyến nghị:

```text
crop đi cùng assignment slot
```

Khi swap:

```text
hai photo reference đổi chỗ
crop reset centered
```

Điều này tránh crop cũ của ảnh A áp lên ảnh B.

---

# 22. Xóa ảnh khỏi Page

Đây là phần cần quy tắc rõ vì Layout hiện yêu cầu số slot cố định.

## 22.1 Khi xóa ảnh

Ví dụ Page từ 4 ảnh còn 3 ảnh:

1. lấy các layout 3 ảnh;
2. chạy selector cho riêng Page;
3. chọn layout tốt nhất;
4. reassign ba ảnh còn lại.

Không để một slot trống trong production Album.

---

## 22.2 Khi Page còn 0 ảnh

Không giữ Page trống.

Các lựa chọn:

* lấy ảnh từ Page còn lại trong Spread nếu Page đó có trên 1 ảnh;
* hoặc xóa cả Spread;
* hoặc chặn hành động.

Version đầu nên dùng quy tắc đơn giản:

```text
Không cho xóa ảnh cuối cùng của một Page.
```

Hiển thị:

```text
Each page must contain at least one photo.
```

Như vậy Spread luôn có:

```text
ít nhất 1 + 1 ảnh
```

---

# 23. Xóa Spread

Cho phép xóa nguyên Spread trong Edit mode.

Điều kiện:

* Album phải còn ít nhất một Spread;
* cần confirmation;
* ảnh không bị xóa khỏi Photos Library;
* chỉ bị loại khỏi Album.

Thông báo:

```text
Remove this spread from the album?
The photos will remain in your Photos Library.
```

---

# 24. Chưa thêm ảnh mới trong Sprint này

Không triển khai:

```text
Add Photo
```

Lý do:

* phải mở lại Event hoặc Photo Picker;
* cần xử lý duplicate;
* cần định nghĩa insert position;
* có thể ảnh mới tạo vượt giới hạn 4 ảnh mỗi Page.

Sprint này chỉ chỉnh sửa ảnh đã có trong Album.

Việc thêm ảnh mới nên là Sprint tiếp theo.

---

# 25. Edit mode UI

Navigation bar:

```text
Cancel                 Save
```

Trong Album:

* tap Page để chọn;
* tap photo để chọn;
* bottom toolbar:

```text
Cover
Layout
Swap
Remove
```

Không hiển thị tất cả action cùng lúc nếu chưa chọn đối tượng.

Ví dụ:

### Chọn Page

```text
Change Layout
```

### Chọn Photo

```text
Change Cover
Swap
Remove
```

### Chọn Spread

```text
Remove Spread
```

---

# 26. Validation trước khi Save

Tái sử dụng hoặc mở rộng `AlbumPlanningValidator`.

Không nên gọi nó là Planning Validator nếu dùng cho Album edit production.

Tạo:

```swift
protocol AlbumDraftValidating {
    func validate(_ draft: AlbumDraft) throws
}
```

Kiểm tra:

* có cover photo;
* có ít nhất một Spread;
* mỗi Spread có đúng hai Page;
* mỗi Page có layout tồn tại;
* số assignment bằng số slot layout;
* mỗi assignment dùng slot hợp lệ;
* không duplicate slot;
* mỗi Page có 1–4 ảnh;
* mỗi Spread có 2–6 ảnh;
* không duplicate ảnh trong cùng Album nếu đó là quy tắc hiện tại;
* photo source identifier không rỗng.

Nếu validation fail:

```text
không save
hiển thị lỗi
giữ editing session
```

---

# 27. Persistence

## 27.1 Giữ JSON row

Sprint này vẫn được giữ:

```text
AlbumDraft encoded JSON trong MDAlbumDraft
```

Không chuyển sang relational store.

---

## 27.2 Bổ sung cột query

Nếu chưa có:

```text
title
coverPhotoIdentifier
primaryPlaceName
startDate
endDate
photoCount
spreadCount
updatedAt
```

Các cột này phục vụ Album List.

Không duplicate toàn bộ Page data thành flat columns.

---

## 27.3 Update method

Repository cần:

```swift
func updateDraft(_ draft: AlbumDraft) async throws
```

Không dùng create mới mỗi lần Save edit.

Cần giữ nguyên:

```text
draftId
createdAt
```

và cập nhật:

```text
updatedAt
```

---

# 28. Album List integration

Album List phải hiển thị ảnh bìa thật.

Mỗi card:

```text
Cover thumbnail
Album title
Date
Photo count
```

Không load ảnh kích thước Album Viewer cho card.

Target khoảng:

```text
200–400 px tùy kích thước card và screen scale
```

---

## 28.1 Missing cover

Nếu cover missing:

* dùng fallback ảnh đầu tiên còn tồn tại;
* nếu không có ảnh tồn tại, dùng missing placeholder;
* Album vẫn mở được;
* Edit mode cho phép người dùng xử lý sau.

---

# 29. Prefetch

## 29.1 Viewer prefetch

Khi đang xem Spread N:

```text
load Spread N
prefetch Spread N+1
prefetch Spread N-1
```

Không load toàn bộ Album full quality ngay khi mở.

---

## 29.2 Cache manager

`PHCachingImageManager` có:

```swift
startCachingImages
stopCachingImages
```

Có thể sử dụng nếu implementation không phức tạp quá.

Version đầu chấp nhận:

```text
request on demand + NSCache
```

nhưng kiến trúc nên cho phép thêm prefetch.

---

# 30. Memory management

Quy tắc bắt buộc:

* không giữ toàn bộ ảnh Album ở full resolution;
* request theo target size;
* cancel request khi slot biến mất;
* giới hạn cache;
* không dùng `Data(contentsOf:)` để đọc ảnh Photos;
* không convert tất cả `PHAsset` thành `UIImage` trước khi render;
* không load ảnh trong Planner;
* không giữ PHAsset trong persisted model.

---

# 31. Permissions

Khi Album được mở:

* nếu Photos permission còn hợp lệ, load bình thường;
* nếu permission bị giới hạn hoặc bị thu hồi, hiển thị trạng thái phù hợp;
* không crash.

Các state:

```text
Authorized
Limited
Denied
Restricted
Not Determined
```

Album có thể chứa ảnh không còn nằm trong Limited selection.

Khi đó slot hiển thị missing/unavailable.

Không tự mở permission prompt liên tục.

---

# 32. Localization

Bổ sung các key cần thiết:

```text
album.open
album.edit
album.save
album.cancel
album.changeCover
album.changeLayout
album.swapPhoto
album.removePhoto
album.removeSpread
album.photoUnavailable
album.unableToLoadPhoto
album.retry
album.photosCount
album.spreadsCount
album.eventsCount
album.eachPageNeedsPhoto
album.removeSpreadConfirmation
album.photosRemainInLibrary
album.noAvailableCoverPhoto
```

Dùng String Catalog hiện có.

Không hardcode tiếng Anh trực tiếp trong View.

---

# 33. Loading experience

Khi mở Album:

```text
khung sách xuất hiện ngay
→ thumbnail/degraded ảnh hiện nhanh
→ ảnh final thay thế dần
```

Không chờ tải đủ tất cả ảnh rồi mới hiện Album.

Album UI phải render được ngay cả khi:

* ảnh đang tải;
* một vài ảnh missing;
* mạng chậm;
* iCloud đang download.

---

# 34. Diagnostics

Thêm:

```text
Real Album Photo Diagnostics
```

Hiển thị:

* source identifier;
* PHAsset found hoặc missing;
* requested target size;
* degraded result received;
* final result received;
* iCloud progress;
* request duration;
* cache hit/miss;
* cancellation.

Không đưa màn hình này vào UI production.

---

# 35. Preview

## 35.1 SwiftUI Preview

Có hai provider:

```text
MockAlbumPhotoProvider
ApplePhotosAlbumPhotoProvider
```

SwiftUI Preview dùng mock provider.

Production dùng Apple provider.

Không yêu cầu quyền Photos trong SwiftUI Preview.

---

## 35.2 Mock provider

Mock provider vẫn được dùng cho:

* Layout preview;
* test;
* Diagnostics edge cases.

Production `AlbumDetailView` không được mặc định dùng mock provider.

---

# 36. Tests

## 36.1 AlbumPhotoReference

* encode/decode;
* migration từ `photoId`;
* source identifier không rỗng;
* computed `photoId` đúng nếu còn dùng.

## 36.2 Asset resolver

Dùng mock repository:

* existing identifier trả asset;
* missing identifier trả nil;
* không fetch toàn library.

Không gọi Photo Library thật trong unit test.

## 36.3 Provider state

Dùng fake image manager abstraction:

* degraded được emit trước success;
* success chỉ emit một lần final;
* missing asset trả missing;
* cancellation dừng callback;
* network error trả failure;
* cache hit không gọi image manager.

## 36.4 Cache

* cùng key trả cùng ảnh;
* khác target bucket tạo key khác;
* purge hoạt động;
* không dùng identifier duy nhất cho mọi size.

## 36.5 Page renderer integration

* assignment tạo đúng số AlbumPhotoView;
* target size tính theo slot;
* missing ảnh không crash;
* crop centered đúng.

## 36.6 Viewer

* cover là item đầu;
* mỗi Spread là một item;
* index navigation đúng;
* empty Album bị validation từ chối;
* current index không vượt giới hạn sau khi xóa Spread.

## 36.7 Edit session

* Cancel không thay đổi Draft gốc;
* Save trả Draft đã sửa;
* `hasChanges` chính xác;
* đổi cover;
* đổi layout;
* swap ảnh;
* remove photo;
* remove Spread.

## 36.8 Change layout

* chỉ layout cùng photo count;
* ảnh không mất;
* không duplicate assignment;
* slot ID hợp lệ;
* validation pass.

## 36.9 Remove photo

* 4 ảnh còn 3 tự chọn layout 3 ảnh;
* không cho xóa ảnh cuối của Page;
* Spread vẫn trong giới hạn 2–6.

## 36.10 Persistence

* save Album mới;
* update Album cũ;
* createdAt giữ nguyên;
* updatedAt thay đổi;
* ảnh reference encode/decode;
* crop encode/decode;
* Draft cũ decode được.

---

# 37. Acceptance criteria

Task hoàn thành khi:

1. Production Album không còn dùng mock placeholder.
2. Mỗi assignment lưu được `AlbumPhotoReference`.
3. `sourceIdentifier` trỏ được tới `PHAsset.localIdentifier`.
4. Có production `ApplePhotosAlbumPhotoProvider`.
5. Provider dùng `PHCachingImageManager`.
6. Provider hỗ trợ degraded và final image.
7. Provider cho phép tải từ iCloud.
8. Có trạng thái progress cơ bản.
9. Request được cancel khi View biến mất.
10. Có memory cache theo identifier và target size.
11. Renderer không phụ thuộc Photos Framework.
12. `AlbumPageRenderer` hiển thị ảnh thật.
13. Album List hiển thị cover thật.
14. Album Detail có hero/cover thật.
15. Có book-style cover.
16. Có Two-page Spread Viewer.
17. Mỗi viewer item sau Cover là một Spread.
18. Có navigation ngang.
19. Có page/spread indicator.
20. Có album overview.
21. Có Edit mode.
22. Có Change Cover.
23. Có Change Layout.
24. Có Swap Photo.
25. Có Remove Photo.
26. Không cho Page rỗng.
27. Có Remove Spread.
28. Không xóa ảnh khỏi Photos Library.
29. Edit dùng working copy.
30. Cancel không lưu thay đổi.
31. Save validate trước khi persist.
32. Repository hỗ trợ update Draft.
33. Draft cũ vẫn decode được.
34. Missing asset không crash.
35. Permission denied không crash.
36. Không load full-resolution ảnh không cần thiết.
37. Không load toàn bộ Album trước khi hiện UI.
38. Preview vẫn hoạt động với Mock Provider.
39. Unit tests compile.
40. Build pass.
41. Không chạy Simulator nếu chưa được yêu cầu.
42. Không chạy test nếu đang giữ quy ước build-only.
43. Không tiếp tục sửa Planner ngoài phần tái sử dụng assigner khi đổi layout.
44. Không thêm AI.
45. Không thêm API bên ngoài.

---

# 38. Thứ tự triển khai

Claude nên làm theo thứ tự sau.

## Phase 1 — Photo reference migration

```text
AlbumPhotoReference
AlbumPhotoSource
AlbumPhotoCrop
Update AlbumPhotoAssignment
Backward decoding
```

## Phase 2 — Production Photo Provider

```text
AlbumPhotoRequest
AlbumPhotoLoadState
AlbumPhotoProviding
PHAssetRepository
ApplePhotosAlbumPhotoProvider
AlbumImageCache
```

## Phase 3 — AlbumPhotoView

```text
loading
degraded
success
missing
failure
iCloud progress
cancellation
```

## Phase 4 — Renderer integration

```text
AlbumPageRenderer uses AlbumPhotoView
target pixel calculation
crop rendering
```

## Phase 5 — Album List and Detail

```text
real cover thumbnail
hero
metadata
album overview
```

## Phase 6 — Spread Viewer

```text
cover item
two-page spread
swipe navigation
indicator
book appearance
```

## Phase 7 — Editing session

```text
working copy
cancel/save
validation
```

## Phase 8 — Editing actions

```text
change cover
change layout
swap photo
remove photo
remove spread
```

## Phase 9 — Persistence update

```text
updateDraft
updatedAt
new JSON fields
old Draft compatibility
```

## Phase 10 — Diagnostics and tests

```text
real photo diagnostics
mock provider
test compile
build
```

---

# 39. Báo cáo hoàn thành

Claude cần báo cáo theo mẫu:

```text
1. Files created
2. Files modified
3. AlbumPhotoReference migration
4. Draft backward compatibility
5. Photo Provider architecture
6. PHAsset lookup
7. Image request options
8. Degraded/final image behavior
9. iCloud loading behavior
10. Cache and cancellation
11. Renderer integration
12. Album List changes
13. Album Detail changes
14. Cover implementation
15. Spread Viewer implementation
16. Edit session architecture
17. Change Cover
18. Change Layout
19. Swap Photo
20. Remove Photo
21. Remove Spread
22. Validation rules
23. Persistence update
24. Diagnostics
25. Tests written
26. Tests executed
27. Build result
28. Known limitations
```

Không chỉ báo:

```text
Done
Build succeeded
```

---

# 40. Nhiệm vụ ngắn để giao Claude Code

```markdown
# TASK — Build the Real Album Experience

The Album Planner and Layout Engine are complete. Stop extending Planner heuristics.

Implement the production Album experience:

1. Replace photoId-only assignments with a backward-compatible `AlbumPhotoReference` containing an internal ID, source type and `PHAsset.localIdentifier`.
2. Add `AlbumPhotoCrop` with normalized offset and scale, defaulting to centered.
3. Build a production `ApplePhotosAlbumPhotoProvider` using `PHCachingImageManager`.
4. Support degraded image → final image replacement, iCloud network loading, progress, cancellation and missing assets.
5. Add an in-memory image cache keyed by source identifier, target-size bucket and content mode.
6. Keep Photos Framework completely outside the Layout Engine and AlbumPageRenderer.
7. Implement `AlbumPhotoView` and replace all production placeholder tiles with real photos.
8. Render Album List covers and Album Detail hero images from real PHAssets.
9. Build a book-style Cover.
10. Build a horizontal Two-page Spread Viewer where each swipe item after the Cover contains exactly two pages.
11. Render all Page layouts using the existing normalized-coordinate Layout Engine.
12. Add a lightweight Album overview with title, date range, primary place, photo count, spread count and source-event count.
13. Add an Album editing session using a working Draft copy.
14. Implement Change Cover using photos already in the Album.
15. Implement Change Layout for one Page, showing only layouts matching the Page photo count and reassigning photos through the existing slot assigner.
16. Implement photo swapping.
17. Implement Remove Photo, automatically selecting a layout for the remaining photo count.
18. Do not allow a Page to become empty.
19. Implement Remove Spread with confirmation. Removing an Album photo must never delete it from Apple Photos.
20. Validate before saving.
21. Add `updateDraft` persistence while preserving createdAt and updating updatedAt.
22. Maintain backward decoding for existing saved Draft JSON.
23. Handle missing assets and revoked/limited Photos permission without crashing.
24. Do not request full-resolution images when a resized display image is enough.
25. Do not load every Album image before presenting the UI.
26. Keep Mock providers for SwiftUI Preview and tests only.
27. Add production photo diagnostics.
28. Build only. Do not run Simulator or tests unless explicitly requested.

Report all files created/modified, reference migration, provider behavior, caching, cancellation, iCloud behavior, viewer implementation, editing operations, persistence compatibility, tests written, build result and known limitations.
```

Sau Sprint này, Nizi sẽ có một chu trình sử dụng hoàn chỉnh:

```text
Photos
→ Event
→ Select
→ Create Album
→ View real photobook
→ Edit
→ Save
```

Bước tiếp theo hợp lý sau đó mới là **thêm ảnh vào Album, điều chỉnh crop và nhập tiêu đề/nội dung cho từng Spread**.
