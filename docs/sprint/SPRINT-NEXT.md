
# NEXT STEPS — EVENT, HOME, TRIP & AUTO MEMORY

## 1. Mục tiêu tổng thể

Nizi hiện đã có các thành phần chính:

- scan và index thư viện ảnh;
- chia Session và Event;
- Event Boundary tương đối chính xác;
- Fast Event Quality chạy thật trong production;
- Trip Discovery;
- Full Home Detection;
- Fast Home Candidate + user xác nhận Home;
- Event Highlights / Curation V2;
- Event Love → hiển thị ở Home.

Các vấn đề còn lại không phải là thiếu engine, mà là:

1. Hai nguồn Home chưa được thống nhất.
2. Trip Discovery đang dùng Home inferred thay vì Home user đã xác nhận.
3. Điều kiện tạo Trip quá lỏng.
4. Fast Event Quality đã có nhưng chưa được dùng để tự đánh dấu Memory.
5. Event địa danh chưa được enrich lazy trong production.
6. Event Highlights vẫn cần kiểm nghiệm và giới hạn số ảnh hợp lý.

Không xây thêm entity Memory riêng trong giai đoạn này.

Memory trước mắt vẫn là trạng thái của Event:

```text
Event do user ♥
hoặc
Event được Nizi tự đánh dấu
        ↓
hiển thị trên Home như một Kỷ niệm
````

---

# PHASE 1 — UNIFY HOME SOURCE

## 2. Vấn đề

Hiện có hai hệ Home:

### Full Home Detector

```text
LocationIntelligenceEngine.detectHome()
```

* chạy trong `EventDiscoveryEngine`;
* phục vụ Event/Trip logic;
* tự infer lại Home mỗi lần discovery.

### Fast Home Candidate Detector

* chạy trong lúc scan;
* đưa candidate lên UI;
* user xác nhận;
* persist `HomeAnchor(source: .userConfirmed)`.

Vấn đề:

```text
Home user xác nhận
≠
Home thực tế Trip Discovery đang dùng
```

Store chỉ bảo vệ không ghi đè dữ liệu confirmed, nhưng engine vẫn dùng Home inferred mới.

---

## 3. Việc cần làm

Thống nhất thứ tự ưu tiên Home:

```text
userConfirmed Home
        ↓
persisted inferred Home
        ↓
newly inferred Home
```

Production discovery phải:

```text
DiscoverEventsUseCase
    ↓
fetch persisted HomeAnchor
    ↓
nếu source == userConfirmed
    dùng trực tiếp
    không chạy Full Home Detector
    ↓
nếu chưa confirmed
    dùng persisted inferred nếu phù hợp
    hoặc chạy Full Home Detector
    ↓
Trip Discovery dùng resolved Home này
```

Có thể thay API thành:

```swift
EventDiscoveryEngine.discover(
    ...,
    preferredHome: HomeAnchor?
)
```

Không để `EventDiscoveryEngine` luôn tự quyết Home từ đầu.

---

## 4. Acceptance Criteria — Home

* User-confirmed Home luôn thắng inferred Home.
* Full Home Detector không chạy vô ích khi đã có confirmed Home.
* Trip Discovery dùng đúng confirmed Home.
* Event Quality và Travel Context dùng cùng một Home.
* Fast Home Candidate UX không bị thay đổi.
* Returning user đã xác nhận Home không bị hỏi lại.
* Diagnostics hiển thị rõ:

```text
Home source: User Confirmed
```

hoặc:

```text
Home source: Inferred
```

---

# PHASE 2 — FIX TRIP ELIGIBILITY

## 5. Vấn đề

Trip hiện có thể được tạo từ một Event đơn lẻ mà không cần:

* khoảng cách tối thiểu;
* duration tối thiểu;
* overnight;
* departure/return Home;
* nhiều Event.

`.dayTrip` hiện gần như chỉ có nghĩa:

```text
overnightCount == 0
```

nên chưa phản ánh đúng nghĩa “chuyến đi trong ngày”.

---

## 6. Tách Trip Eligibility và Trip Classification

Không classify trước khi xác định sequence có thật sự là Trip.

Pipeline mới:

```text
Events
   ↓
Trip Eligibility
   ↓
nếu đủ điều kiện
   ↓
Trip Grouping
   ↓
Travel Classification
```

---

## 7. Trip Eligibility V1

Một group có thể trở thành Trip khi thỏa một trong các nhóm rõ ràng.

### Overnight Trip

```text
away from Home
+
overnightCount >= 1
+
distance from Home đủ đáng kể
```

### Day Trip

```text
away from Home
+
duration đủ dài
+
distance đủ xa
+
có đủ activity/session
```

### International Trip

```text
country khác Home country
```

Một international Event đơn lẻ vẫn có thể trở thành Trip nếu evidence rõ.

Một Event ngắn gần Home không được trở thành Trip.

---

## 8. Classification chỉ chạy sau Eligibility

Sau khi đủ điều kiện:

```swift
dayTrip
domesticTrip
internationalTrip
```

Không tạo `PhotoTrip` cho hoạt động local thông thường.

---

## 9. Acceptance Criteria — Trip

* Event gần Home trong thời gian ngắn không thành Trip.
* Day Trip thực sự yêu cầu away + distance/duration.
* Trip qua đêm được nhận biết.
* International Trip được nhận biết.
* Departure/Return được tính bằng đúng confirmed Home.
* Nhiều Event nhỏ trong một hành trình được nhóm thành một Trip.
* Không merge các Event con thành một PhotoEvent lớn.
* Event con vẫn được giữ nguyên.

---

# PHASE 3 — AUTO MEMORY MARKING

## 10. Product Model

Không tạo entity Memory mới.

Dùng trực tiếp `PhotoEvent`.

Giữ hai trạng thái riêng:

```swift
isLoved: Bool
isAutoMemory: Bool
```

Ý nghĩa:

```text
isLoved
= user chủ động ♥ Event

isAutoMemory
= Nizi tự đánh giá Event đáng xuất hiện như Kỷ niệm
```

Home lấy:

```text
isLoved || isAutoMemory
```

Heart không tự sáng chỉ vì `isAutoMemory == true`.

---

## 11. Không dùng Fast Event Quality một mình

Không làm:

```text
meaningful Event
→ Auto Memory
```

Fast Event Quality trả lời:

> Event có sạch và có đủ ý nghĩa cơ bản hay không?

Memory Potential trả lời:

> Event có đủ đặc biệt để Nizi chủ động đưa ra Home hay không?

---

## 12. Memory Potential Evaluator

Tạo một service nhẹ:

```swift
MemoryPotentialEvaluator
```

Chạy sau:

```text
Trip Discovery
+
Fast Event Quality
```

Không chạy Vision.

Không chạy Curation hàng loạt.

---

## 13. Rule V1

Điều kiện nền:

```text
eventVisibility != hiddenNoise
AND
eventQualityScore >= high threshold
```

Và phải có ít nhất một strong signal:

```text
- thuộc International Trip;
- thuộc Domestic Trip nhiều ngày;
- away from Home rõ ràng;
- Event kéo dài đủ lâu;
- Favorite count cao;
- Favorite ratio cao;
- nhiều session/moment đa dạng;
- số ảnh đáng kể nhưng không dùng photo count một mình.
```

Ví dụ:

```text
Quality cao
6 ảnh ở nhà
10 phút
0 Favorite
→ không Auto Memory
```

```text
Quality tốt
3 ngày ở Đà Nẵng
away from Home
8 Favorite
→ Auto Memory
```

---

## 14. Auto Memory phải bảo thủ

Mục tiêu ban đầu:

```text
1.600 Events
↓
một số lượng nhỏ Auto Memories thực sự nổi bật
```

Không biến phần lớn Event thành Memory.

Threshold và reason phải nằm trong config, không hard-code rải rác.

---

## 15. Persist reason để Diagnostics

Có thể lưu:

```swift
isAutoMemory: Bool
autoMemoryScore: Double
autoMemoryReasons: [String]
```

Nếu không muốn persist array, có thể dùng bit flags hoặc derive lại trong Diagnostics.

Ví dụ:

```text
Auto Memory

✓ Quality cao
✓ Domestic Trip
✓ 3 ngày
✓ 8 Favorite
```

Không cần hiện reason này trên production Home V1.

---

## 16. Không chạy Curation khi đánh dấu Memory

Flow:

```text
Event Discovery
    ↓
Fast Event Quality
    ↓
Memory Potential
    ↓
isAutoMemory = true
    ↓
Home hiển thị Event
```

Khi user mở Event/Memory:

```text
Curation chạy lazy nếu chưa có cache
```

Không curate hàng chục hoặc hàng trăm Event ngay sau scan.

---

## 17. Acceptance Criteria — Auto Memory

* Loved Event vẫn xuất hiện trên Home.
* Auto Memory cũng xuất hiện trên Home.
* Auto Memory không tự bật trạng thái heart.
* User có thể ♥ một Auto Memory.
* User có thể bỏ Love mà Auto Memory vẫn còn nếu `isAutoMemory == true`.
* Có cách loại Auto Memory khỏi Home sau này, nhưng chưa bắt buộc trong V1.
* Không tạo `MemoryCandidate`.
* Không chạy `MemoryBuilder`.
* Không chạy Vision hàng loạt.
* Không làm initial scan chậm đáng kể.

---

# PHASE 4 — HOME DATA SOURCE

## 18. Home section “Kỷ niệm”

Data source:

```text
Events
WHERE
isLoved == true
OR
isAutoMemory == true
```

Sort ban đầu:

```text
event date DESC
```

Có thể ưu tiên Loved trước Auto sau này, nhưng chưa cần trong V1.

---

## 19. Presentation distinction

Không cần tách thành hai section lớn.

Có thể dùng một section:

```text
Kỷ niệm
```

Auto Memory có thể có label tinh tế:

```text
Nizi chọn
```

Loved Event có heart đỏ.

Không làm Home thành dashboard.

---

# PHASE 5 — LAZY EVENT PLACE ENRICHMENT

## 20. Địa danh Event

Không reverse-geocode toàn bộ 1.600 Event sau scan.

Dùng:

```text
Event hiện/sắp hiện trên viewport
        ↓
representative coordinate
        ↓
reverse geocode một lần
        ↓
persist/cache
```

Display:

### Việt Nam

```text
Phường/Xã - Thành phố
```

### Nước ngoài

```text
Thành phố - Quốc gia
```

Không cần POI, đường hoặc địa chỉ chi tiết.

---

## 21. Priority

Ưu tiên resolve:

```text
Event Detail hiện tại
>
Home Memories
>
visible Event cards
>
small viewport prefetch
```

Không geocode hàng loạt.

---

# PHASE 6 — EVENT HIGHLIGHTS VALIDATION

## 22. Curation V2 đã triển khai

Đã có:

* manual override preservation;
* source asset fingerprint;
* quality gate;
* local clustering cải tiến;
* global duplicate suppression;
* Favorite priority;
* temporal diversity;
* Diagnostics;
* algorithm version 2.

Việc còn lại là đánh giá trên thư viện thật.

---

## 23. Vấn đề số lượng selected

Nếu Event khoảng 500 ảnh nhưng chọn gần 400 ảnh:

đây là lỗi về selection cap/balance, không phải chỉ similarity threshold.

Cần đảm bảo:

```text
same moment
→ giới hạn auto-selection

toàn Event
→ giới hạn final Highlights
```

Suggested V1:

```text
maxAutoSelectedPerMoment = 2
```

User-added không chịu giới hạn này.

Event khoảng 500 ảnh nên chỉ còn khoảng vài chục Highlights, không phải hàng trăm.

Không chỉnh similarity threshold trước khi xác nhận cap hoạt động đúng.

---

# PHASE 7 — DIAGNOSTICS CLARITY

## 24. Phân biệt các màn Diagnostics

### Event Boundary

Hiển thị rõ:

```text
Preview only
Does not modify persisted Events
```

### Detected Trips

Hiển thị rõ:

```text
Production pipeline result
May persist Trip/location intelligence
```

### Home Detection

Hiển thị:

```text
Resolved Home
Source: User Confirmed / Inferred
```

### Fast Event Quality

Hiển thị:

```text
Production Event Quality
```

### Memory Potential

Thêm Diagnostics:

```text
Memory score
Auto Memory: YES/NO
Reasons
```

---

# 25. Thứ tự triển khai bắt buộc

Không làm tất cả đồng thời.

```text
STEP 1
Unify Home Source

STEP 2
Fix Trip Eligibility + dayTrip semantics

STEP 3
Re-run Trip Diagnostics trên thư viện thật

STEP 4
Implement Memory Potential Evaluator

STEP 5
Persist isAutoMemory

STEP 6
Update Home query:
isLoved OR isAutoMemory

STEP 7
Add Memory Potential Diagnostics

STEP 8
Implement Lazy Event Place Enrichment

STEP 9
Validate Curation V2 and final highlight caps
```

Không làm Auto Memory trước khi Trip Discovery dùng đúng Home, vì các signal:

```text
away from Home
domestic Trip
international Trip
```

sẽ chưa đáng tin.

---

# 26. Những thứ chưa làm

Không scope creep:

* không tạo entity Memory mới;
* không refactor `MemoryCandidate` trong task này;
* không merge Event con thành Event lớn;
* không xóa Event rác;
* không chạy Vision toàn library;
* không auto-curate mọi Memory;
* không backend;
* không Cloud AI;
* không location POI;
* không multi-home history;
* không Trip → Album tự động;
* không redesign Home trong cùng task.

---

# 27. Kiến trúc mục tiêu sau các bước này

```text
Photo Library
      ↓
Sessions
      ↓
Event Boundary
      ↓
PhotoEvents
      ↓
Trip Discovery
      ↓
Fast Event Quality
      ↓
Memory Potential
      ↓
PhotoEvent flags:
- isLoved
- isAutoMemory
      ↓
Home “Kỷ niệm”
```

Song song:

```text
Visible Event
      ↓
Lazy Place Enrichment
```

Và khi user mở Event:

```text
Lazy Curation
      ↓
Highlights
```

---

# 28. Product Principle

Không thêm một tầng dữ liệu mới khi chỉ cần đánh dấu Event.

```text
Event
+
Love hoặc Auto Memory
=
Kỷ niệm
```

Nizi tự đề xuất trước.

User có thể xem, ♥ và chỉnh Highlights sau.

```

Thứ tự quan trọng nhất là **sửa Home source trước, rồi sửa Trip eligibility, sau đó mới Auto Memory**. Nếu làm Auto Memory ngay bây giờ, các tín hiệu chuyến đi xa/trong nước/nước ngoài vẫn có thể sai vì Trip Discovery chưa sử dụng đúng Home mà user đã xác nhận.
```
