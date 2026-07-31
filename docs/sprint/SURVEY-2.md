
# SURVEY — EVENT PHOTO CURATION / HIGHLIGHT SELECTION

## Mục tiêu

KHÔNG sửa code.

Tôi cần hiểu chính xác cơ chế Nizi hiện đang dùng để:

- tự chọn ảnh khi mở Event;
- loại ảnh xấu;
- xử lý ảnh giống/trùng;
- chọn ảnh đại diện;
- persist kết quả;
- reuse kết quả khi mở Event lần sau.

Vấn đề thực tế:

> Event segmentation hiện đã khá tốt, nhưng ảnh Nizi tự chọn trong Event vẫn còn nhiều ảnh không đáng chọn và nhiều ảnh gần giống nhau.

Trước khi điều chỉnh thuật toán, hãy khảo sát toàn bộ pipeline hiện tại.

---

# 1. Khi nào Curation thực sự chạy?

Khảo sát `EventDetailView`.

Trả lời chính xác:

### Lần đầu mở Event:

```text
EventDetailView appears
        ↓
?
        ↓
EventPhotoCurationService
````

Có đúng không?

Cho biết:

* `.task`
* `.onAppear`
* explicit button
* coordinator
* service call

nào kích hoạt curation.

Đưa file + function cụ thể.

---

# 2. Lần thứ hai mở Event

Nếu Event đã curate:

* có chạy Vision lại không?
* có load thumbnail lại không?
* hay lấy `EventCurationResult` từ SwiftData?

Mô tả cache/reuse rule chính xác.

Ví dụ kiểm tra:

```text
eventID
algorithmVersion
sourcePhotoCount
status
```

Nếu một trong số đó thay đổi thì chuyện gì xảy ra?

---

# 3. Pipeline đầy đủ

Vẽ pipeline thật từ code:

```text
PhotoEvent
    ↓
fetch assets
    ↓
fetch sessions
    ↓
?
    ↓
Vision analysis
    ↓
?
    ↓
Grouping
    ↓
?
    ↓
Scoring
    ↓
?
    ↓
Selection
    ↓
EventCurationResult
```

Không mô tả theo assumption.

Phải dựa vào implementation thật.

---

# 4. Các class/service liên quan

Khảo sát tối thiểu:

```text
EventPhotoCurationService
EventPhotoCurationEngine

VisionEventPhotoAnalyzer
EventPhotoAnalysis

PhotoCurationGroup
PhotoCurationItem
EventCurationResult

EventDetailView
MemorySelectionEditView

MDEventCurationResult
MDPhotoCurationGroup
MDPhotoCurationItem
```

Grep thêm các protocol/helper được gọi trong pipeline.

---

# 5. FILTER — app hiện loại những ảnh nào?

Liệt kê toàn bộ rule hiện có.

Ví dụ kiểm tra có detection cho:

```text
screenshot
document
blur
bad exposure
very dark
very bright
tiny image
screen capture
QR/document
```

Với mỗi rule:

```text
signal
threshold
penalty / exclusion
```

Cho biết:

* ảnh bị loại hẳn;
* hay chỉ bị trừ score.

---

# 6. Favorite photo

Khảo sát `IndexedAsset.isFavorite`.

Favorite hiện ảnh hưởng như thế nào tới curation?

Ví dụ:

```text
favorite → +score?
favorite → forced selected?
favorite → representative priority?
```

Cho exact rule/weight.

Nếu Favorite không được dùng trong Event curation, nói rõ.

---

# 7. Duplicate / Near-Duplicate

Đây là phần quan trọng nhất.

Khảo sát xem pipeline hiện có thực sự detect ảnh trùng/gần giống nhau không.

Tìm:

```text
featurePrint
similarity
distance
duplicate
nearDuplicate
burst
group
visualSimilarity
```

Trả lời:

### Có visual grouping không?

Nếu có:

```text
VNFeaturePrintObservation
```

hoặc mechanism nào?

### Similarity threshold bao nhiêu?

### Có kết hợp time gap không?

Ví dụ:

```text
2 photos
time gap < 2 min
+
visual similarity > threshold
→ same group
```

hay chỉ dùng visual?

---

# 8. Burst / Same Moment

PhotoSession có đang được dùng như proxy cho “same moment” không?

Ví dụ một session có:

```text
15 ảnh trong 2 phút
```

engine:

* chọn 1?
* chọn nhiều?
* không giới hạn?

Cho rule thật.

---

# 9. PhotoCurationGroup được tạo như thế nào?

Đây là điểm cần hiểu kỹ.

Một `PhotoCurationGroup` đại diện cho:

* một Session?
* nhóm near-duplicate?
* time cluster?
* visual cluster?
* hay combination?

Đưa implementation.

---

# 10. Chọn bao nhiêu ảnh trong mỗi group?

Có rule như:

```text
1 ảnh/group
2 ảnh/group
% group size
```

không?

Nếu một group có:

```text
10 ảnh gần giống
```

tại sao hiện có thể vẫn chọn nhiều ảnh?

Tìm nguyên nhân từ code.

---

# 11. Beauty / Quality Score

Liệt kê đầy đủ score hiện có.

Ví dụ:

```text
sharpness
exposure
face count
face quality
favorite
document penalty
technical quality
```

Cho formula hoặc weight cụ thể.

Ví dụ:

```text
score =
 sharpness * X
 + exposure * Y
 + ...
```

Không cần giải thích Vision tổng quát; chỉ cần implementation hiện tại.

---

# 12. Face Detection

Khảo sát:

```text
face landmarks
face count
face area
closed eyes?
```

thực sự dùng thế nào.

Có phải cứ nhiều face thì score cao?

Có xử lý:

```text
group photo
very small faces
partial face
```

không?

---

# 13. Sharpness

Sharpness đang tính thế nào?

* pixel variance?
* Core Image?
* Vision?
* custom analyzer?

Range score?

Threshold?

Có loại blur hay chỉ penalize?

---

# 14. Exposure

Exposure metric hiện tại:

* brightness?
* histogram?
* clipped highlights?
* shadows?

Có ảnh tối/sáng nào bị hard reject không?

---

# 15. Document Detection

Survey trước nói Vision analyzer có document segmentation.

Xác nhận:

```text
VNDetectDocumentSegmentationRequest
```

hoặc implementation tương đương.

Document ảnh hưởng selection như thế nào?

---

# 16. Screenshot

Screenshot được detect từ:

```text
PHAsset mediaSubtype
```

hay Vision?

Có loại screenshot khỏi curation không?

Nếu screenshot vẫn xuất hiện trong selected photos, tìm lý do.

---

# 17. Feature Print

Khảo sát chính xác feature print được dùng để:

```text
score quality?
group duplicates?
select diversity?
```

hay chỉ được calculate nhưng không tận dụng đầy đủ.

Đây là câu hỏi quan trọng.

---

# 18. Diversity

Sau khi rank score, engine có đảm bảo diversity không?

Ví dụ đã chọn:

```text
Beach photo A
```

thì Beach photo B gần giống có penalty không?

Có:

```text
Maximal Marginal Relevance
similarity penalty
one-per-cluster
temporal diversity
```

hay không?

Nếu không có, nói rõ.

---

# 19. Temporal Coverage

Engine có cố giữ:

```text
đầu Event
giữa Event
cuối Event
```

không?

Hay chỉ chọn top quality score toàn Event?

Ví dụ Event 3 ngày:

```text
Day 1 100 ảnh đẹp
Day 2 20 ảnh
Day 3 30 ảnh
```

có nguy cơ selected tập trung Day 1 không?

---

# 20. Location Diversity

GPS/location có được dùng khi chọn highlights không?

Nếu một Event có:

```text
Hotel
Beach
Restaurant
Museum
```

engine có cố chọn đại diện mỗi place không?

Hay location không tham gia curation?

---

# 21. Target selection count

Nizi quyết định chọn bao nhiêu ảnh như thế nào?

Ví dụ:

```text
Event 20 ảnh → ? selected
Event 100 ảnh → ?
Event 500 ảnh → ?
```

Cho exact formula/config.

---

# 22. Minimum / maximum selection

Có:

```text
minimumSelected
maximumSelected
selectionRatio
```

không?

Các value hiện tại?

---

# 23. Manual User Selection

Nếu user:

```text
+ thêm ảnh
- bỏ ảnh
```

thì lưu ở đâu?

Khảo sát:

```text
selectionSource
userAdded
userRemoved
```

Khi algorithm version thay đổi/recurate:

manual choice có được preserve không?

---

# 24. Curation invalidation

Curation được chạy lại khi nào?

Ví dụ:

```text
algorithmVersion changed
photo count changed
event changed
```

Nếu chỉ thêm 1 ảnh vào Event:

* toàn bộ analysis chạy lại?
* hay incremental?

---

# 25. Algorithm Version

Tìm current:

```text
algorithmVersion
```

Giá trị hiện tại là gì?

Nếu thay đổi thuật toán duplicate selection sau này:

chỉ cần bump version là curation rebuild?

Xác nhận.

---

# 26. Vision cost

Survey trước nói analyzer:

* request thumbnail 256×256;
* face landmarks;
* feature print;
* document segmentation;
* sharpness/exposure;
* concurrency tối đa 2.

Xác nhận code hiện tại.

Cho biết:

```text
mỗi photo chạy bao nhiêu Vision request
```

và pipeline có reuse analysis không.

---

# 27. Performance khi mở Event lần đầu

Không benchmark nếu không chạy được app.

Nhưng từ code hãy mô tả:

```text
Event 20 photos
Event 100 photos
Event 500 photos
```

công việc tăng approximately theo:

```text
O(n)
O(n²)
```

Đặc biệt kiểm tra duplicate similarity:

nếu so từng ảnh với từng ảnh thì có O(n²) không?

---

# 28. UI Progress

Khi Event curation chạy lần đầu:

user thấy gì?

* spinner?
* progress count?
* skeleton?
* Event images xuất hiện dần?
* UI block hoàn toàn?

Cho exact behavior.

---

# 29. Curation Diagnostics

Có màn/debug hiện tại cho biết:

```text
ảnh nào selected
ảnh nào rejected
score
reason
duplicate group
```

không?

Nếu không có, nói rõ.

Không implement.

---

# 30. Phân tích 3 lỗi chính

Dựa trên code, xác định khả năng gây ra ba vấn đề:

### A. Ảnh gần giống vẫn được chọn nhiều

Do:

* không group?
* threshold?
* group nhưng chọn nhiều?
* feature print chưa dùng?

### B. Ảnh không đáng chọn vẫn lọt

Do:

* quality score yếu?
* minimum quota?
* forced coverage?
* không hard reject?

### C. Ảnh quan trọng bị bỏ

Do:

* Favorite weight thấp?
* diversity?
* group representative sai?
* target count thấp?

Không sửa, chỉ trace nguyên nhân có thể chứng minh từ code.

---

# 31. Đề xuất cấu trúc cải tiến — chỉ sau khảo sát

Cuối báo cáo, map implementation hiện tại vào 4 tầng:

```text
FILTER
GROUP
SELECT REPRESENTATIVE
RANK + DIVERSITY
```

Cho bảng:

| Layer                 | Hiện đã có? | Implementation | Điểm yếu |
| --------------------- | ----------- | -------------- | -------- |
| Filter                |             |                |          |
| Group near duplicates |             |                |          |
| Select best per group |             |                |          |
| Global ranking        |             |                |          |
| Temporal diversity    |             |                |          |
| Visual diversity      |             |                |          |
| Favorite priority     |             |                |          |

---

# 32. Không sửa code

Task này chỉ khảo sát.

Không:

* đổi threshold;
* bump algorithm version;
* thêm duplicate logic;
* sửa selection count;
* thêm UI;
* thay Vision;
* refactor curation.

Mục tiêu duy nhất:

> Hiểu chính xác vì sao Event curation hiện vẫn chọn nhiều ảnh gần giống và một số ảnh không đáng chọn.


