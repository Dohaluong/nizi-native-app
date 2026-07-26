# SPEC-MEMORY-DISCOVERY

## 1. Tên tính năng

**Memory Discovery — Khám phá ký ức**

---

## 2. Mục tiêu sản phẩm

Giúp người dùng tìm lại các sự kiện có ý nghĩa trong thư viện ảnh nhiều năm trên iPhone và chuyển chúng thành Album Nizi mà không phải upload toàn bộ ảnh trước.

---

## 3. Problem Statement

Người dùng có hàng nghìn ảnh nhưng:

- khó nhớ ảnh nằm ở đâu;
- không có thời gian tự phân loại;
- có quá nhiều ảnh giống nhau;
- không biết nên chọn ảnh nào;
- ngại upload hàng trăm MB hoặc hàng GB;
- ít khi tạo được album hoàn chỉnh.

Nizi cần giải quyết điểm bắt đầu:

> Tự tìm các cụm ảnh đáng nhớ trước, sau đó mới mời người dùng tạo Album.

---

## 4. User Story chính

### US-01

Là người dùng Nizi, tôi muốn Nizi khảo sát thư viện ảnh trên iPhone để tìm những sự kiện đáng nhớ mà không upload toàn bộ thư viện.

### US-02

Tôi muốn xem Nizi đang có quyền Full hay Limited để hiểu phạm vi khảo sát.

### US-03

Tôi muốn thấy tiến độ quét và có thể tạm dừng.

### US-04

Tôi muốn Nizi đề xuất các cụm ảnh theo thời gian và địa điểm.

### US-05

Tôi muốn xem lý do tại sao Nizi cho rằng một nhóm ảnh là một sự kiện.

### US-06

Tôi muốn thêm, bỏ, gộp hoặc tách ảnh trước khi tạo Album.

### US-07

Tôi chỉ muốn upload những ảnh tôi đã xác nhận.

### US-08

Tôi muốn xóa toàn bộ dữ liệu khảo sát khỏi iPhone mà không xóa ảnh trong Photos.

---

## 5. Phạm vi MVP

MVP bao gồm:

1. Photo permission.
2. Full/Limited/Denied state.
3. Metadata scan.
4. Batch scan.
5. Checkpoint và resume.
6. Timeline theo năm/tháng.
7. Temporal clustering.
8. Spatial clustering cơ bản.
9. EventCandidate.
10. Candidate list.
11. Candidate detail.
12. Chọn/bỏ ảnh.
13. Tạo AlbumDraft local.
14. Chuẩn bị handoff sang API.
15. Incremental update cơ bản.
16. Xóa dữ liệu khảo sát.

MVP chưa bao gồm:

- nhận diện danh tính;
- cloud AI phân tích toàn thư viện;
- semantic search;
- photobook auto-layout;
- tự động upload;
- đồng bộ LocalMemoryIndex giữa các máy;
- đánh giá thẩm mỹ nâng cao;
- học sở thích dài hạn.

---

## 6. Functional Requirements

## FR-01 — Photo Authorization

Hệ thống phải:

- đọc trạng thái hiện tại;
- yêu cầu quyền sau khi giải thích;
- hỗ trợ Full Access;
- hỗ trợ Limited Access;
- hỗ trợ Denied;
- cho phép mở Settings khi cần.

### Acceptance Criteria

- App không crash khi denied.
- Limited hiển thị rõ chỉ xử lý ảnh được cấp.
- Full cho phép scan toàn bộ asset khả dụng.

---

## FR-02 — Initial Scan

Hệ thống phải:

- scan theo batch;
- không block UI;
- hiển thị progress;
- lưu checkpoint;
- pause/resume;
- tiếp tục sau khi app mở lại.

### Acceptance Criteria

- Đóng app giữa scan, mở lại có thể tiếp tục.
- Asset đã index không bị insert duplicate.
- Một asset lỗi không dừng toàn bộ scan.

---

## FR-03 — Metadata Index

Mỗi asset lưu tối thiểu:

```text
assetLocalIdentifier
creationDate
mediaType
pixelWidth
pixelHeight
location nếu có
favorite
screenshot
burstIdentifier nếu có
availability
```

Không lưu ảnh gốc.

---

## FR-04 — Timeline Explorer

Hệ thống cho phép duyệt:

- năm;
- tháng;
- số ảnh;
- thumbnail đại diện.

MVP chưa cần gallery hoàn chỉnh như Apple Photos.

---

## FR-05 — Temporal Grouping

Ảnh được sắp theo `creationDate`.

Hệ thống tạo PhotoSession dựa trên:

- khoảng cách thời gian;
- mật độ chụp;
- chuyển ngày;
- vị trí nếu có.

Ngưỡng phải cấu hình được.

---

## FR-06 — Spatial Grouping

Nếu có GPS, hệ thống dùng:

- khoảng cách giữa ảnh;
- cluster center;
- geo cell;
- chuỗi di chuyển.

Không gọi reverse geocoding cho từng ảnh.

---

## FR-07 — Event Candidate

Một EventCandidate phải có:

- khoảng thời gian;
- số ảnh;
- cover tạm;
- title gợi ý;
- location label nếu có;
- score;
- reasons;
- status.

### Candidate Reason ví dụ

```text
126 ảnh trong 3 ngày
Phần lớn được chụp tại cùng khu vực
Có 5 phiên chụp liên tiếp
12 ảnh được đánh dấu Favorite
```

---

## FR-08 — Candidate List

Danh sách sắp theo:

1. score;
2. mới nhất;
3. chưa xem.

Mỗi card có:

- cover;
- title;
- date range;
- asset count;
- location;
- CTA xem lại.

---

## FR-09 — Candidate Review

Người dùng có thể:

- chọn/bỏ ảnh;
- đổi cover;
- đổi title;
- xem theo session;
- dismiss;
- snooze;
- convert thành AlbumDraft.

MVP chưa cần split/merge nâng cao nếu ảnh hưởng tiến độ; có thể để Sprint sau.

---

## FR-10 — Album Draft

AlbumDraft phải:

- tồn tại local;
- không tạo Album server ngay;
- lưu selection;
- lưu cover;
- lưu sort order;
- lưu upload state.

---

## FR-11 — Upload Handoff

Chỉ khi người dùng xác nhận:

```text
AlbumDraft
→ create album API
→ create upload session
→ request original
→ upload selected assets
→ complete
```

Không upload candidate chưa xác nhận.

---

## FR-12 — Incremental Changes

Hệ thống nhận biết:

- asset mới;
- asset bị xóa;
- asset thay đổi;
- quyền thay đổi.

Chỉ rebuild cluster bị ảnh hưởng nếu có thể.

MVP được phép thực hiện incremental đơn giản:

- index asset mới;
- đánh dấu deleted;
- chạy lại candidate trong khoảng thời gian liên quan.

---

## FR-13 — Data Reset

Người dùng có thể xóa dữ liệu khám phá.

App phải cảnh báo:

- dữ liệu candidate sẽ mất;
- ảnh trong Photos không bị xóa;
- Album đã upload không bị xóa.

---

## 7. Non-functional Requirements

## NFR-01 — Privacy

- Không upload ngầm.
- Không gửi GPS chưa xác nhận.
- Không log nội dung ảnh.
- Không lưu face identity trong MVP.

## NFR-02 — Performance

- UI không freeze khi scan.
- Không giữ toàn bộ thumbnail trong RAM.
- Scan 50.000 asset phải có thể resume.
- Thumbnail request phải cancellable.

## NFR-03 — Reliability

- Batch transaction.
- Retry giới hạn.
- Checkpoint.
- Idempotent upsert.
- Không duplicate.

## NFR-04 — Explainability

Mỗi candidate có ít nhất một lý do hiển thị được.

## NFR-05 — Testability

Clustering và scoring test được bằng synthetic metadata.

---

## 8. Permission Flow

```text
User mở Khám phá ký ức
→ Onboarding
→ User bấm Bắt đầu
→ Request Photos Access
    ├── Full → scan
    ├── Limited → scan phạm vi giới hạn
    ├── Denied → hướng dẫn Settings
    └── Not determined → chờ kết quả
```

Không xin quyền ngay khi mở app lần đầu.

---

## 9. Scan Flow

```text
Start Scan
→ Estimate asset count
→ Fetch batch
→ Normalize
→ Upsert LocalAsset
→ Save checkpoint
→ Update progress
→ Continue
→ Create initial sessions
→ Create first candidates
→ Complete
```

Cho phép hiển thị candidate đầu tiên trước khi scan xong toàn bộ.

---

## 10. Discovery Rules MVP

### Temporal rules

```text
gap <= 30 phút: cùng session
30 phút < gap <= 3 giờ: xét cùng session
3 giờ < gap <= 8 giờ: cần location/density hỗ trợ
gap > 8 giờ: session mới
```

### Spatial rules

Giá trị khởi điểm:

```text
< 2 km: cùng khu vực mạnh
2–20 km: có thể cùng event
20–100 km: xét theo trip
> 100 km: thường là địa điểm mới
```

Không hard-code trong UI. Đặt trong config.

### Minimum candidate

Mặc định:

```text
ít nhất 12 ảnh
hoặc ít nhất 6 ảnh nếu có Favorite/mật độ cao
```

### Noise

Giảm điểm:

- screenshot;
- ảnh không có creationDate;
- burst quá lớn;
- ảnh quá thưa;
- cụm lặp hàng ngày.

---

## 11. Event Types MVP

```text
trip
dayEvent
weekend
unknown
```

Không cần tự xác định sinh nhật, Tết, đám cưới trong MVP.

---

## 12. Candidate Scoring MVP

Mỗi thành phần chuẩn hóa 0...1.

```text
score =
  0.30 * temporalCohesion
+ 0.25 * spatialCohesion
+ 0.20 * density
+ 0.10 * favoriteRatio
+ 0.10 * durationValue
+ 0.05 * mediaDiversity
- noisePenalty
```

Chỉ là điểm khởi đầu, phải điều chỉnh bằng test thật.

---

## 13. Empty/Error States

### Không có quyền

> Nizi cần quyền truy cập Photos để tìm lại các sự kiện trong thư viện.

### Limited

> Nizi đang khảo sát những ảnh bạn đã cho phép.

### Không có candidate

> Nizi chưa tìm thấy sự kiện đủ rõ. Bạn có thể duyệt theo năm hoặc mở rộng phạm vi ảnh được cho phép.

### Asset unavailable

> Ảnh này hiện không còn khả dụng trong thư viện Photos.

### iCloud required

> Ảnh gốc cần được tải từ iCloud trước khi upload.

---

## 14. Analytics Events

Chỉ log sự kiện sản phẩm, không log dữ liệu ảnh.

```text
memory_discovery_opened
photo_permission_requested
photo_permission_full
photo_permission_limited
photo_permission_denied
scan_started
scan_paused
scan_resumed
scan_completed
candidate_created
candidate_opened
candidate_dismissed
candidate_accepted
album_draft_created
upload_started
upload_completed
discovery_data_cleared
```

---

## 15. API Contract tối thiểu với Nizi Web

### Create Album

```http
POST /api/mobile/albums
```

Payload:

```json
{
  "title": "Đà Nẵng 2024",
  "startDate": "2024-06-08",
  "endDate": "2024-06-11",
  "locationLabel": "Đà Nẵng, Hội An",
  "photoCount": 42
}
```

### Create Upload Session

```http
POST /api/mobile/albums/{albumId}/upload-sessions
```

### Register Photo

```http
POST /api/mobile/upload-sessions/{sessionId}/photos
```

### Complete Upload

```http
POST /api/mobile/upload-sessions/{sessionId}/complete
```

API chi tiết sẽ viết ở tài liệu mobile API riêng.

---

## 16. Security

- API yêu cầu access token.
- Không dùng database credential trên iOS.
- Upload URL nên có thời hạn.
- Server kiểm tra album ownership.
- Không tin metadata từ client tuyệt đối.
- Không gửi `assetLocalIdentifier` lên server nếu không cần.

---

## 17. Acceptance Test cấp module

1. Chạy trên iPhone thật.
2. Full Access scan được thư viện.
3. Limited chỉ đọc ảnh được cấp.
4. Denied không crash.
5. Ảnh có date/GPS được index.
6. Scan dừng và tiếp tục được.
7. Candidate được tạo từ synthetic và real library.
8. Candidate có reason.
9. User chọn ảnh và tạo AlbumDraft.
10. Chỉ ảnh selected mới vào upload queue.
11. Asset bị xóa được đánh dấu unavailable.
12. Xóa discovery data không xóa Photos.
