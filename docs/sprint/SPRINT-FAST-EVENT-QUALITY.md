# SPRINT — FAST EVENT QUALITY DURING INITIAL SCAN

## 1. Mục tiêu

Tích hợp cơ chế đánh giá chất lượng Event (Fast Event Quality) ngay trong quá trình Initial Scan.

Mục tiêu:

- giảm số Event hiển thị mặc định;
- ẩn các Event rất ít giá trị;
- không làm tăng đáng kể thời gian scan;
- không chạy Vision;
- không chạy Event Curation;
- không cần internet;
- hoàn toàn local.

Sau khi scan hoàn tất:

Photo Library
↓
Scan Metadata
↓
Photo Sessions
↓
Event Discovery
↓
Fast Event Quality
↓
Persist Events
↓
Event List

Không có bước chạy riêng sau scan.

---

# 2. Triết lý

Không phải mọi cụm ảnh đều là một Event đáng để người dùng xem.

Event Discovery có nhiệm vụ:

> tìm tất cả các cụm ảnh.

Fast Event Quality có nhiệm vụ:

> quyết định cụm nào đáng xuất hiện trong UX.

Không xoá Event.

Chỉ quyết định:

- hiển thị;
- hạ ưu tiên;
- hoặc ẩn mặc định.

---

# 3. Không dùng Vision

Fast Event Quality chỉ được dùng dữ liệu đã có sau Scan.

Không được:

- load thumbnail;
- chạy VNFeaturePrint;
- detect face;
- document detection;
- sharpness;
- exposure;
- beauty score.

Các việc này thuộc Deep Curation khi user mở Event.

---

# 4. Pipeline mới

Current:

Photo Scan
↓
Session Discovery
↓
Event Discovery
↓
Persist

Đổi thành:

Photo Scan
↓
Session Discovery
↓
Event Discovery
↓
Fast Event Quality
↓
Persist

Không tạo pass thứ hai.

---

# 5. Dữ liệu được phép sử dụng

Được phép dùng:

PhotoEvent

IndexedAsset

PhotoSession

Location metadata

Favorite

Trip Discovery result

Home Detection result nếu đã có.

Không chạy thêm AI.

---

# 6. EventFastQuality

Tạo service mới:

FastEventQualityService

hoặc

EventQualityClassifier

Không coupling vào UI.

Không để View tự tính.

---

# 7. Output

Mỗi Event có thêm:

eventQualityScore

0...1

và

eventVisibility

```swift
enum EventVisibility {
    case normal
    case lowValue
    case hiddenNoise
}
```

Không cần nhiều trạng thái hơn.

---

# 8. Event List

Mặc định:

chỉ load

normal

và

lowValue.

hiddenNoise

không hiện.

Diagnostics vẫn xem được tất cả.

---

# 9. Không xoá Event

Event bị đánh giá thấp vẫn tồn tại.

Không delete.

Không merge.

Không rebuild.

Không đổi EventID.

Chỉ thay đổi:

visibility

---

# 10. Các signal được dùng

## Photo count

Quá ít ảnh

↓

trừ điểm.

Không hard reject.

Ví dụ:

3 ảnh vẫn có thể là Event tốt.

---

## Favorite

Có Favorite

↓

cộng điểm mạnh.

Đây là tín hiệu cảm xúc mạnh nhất.

---

## Duration

Event quá ngắn

↓

trừ điểm.

Nhưng duration ngắn không đồng nghĩa Event rác.

---

## Moment count

Nếu Event chỉ có:

1 moment

↓

giảm điểm.

Nếu nhiều moment:

↓

tăng điểm.

---

## Session diversity

Có nhiều session nhỏ

↓

tăng điểm.

---

## Screenshot ratio

Nếu phần lớn là screenshot

↓

giảm mạnh.

Không cần Vision.

Đã có metadata.

---

## GPS

Có location

↓

tăng nhẹ.

Không có GPS

↓

không coi là rác.

Chỉ không được cộng điểm.

---

## Trip

Nếu Event thuộc Trip

↓

tăng điểm.

Đặc biệt:

international

domestic trip

multi-day trip

---

## Home

Nếu Event chỉ là:

rất ít ảnh

rất ngắn

ở Home

↓

giảm nhẹ.

Không được coi tất cả Event ở Home là rác.

Sinh nhật ở nhà vẫn là Event tốt.

---

# 11. Không dùng người

Không dùng:

face count

face quality

face landmarks

vì Vision chưa chạy.

---

# 12. Không dùng duplicate

Không dùng:

feature print

duplicate ratio

highlight count

usable count

Các signal này chỉ có sau Deep Curation.

---

# 13. Event Quality Score

Score là tổng hợp nhiều signal.

Không dùng rule:

photoCount < X
↓

hide

Cần weighted scoring.

Ví dụ:

Favorite

Moment diversity

Duration

Trip

GPS

Screenshot ratio

Photo count

Không hard-code toàn bộ trong nhiều nơi.

Tập trung vào một service.

---

# 14. EventVisibility

Quy tắc:

Score cao

↓

normal

Score trung bình

↓

lowValue

Score rất thấp

↓

hiddenNoise

Threshold đưa vào config.

Không hard-code.

---

# 15. Event List

Mặc định:

không hiện

hiddenNoise.

Nếu sau này cần:

Developer có thể bật:

Show Hidden Events.

Không cần UI production ngay.

---

# 16. Diagnostics

Thêm màn:

Fast Event Quality

Hiển thị:

Quality Score

Visibility

Reason

Ví dụ:

+ Favorite

+ Trip

- Too Short

- Mostly Screenshots

Không cần giao diện đẹp.

Mục tiêu tune.

---

# 17. Explainability

Diagnostics phải giải thích được:

Vì sao Event bị hide?

Ví dụ:

Score 0.28

Reasons

- very short

- one moment only

- no favorites

- mostly screenshots

Không chỉ hiện:

0.28

---

# 18. Performance

Không được scan lại ảnh.

Không load thumbnail.

Không thêm pass Vision.

Độ phức tạp:

O(number of Events)

Không phụ thuộc số ảnh.

---

# 19. Sau này

Fast Event Quality chỉ là bước đầu.

Sau khi user mở Event:

Deep Curation

↓

có thể cập nhật:

eventQualityScore

chính xác hơn.

Nhưng không thuộc sprint này.

---

# 20. Không làm trong sprint

Không:

- Vision
- Face Detection
- Feature Print
- Beauty Score
- Deep Curation
- Memory Score
- Album
- Reverse Geocode
- Major Event
- Trip redesign

---

# 21. Acceptance Criteria

Sau Initial Scan:

- mọi Event đều có eventQualityScore.
- mọi Event đều có visibility.
- Event List mặc định ít Event hơn.
- Event không bị xoá.
- Không tăng đáng kể thời gian scan.
- Không chạy Vision.
- Không có thêm background pass sau scan.
- Diagnostics giải thích được lý do từng Event bị ẩn hoặc được giữ.