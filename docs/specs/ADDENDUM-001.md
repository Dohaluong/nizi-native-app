
# ADDENDUM 001 — Single-Page Album Viewer on iPhone

## 1. Quan hệ với SPEC gốc

Tài liệu này là phần bổ sung cho:

`SPEC-REAL-ALBUM-EXPERIENCE.md`

Không chỉnh sửa, xóa hoặc viết lại SPEC gốc.

Mọi nội dung trong SPEC gốc vẫn giữ nguyên, ngoại trừ các yêu cầu liên quan đến việc hiển thị đồng thời hai trang trong Album Viewer.

Khi có khác biệt giữa hai tài liệu, Addendum này được ưu tiên áp dụng cho các phần:

- Album Viewer;
- viewer data source;
- điều hướng trang;
- page indicator;
- responsive presentation;
- prefetch ảnh;
- trạng thái lựa chọn trong Edit mode.

Addendum này không thay đổi:

- cấu trúc `AlbumDraft`;
- cấu trúc `AlbumDraftSpread`;
- quy tắc mỗi Spread có đúng hai Page;
- Album Planner;
- Layout Engine;
- Layout Library;
- persistence;
- validation theo Spread;
- logic chỉnh sửa có liên quan đến hai Page cùng Spread.

---

# 2. Quyết định UX

Trên iPhone, Album Viewer chỉ hiển thị **một Page tại một thời điểm**.

Không hiển thị hai Page cạnh nhau.

Lý do:

- chiều ngang iPhone không đủ để hiển thị hai Page rõ ràng;
- nếu chia đôi màn hình, ảnh và nội dung trong từng slot sẽ quá nhỏ;
- một Page toàn chiều rộng tạo cảm giác hình ảnh tốt hơn;
- cách vuốt tương đồng với màn hình chi tiết ảnh đã có trong Nizi;
- người dùng chỉ cần một cơ chế điều hướng ngang thống nhất.

Viewer:

```text
Cover
  ↓
Page 1
  ↓
Page 2
  ↓
Page 3
  ↓
Page 4
````

Mỗi thao tác vuốt ngang chuyển đúng một Page.

---

# 3. Logic Spread vẫn được giữ nguyên

Mô hình dữ liệu tiếp tục là:

```text
AlbumDraft
    ├── Spread 1
    │   ├── Left Page
    │   └── Right Page
    │
    ├── Spread 2
    │   ├── Left Page
    │   └── Right Page
    │
    └── ...
```

Không flatten và lưu lại Album dưới dạng danh sách Page độc lập.

Danh sách Page tuần tự chỉ được tạo ở tầng Presentation:

```text
Persisted Album Draft
        ↓
Album Viewer Adapter
        ↓
Flattened Viewer Items
        ↓
Cover
Page 1
Page 2
Page 3
Page 4
```

Nhờ vậy:

* Planner vẫn cân bằng hai Page trong một Spread;
* layout-pair selection vẫn hoạt động;
* validation vẫn kiểm tra hai Page;
* swap ảnh giữa hai Page cùng Spread vẫn thực hiện được;
* remove Spread vẫn xóa đúng hai Page;
* sau này có thể thêm chế độ hai trang cho iPad mà không migration dữ liệu.

---

# 4. Thay thế yêu cầu Two-page Spread Viewer

Trong SPEC gốc, mọi yêu cầu bắt buộc hiển thị hai Page cạnh nhau trong Viewer được thay thế bởi:

```text
Single-Page Album Viewer
```

Các tên như:

```text
AlbumSpreadViewer
Two-page Spread Viewer
spread swipe item
```

không còn là tên bắt buộc cho giao diện iPhone.

Tên production đề xuất:

```text
AlbumPageViewer
```

hoặc:

```text
AlbumReaderView
```

Không bắt buộc đổi các type đã được tạo nếu tên cũ chưa gây hiểu nhầm trong code. Tuy nhiên hành vi hiển thị phải tuân theo Addendum này.

---

# 5. Viewer item

Tạo model ở tầng Presentation:

```swift
enum AlbumViewerItem: Identifiable, Hashable {
    case cover(AlbumCoverConfiguration)
    case page(AlbumViewerPage)
}
```

```swift
struct AlbumViewerPage: Identifiable, Hashable {
    let id: String

    let page: AlbumDraftPage

    let pageNumber: Int
    let totalPageCount: Int

    let spreadId: String
    let spreadIndex: Int
    let positionInSpread: AlbumSpreadPagePosition
}
```

```swift
enum AlbumSpreadPagePosition: String, Codable, Hashable, Sendable {
    case left
    case right
}
```

`positionInSpread` có thể chỉ tồn tại ở Presentation nếu `AlbumDraftSpread` đã bảo đảm thứ tự Page.

Không bắt buộc thêm field này vào JSON nếu có thể suy ra chắc chắn:

```text
pages[0] = left
pages[1] = right
```

Nếu thứ tự hiện tại chưa được bảo đảm bằng domain invariant, cần bổ sung position rõ ràng vào model.

---

# 6. Flattening Adapter

Tạo service hoặc mapper:

```swift
protocol AlbumViewerItemBuilding {
    func makeItems(
        from draft: AlbumDraft
    ) -> [AlbumViewerItem]
}
```

Implementation:

```text
DefaultAlbumViewerItemBuilder
```

Quy tắc:

1. Cover là item đầu tiên.
2. Duyệt Spread theo thứ tự đã lưu.
3. Trong mỗi Spread, thêm Page trái trước.
4. Sau đó thêm Page phải.
5. Đánh số Page liên tục từ 1.
6. Không thay đổi thứ tự photo assignment.
7. Không sao chép hoặc persistence danh sách đã flatten.
8. Không đưa Page rỗng vào Viewer.
9. Dữ liệu không hợp lệ phải được validator phát hiện, không âm thầm bỏ Page.

Ví dụ:

```text
Cover       → viewer index 0
Spread 1 L  → Page 1
Spread 1 R  → Page 2
Spread 2 L  → Page 3
Spread 2 R  → Page 4
```

---

# 7. Giao diện Viewer trên iPhone

Mỗi Page:

* chiếm gần toàn bộ chiều rộng màn hình;
* giữ đúng tỷ lệ `AlbumPageFormat`;
* căn giữa theo chiều ngang;
* có khoảng cách ngoài vừa đủ;
* không hiển thị một phần lớn của Page kế tiếp;
* không scale xuống để dành chỗ cho Page đối diện;
* tiếp tục dùng `AlbumPageRenderer`;
* tiếp tục dùng normalized coordinates của Layout Library;
* hiển thị ảnh thật qua `AlbumPhotoView`.

Ví dụ:

```text
┌────────────────────────┐
│ Sydney          3 / 12 │
│                        │
│  ┌──────────────────┐  │
│  │                  │  │
│  │      PAGE 3      │  │
│  │                  │  │
│  └──────────────────┘  │
│                        │
│          ● ○ ○         │
└────────────────────────┘
```

Không đặt thêm một Page thu nhỏ bên cạnh để minh họa Spread.

---

# 8. Navigation

Viewer sử dụng điều hướng ngang giống màn hình chi tiết ảnh hiện có.

Yêu cầu:

* swipe trái để sang Page kế tiếp;
* swipe phải để về Page trước;
* mỗi lần snap đúng một item;
* Cover là item đầu tiên;
* sau Cover là Page 1;
* không nhảy theo cả Spread;
* giữ current index khi UI state thay đổi không liên quan;
* current index phải được điều chỉnh an toàn sau khi xóa Spread hoặc Page.

Có thể dùng:

```swift
TabView(selection: ...)
    .tabViewStyle(.page(indexDisplayMode: .never))
```

hoặc paging `ScrollView` tùy kiến trúc hiện tại.

Ưu tiên tái sử dụng cơ chế swipe của màn hình chi tiết ảnh đã xây nếu phù hợp, thay vì tạo một interaction khác.

---

# 9. Page Indicator

Indicator tính theo Page, không tính theo Spread.

Ví dụ:

```text
Page 3 / 12
```

Không hiển thị:

```text
Spread 2 / 6
```

làm indicator chính.

Có thể hiển thị thông tin Spread ở mức phụ trong Edit mode:

```text
Page 3 / 12 · Spread 2
```

Cover không được tính là Page.

Khi đang ở Cover:

```text
Cover
```

hoặc không hiện Page indicator.

Không hiển thị 12 dấu chấm nếu Album quá dài.

Quy tắc:

* Album ngắn: có thể dùng dot indicator;
* Album dài: dùng text `3 / 24`;
* ưu tiên text counter để UI ổn định.

---

# 10. Header và controls

Viewer production nên giữ controls tối giản.

Khi xem Page:

```text
Album title                     More
Page 3 / 12
```

Có thể ẩn header khi người dùng tap vào Page, tương tự màn hình xem ảnh, nhưng đây không phải yêu cầu bắt buộc ở Sprint đầu.

Controls không được che nội dung Page quá nhiều.

Các thông tin kỹ thuật không hiển thị:

* spread ID;
* page ID;
* layout score;
* planning score;
* assignment score;
* orientation summary.

---

# 11. Book appearance trong chế độ một Page

Vẫn giữ cảm giác photobook dù chỉ hiển thị một Page.

Mỗi Page có thể có:

* nền giấy sáng;
* outer shadow nhẹ;
* corner radius rất nhỏ hoặc không có, tùy thiết kế;
* khoảng trống xung quanh;
* nền màn hình trung tính;
* shadow thay đổi nhẹ trong lúc swipe.

Không hiển thị:

* gutter giữa hai Page;
* gáy sách nằm giữa màn hình;
* hai Page chia đôi chiều ngang.

Có thể thêm dấu hiệu rất nhẹ theo vị trí trong Spread:

```text
Left Page  → shadow hoặc binding hint nhẹ ở mép phải
Right Page → shadow hoặc binding hint nhẹ ở mép trái
```

Tuy nhiên không được làm giao diện lệch hoặc gây cảm giác Page bị cắt.

Đây là chi tiết tùy chọn, không phải acceptance criterion bắt buộc.

---

# 12. Cover

Cover vẫn là item riêng đầu tiên.

Cover hiển thị một màn hình đầy đủ, không ghép với Page 1.

Trình tự:

```text
Cover
→ swipe
Page 1
→ swipe
Page 2
```

Cover có thể dùng tỷ lệ giống Page hoặc thiết kế bìa riêng theo SPEC gốc.

Khi người dùng đổi Cover trong Edit mode, current viewer item không tự nhảy trừ khi Cover bị lỗi hoặc Album được reload có chủ đích.

---

# 13. Prefetch ảnh

Prefetch theo Page đang xem, không theo toàn Spread.

Khi đang xem Page `N`:

```text
render Page N
prefetch Page N + 1
prefetch Page N - 1
```

Có thể prefetch thêm Page đối diện cùng Spread nếu khác `N ± 1` do cấu trúc đặc biệt, nhưng với thứ tự Page trái rồi Page phải, Page đối diện thường đã nằm sát cạnh.

Không tải toàn bộ ảnh của mọi Spread khi mở Viewer.

Khi Page biến mất xa khỏi vùng hiện tại:

* cancel request không còn cần;
* giữ thumbnail đã cache theo giới hạn memory;
* không giữ full-resolution image.

---

# 14. Responsive behavior

## iPhone portrait

Bắt buộc hiển thị một Page.

## iPhone landscape

Vẫn hiển thị một Page trong Sprint này để giữ interaction nhất quán.

Không tự động chuyển sang hai Page khi xoay ngang.

## iPad hoặc macOS trong tương lai

Có thể bổ sung:

```text
Viewer Display Mode
- singlePage
- spread
```

Nhưng không triển khai trong Sprint hiện tại.

Data model hiện tại phải tiếp tục cho phép bổ sung chế độ đó mà không migration.

---

# 15. Editing trong Single-Page Viewer

Edit mode vẫn hiển thị Page hiện tại ở kích thước lớn.

Các action theo Page hiện tại:

```text
Change Layout
Swap Photo
Remove Photo
```

Các action theo Album:

```text
Change Cover
Save
Cancel
```

Các action theo Spread:

```text
Swap with facing Page
Remove Spread
```

Viewer phải xác định được Page đối diện thông qua:

```text
spreadId
positionInSpread
```

Ví dụ:

```text
Page hiện tại: left
Facing Page: right trong cùng Spread
```

hoặc ngược lại.

Không cần hiển thị đồng thời hai Page để thực hiện swap giữa chúng. Có thể dùng sheet chọn ảnh hoặc danh sách thumbnail của Page đối diện.

---

# 16. Remove Spread

Khi người dùng đang xem một Page và chọn `Remove Spread`:

* xóa cả Page hiện tại và Page đối diện;
* không chỉ xóa Page đang hiển thị;
* yêu cầu confirmation;
* ảnh vẫn còn trong Apple Photos;
* sau khi xóa, chọn Page gần nhất còn tồn tại;
* nếu đang ở Spread cuối, chuyển về Page cuối mới;
* Album phải còn ít nhất một Spread.

Current viewer index phải được tính lại theo danh sách flattened mới.

Không giữ index cũ nếu vượt phạm vi.

---

# 17. Remove Photo

Remove Photo chỉ tác động đến Page hiện tại.

Sau khi xóa:

* Page hiện tại tự chọn layout phù hợp với số ảnh còn lại;
* không làm thay đổi Page đối diện;
* không chạy lại toàn Album Planner;
* không cho Page còn 0 ảnh;
* Page numbering không thay đổi;
* viewer giữ ở Page hiện tại.

Nếu layout mới render thành công, UI cập nhật tại chỗ.

---

# 18. Change Layout

`Change Layout` chỉ áp dụng cho Page đang xem.

Layout picker:

* hiển thị các layout cùng số lượng ảnh;
* render preview bằng ảnh thật;
* không cần hiển thị Page đối diện;
* sau khi chọn, viewer vẫn ở cùng Page;
* không thay đổi thứ tự Page;
* không thay đổi Spread.

---

# 19. Swap Photo

Hỗ trợ:

1. Swap hai ảnh trong cùng Page.
2. Swap ảnh giữa Page hiện tại và Page đối diện cùng Spread.

Không bắt buộc swap trực tiếp với mọi Page trong Album ở Sprint này.

Với swap giữa hai Page:

```text
Select photo on current Page
→ Choose “Swap with facing page”
→ Show thumbnails from facing Page
→ Select target photo
→ Swap references
→ Reset both crops to centered
```

Không cần render hai Page cạnh nhau.

---

# 20. Viewer state

Tạo state dựa trên identity thay vì chỉ lưu integer index nếu có thể:

```swift
struct AlbumViewerSelection: Equatable {
    let itemId: String
}
```

Khi Draft cập nhật:

1. Tìm lại item có cùng ID.
2. Nếu còn tồn tại, giữ item đó.
3. Nếu bị xóa, chọn item gần nhất.
4. Không tự quay về Cover sau mỗi lần Save hoặc edit.

Điều này quan trọng khi remove Spread làm thay đổi số lượng Page trước current index.

---

# 21. Album List và Album Detail

Addendum này không thay đổi:

* Album List;
* cover card;
* Album Detail header;
* Album overview;
* hero image;
* metadata.

Khi người dùng nhấn `Open Album`, mở `AlbumPageViewer`, không mở giao diện hai Page.

Album Detail có thể hiển thị thumbnail Page theo dạng lưới nếu SPEC gốc có yêu cầu. Việc đó không đồng nghĩa với Viewer phải hiển thị hai Page.

---

# 22. Diagnostics và Preview

Cập nhật production-flow Preview:

```text
Cover
Page 1
Page 2
Page 3
...
```

Diagnostics vẫn có thể giữ một màn hình riêng hiển thị cặp Layout trong Spread để kiểm tra Planner.

Phân biệt:

```text
Planner Diagnostics
→ có thể hiển thị hai Page cạnh nhau để debug cặp layout

Production Album Viewer
→ chỉ hiển thị một Page
```

Không xóa Preview kỹ thuật hai Page nếu nó hữu ích cho việc kiểm tra layout-pair selection.

---

# 23. Tests bổ sung

## Viewer item builder

* Cover là item đầu tiên.
* Page trái đứng trước Page phải.
* Spread giữ đúng thứ tự.
* Page numbering bắt đầu từ 1.
* Cover không được tính vào total Page count.
* Hai Spread tạo bốn Page viewer items.
* Không persistence flattened items.

## Navigation

* Vuốt từ Cover sang Page 1.
* Vuốt Page 1 sang Page 2.
* Không nhảy từ Page 1 sang Page 3.
* Indicator hiển thị đúng `Page N / Total`.
* Cover không hiển thị Page number.
* Current selection không vượt phạm vi.

## Edit integration

* Change Layout giữ nguyên current Page.
* Remove Photo giữ nguyên Page nếu Page vẫn tồn tại.
* Remove Spread xóa cả hai Page.
* Sau khi xóa Spread, chọn Page gần nhất.
* Swap với facing Page xác định đúng Page cùng Spread.
* Cancel edit giữ nguyên Viewer của Draft gốc.

## Prefetch

* Current Page được request.
* Previous và next Page được prefetch.
* Page xa bị cancel hoặc không request.
* Không prefetch toàn Album.

---

# 24. Acceptance criteria bổ sung

Addendum hoàn thành khi:

1. iPhone Album Viewer chỉ hiển thị một Page tại một thời điểm.
2. Không có hai Page production đặt cạnh nhau.
3. Model `AlbumDraftSpread` vẫn giữ đúng hai Page.
4. Viewer flatten Spread thành danh sách Page chỉ ở Presentation.
5. Cover là item đầu tiên.
6. Mỗi swipe chuyển đúng một item.
7. Sau Cover là Page 1.
8. Page trái đứng trước Page phải.
9. Indicator tính theo Page.
10. Cover không được tính vào tổng số Page.
11. Page chiếm gần toàn chiều rộng iPhone.
12. Renderer vẫn dùng normalized coordinates.
13. Ảnh thật vẫn được load qua `AlbumPhotoProvider`.
14. Prefetch theo Page trước và sau.
15. Không load toàn Album trước khi hiển thị.
16. Edit mode thao tác trên Page hiện tại.
17. Có thể xác định Page đối diện cùng Spread.
18. Remove Spread xóa đúng hai Page.
19. Change Layout không làm thay đổi Page đối diện.
20. Remove Photo không cho Page rỗng.
21. Current selection được giữ theo item ID khi có thể.
22. Album Detail mở Single-Page Viewer.
23. Planner Diagnostics hai Page có thể được giữ.
24. Không migration cấu trúc Spread chỉ để phục vụ Viewer.
25. Không triển khai chế độ hai Page trên iPad trong Sprint này.
26. Build pass.
27. Không chạy Simulator hoặc tests nếu chưa được yêu cầu.

---

# 25. Nội dung ngắn để gửi Claude Code

## ADDENDUM — Replace the production two-page viewer with a single-page iPhone viewer

This is an addendum to `SPEC-REAL-ALBUM-EXPERIENCE.md`. Do not modify or rewrite the original specification.

The Album domain and Planner must continue to organize content as Spreads containing exactly two Pages. Only the production Viewer presentation changes.

Requirements:

1. On iPhone, show exactly one Album Page at a time.
2. Do not render two production Pages side by side.
3. Keep `AlbumDraftSpread` and all two-page planning, validation and editing logic unchanged.
4. Add a presentation-layer builder that flattens:

   * Cover;
   * Spread 1 left Page;
   * Spread 1 right Page;
   * Spread 2 left Page;
   * Spread 2 right Page;
   * and so on.
5. Cover is the first viewer item and is not included in the Page count.
6. Each horizontal swipe moves exactly one item.
7. Reuse the interaction style of the existing photo-detail screen where practical.
8. Display `Page N / Total Pages`, not a Spread-based primary indicator.
9. Render each Page near the full available iPhone width using the existing `AlbumPageRenderer`.
10. Continue using normalized Layout Library coordinates.
11. Continue loading real images through `AlbumPhotoProvider`.
12. Prefetch only the previous, current and next Page instead of loading the full Album.
13. Store viewer selection by item identity where possible so edits do not unnecessarily reset the current Page.
14. Change Layout and Remove Photo operate on the current Page only.
15. The facing Page is resolved through the current Page's parent Spread.
16. Swap can work within the current Page or with the facing Page through a selection sheet; two Pages do not need to be visible simultaneously.
17. Remove Spread removes both Pages in the current Spread and selects the closest remaining Page.
18. Keep technical two-page Spread previews in Planner Diagnostics if useful.
19. Do not add an iPad two-page mode in this Sprint.
20. Build only. Do not run Simulator or tests unless explicitly requested.

Report:

* files created;
* files modified;
* viewer-item flattening;
* page ordering;
* Cover handling;
* navigation and selection state;
* Page indicator;
* prefetch behavior;
* edit integration;
* diagnostics retained;
* build result;
* known limitations.

```

Claude nên thực hiện **SPEC gốc trước**, sau đó áp dụng Addendum này để ghi đè riêng hành vi Viewer.
```
