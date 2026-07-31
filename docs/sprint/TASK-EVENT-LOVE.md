
# TASK — EVENT LOVE → HOME MEMORIES

## Mục tiêu

Thực hiện bản đơn giản nhất của Memory:

> Một Event được user bấm Love thì Event đó được coi là Memory và xuất hiện ở Home.

Không tạo Memory entity mới.
Không dùng `MemoryBuilder`.
Không dùng `MDMemoryCandidate` cho flow này.
Không làm Auto Promotion.
Không refactor First Memory hiện tại.

---

## 1. Event Model

Khảo sát `PhotoEvent` và SwiftData model tương ứng.

Bổ sung trạng thái persist:

```swift
isLoved: Bool
````

Default:

```swift
false
```

Nếu cần timestamp:

```swift
lovedAt: Date?
```

`lovedAt` chỉ dùng để sort hoặc audit, không bắt buộc nếu không cần.

---

## 2. Event List UI

Trong mỗi `EventCardView`, thêm nút heart:

```text
♡ = chưa Love
♥ = đã Love
```

Tap heart:

```swift
isLoved.toggle()
```

và persist ngay.

Không yêu cầu mở Event Detail.

Không yêu cầu confirmation dialog.

Không chạy curation.

Không tạo Album.

---

## 3. Tap behavior

Heart button không được trigger navigation vào Event Detail.

Nếu card hiện có tap gesture toàn card:

* heart phải consume tap riêng;
* tap ảnh/card vẫn mở Event;
* tap heart chỉ toggle Love.

---

## 4. Persistence

Thêm repository method phù hợp, ví dụ:

```swift
func setEventLoved(
    eventID: UUID,
    isLoved: Bool
) async throws
```

Không để View sửa SwiftData trực tiếp nếu architecture hiện tại đang đi qua repository/store.

---

## 5. Home

Home hiện đang có Memory/hero section cũ.

Không redesign Home toàn diện.

Bổ sung một section:

```text
Kỷ niệm
```

Data source:

```text
PhotoEvent WHERE isLoved == true
```

Không query `MDMemoryCandidate` cho section mới này.

---

## 6. Home display

Mỗi Loved Event hiển thị:

```text
cover image
place nếu đã resolve
date/date range
photo count
♥
```

Có thể reuse `EventCardView` hoặc tạo presentation variant nhẹ.

Không duplicate Event object.

---

## 7. Sort

Loved Events trên Home sort:

```text
event date DESC
```

mới nhất trước.

Không sort theo `lovedAt` trong V1.

---

## 8. Empty state

Nếu chưa có Loved Event:

Không cần section lớn.

Có thể hiện nhẹ:

```text
Các sự kiện bạn yêu thích sẽ xuất hiện ở đây.
```

hoặc ẩn section hoàn toàn.

Ưu tiên UI gọn.

---

## 9. Unlove

Nếu user tap ♥ thành ♡:

```text
isLoved = false
```

Event phải:

* vẫn tồn tại trong Event List;
* biến mất khỏi Home Memory section;
* không xóa Event;
* không xóa Album;
* không ảnh hưởng curation.

---

## 10. Event Detail

Nếu Event Detail có toolbar/action phù hợp, có thể hiển thị cùng trạng thái heart.

Nhưng không bắt buộc nếu làm tăng scope.

Source of truth vẫn là persisted `isLoved`.

---

## 11. Event rebuild — lưu ý quan trọng

Event Discovery hiện có thể rebuild Event và tạo UUID mới.

Trong task này:

KHÔNG giải quyết toàn bộ stable identity architecture.

Nhưng Claude phải kiểm tra:

* `isLoved` có bị mất khi `replaceRebuildableEvents()` chạy không?
* nếu có, báo rõ trước khi triển khai.

Nếu có cách rất nhỏ để preserve trạng thái loved khi rebuild bằng existing matching logic, có thể thực hiện.

Nếu cần refactor lớn:

* không làm;
* ghi TODO rõ ràng.

Không mở rộng task thành Stable Event Identity sprint.

---

## 12. First Memory hiện tại

Không sửa:

```text
FirstExperienceCoordinator
MemoryCandidate
MemoryBuilder
FirstMemoryView
MemoryViewerView
```

Loved Event section ở Home là flow mới độc lập.

Sau này mới quyết định có bỏ `MemoryCandidate` hay không.

---

## 13. Acceptance Criteria

1. Event List hiển thị ♡ trên mỗi Event.
2. Tap ♡ → ♥.
3. Relaunch app vẫn còn ♥.
4. Loved Event xuất hiện ở Home.
5. Tap ♥ → ♡ thì Event biến mất khỏi Home.
6. Event vẫn tồn tại bình thường trong Event List.
7. Heart tap không mở Event.
8. Event navigation cũ vẫn hoạt động.
9. Không tạo `MemoryCandidate` mới.
10. Không chạy curation khi Love.
11. Không thay Event Discovery algorithm.
12. Build/test pass.
