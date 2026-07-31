# SPRINT — INITIAL SCAN MEMORY JOURNEY & HOME CONFIRMATION

> **Project:** Nizi  
> **Priority:** P0 — First User Experience  
> **Scope:** Production onboarding / initial photo scan UX  
> **Principle:** Không cố biến initial scan thành một loading screen ngắn. Biến thời gian scan thành trải nghiệm “quay lại ký ức”, đồng thời cho user xác nhận Home một cách nhẹ nhàng trong lúc scan vẫn tiếp tục.

---

# 1. Bối cảnh

Nizi hiện có thể scan một thư viện rất lớn, thực tế khoảng 105.000 ảnh.

Initial scan là bước lâu nhất:

```text
Photo Library
    ↓
Metadata Scan
    ↓
Local Memory Index
    ↓
Session / Event Discovery
    ↓
First Memory
```

Event Discovery hiện đã cải thiện đáng kể và tạo các Event nhỏ, chính xác hơn.

Vấn đề UX còn lại:

- scan lâu;
- user không biết app đang thực sự làm gì;
- progress hiện chưa tạo cảm xúc;
- user dễ nghĩ app bị treo;
- Home Detector tự động tương đối nặng nhưng production thực tế vẫn cần biết Home để phân biệt local / away / trip.

Sprint này giải quyết cả hai bằng một flow thống nhất.

---

# 2. Product Decision

## Không dùng Full Home Detector trong production onboarding

Full Home Detector hiện tại:

- giữ lại cho Diagnostics / research;
- không bắt user chờ;
- không phải dependency để hoàn tất onboarding;
- không chạy như một bước bắt buộc sau scan.

Production sử dụng:

```text
FAST HOME CANDIDATES
        ↓
USER CONFIRMATION
        ↓
USER-CONFIRMED HOME
```

---

# 3. Core UX

Sau khi user cấp quyền Photos:

```text
SCAN STARTS IMMEDIATELY
        ↓
MEMORY JOURNEY
        ↓
năm + ảnh + progress xuất hiện dần
        ↓
HOME CONFIRMATION CARD
        ↓
scan vẫn chạy
        ↓
MEMORY JOURNEY tiếp tục
        ↓
EVENT DISCOVERY
        ↓
FIRST MEMORY
```

Nguyên tắc bắt buộc:

> **Scan là background process. Memory Journey là foreground experience.**

Không pause scan chỉ để user đọc hoặc chọn Home.

---

# 4. Memory Journey

Không dùng màn hình scan kiểu kỹ thuật:

```text
Scanning...
43%
42,521 / 105,283
```

Thay bằng:

```text
Đang tìm lại những kỷ niệm của bạn


              2018
           8 năm trước

          [ HERO PHOTO ]

      [photo] [photo] [photo]


42.521 / 105.283 ảnh

████████████░░░░░░

Đang xem lại năm 2018
```

User phải cảm thấy:

> Nizi đang đi qua lịch sử ảnh của mình.

---

# 5. Current Scan Year

Scanner phải expose năm của asset/batch hiện tại.

Ví dụ:

```text
2014
↓
2015
↓
2016
↓
...
↓
2026
```

hoặc ngược lại nếu scanner thực tế scan newest-first.

Không giả lập thứ tự năm.

UI phản ánh chính xác scanner đang ở đâu.

---

# 6. Year Presentation

Hiển thị:

```text
2018
8 năm trước
```

Current year:

```text
2026
Năm nay
```

Previous year:

```text
2025
1 năm trước
```

Tính động bằng `Calendar`.

Không hard-code.

Khi đổi năm:

- crossfade;
- hoặc transition nhẹ;
- không animation phức tạp.

---

# 7. Photo Preview

Trong quá trình scan, Presentation nhận một lượng nhỏ candidate asset IDs.

Không request thumbnail cho mọi ảnh.

Selection priority:

```text
1. Favorite
2. non-screenshot representative photo
3. ordinary photo fallback
```

Nếu `PHAsset.isFavorite == true`, ưu tiên cao.

Không chạy:

- Vision;
- AI curation;
- embeddings;
- full-resolution loading

chỉ để chọn ảnh scan preview.

---

# 8. Preview Behavior

Mỗi năm có buffer nhỏ:

```text
5–10 candidate assets
```

UI có thể hiện:

```text
[ HERO ]

[ small ] [ small ] [ small ]
```

Khi candidate mới tốt hơn xuất hiện:

```text
crossfade
```

Không update liên tục theo từng asset.

Suggested triggers:

- Favorite mới;
- year changed;
- sau một số lượng asset nhất định;
- representative candidate mới.

UI preview là best-effort.

Scanner luôn có priority cao hơn.

---

# 9. Scan Progress Model

Mở rộng progress callback hiện tại.

Concept:

```swift
struct InitialScanProgress {
    let processedAssetCount: Int
    let totalAssetCount: Int

    let currentYear: Int?

    let previewAssetIDs: [String]

    let phase: InitialScanPhase
}
```

Có thể bổ sung event count nếu engine thực sự expose incremental event discovery.

Không bắt buộc tên/type đúng y hệt.

Reuse infrastructure hiện có.

---

# 10. InitialScanPhase

Concept:

```swift
enum InitialScanPhase {
    case scanning
    case discoveringEvents
    case curatingFirstMemory
    case completed
}
```

Presentation copy theo phase.

### Scanning

```text
Đang xem lại những năm tháng đã qua
```

### Discovering Events

```text
Đang kết nối những khoảnh khắc...
```

### First Memory Curation

```text
Đang chọn những khoảnh khắc nổi bật...
```

### Ready

```text
Nizi vừa tìm thấy một kỷ niệm
```

---

# 11. Event Count

Nếu Event Discovery hiện chỉ chạy sau full scan:

**không refactor lớn chỉ để hiện Event count trong scan phase.**

Khi bước Event Discovery bắt đầu:

```text
Đã tìm thấy 387 sự kiện
```

chỉ khi count là dữ liệu thật.

Nếu engine có incremental output dễ expose:

có thể update dần.

Không fake.

---

# 12. Home Confirmation — nằm trong Memory Journey

Home không phải một onboarding page riêng.

Nó là một **interactive card** xuất hiện trong Memory Journey.

Ví dụ:

```text
┌─────────────────────────────┐
│  Giúp Nizi hiểu bạn hơn     │
│                             │
│  🏠 Đâu là Nhà của bạn?     │
│                             │
│  Nizi dùng thông tin này    │
│  để nhận ra khi nào bạn     │
│  đang đi xa.                │
│                             │
│  ○ Thanh Xuân, Hà Nội       │
│  ○ Cầu Giấy, Hà Nội         │
│  ○ Long Biên, Hà Nội        │
│                             │
│  Chọn địa điểm khác...      │
│                             │
│  [Xác nhận]     Bỏ qua      │
└─────────────────────────────┘
```

Scan phía sau vẫn tiếp tục.

---

# 13. Không hỏi Home quá sớm

Không hiển thị Home card ngay sau permission.

User nên thấy Memory Journey trước.

Ví dụ:

```text
Permission
 ↓
scan
 ↓
2015 + photos
 ↓
2016 + photos
 ↓
processed enough location samples
 ↓
Home card appears
```

Mục tiêu:

> user đã thấy Nizi đang làm điều có ý nghĩa trước khi app hỏi thêm thông tin.

---

# 14. Fast Home Candidate Detector

Không chạy Full Home Detector.

Tạo lightweight service:

```swift
protocol FastHomeCandidateDetecting {
    func candidates(...) async -> [HomeCandidate]
}
```

Mục tiêu:

```text
Top 3 candidates
```

Không cần xác định Home chắc chắn.

Chỉ cần đưa ra những vùng có khả năng cao.

---

# 15. Fast Candidate Strategy

Sử dụng metadata/GPS scanner đã đọc.

Không phân tích toàn bộ 105.000 ảnh với scoring phức tạp.

Ưu tiên **temporal recurrence**.

Home thường có đặc điểm:

```text
xuất hiện ở nhiều tháng
+
nhiều năm
+
nhiều ngày khác nhau
```

Vacation thường:

```text
rất nhiều ảnh
+
nhưng chỉ vài ngày / một khoảng ngắn
```

Do đó candidate scoring không ưu tiên raw photo count.

Concept:

```text
CandidateScore =
    distinctYearScore
  + distinctMonthScore
  + sampledDistinctDayScore
  + recurrenceScore
```

Không cần evening/night/visit segmentation trong Fast Detector V1.

---

# 16. Sampling

Không cần đợi toàn bộ library.

Candidate detector có thể làm việc trên location observations đã scan.

Có thể sampling theo thời gian:

```text
giới hạn observations mỗi tháng / mỗi period
```

Mục tiêu:

- tránh 2.000 ảnh vacation lấn át;
- giữ representation trải dài nhiều năm;
- candidate xuất hiện đủ sớm.

Không hard-code sample strategy trong View.

---

# 17. Candidate Readiness

Home card chỉ xuất hiện khi:

```text
candidate quality đủ dùng
```

Không nhất thiết cần confidence cao như Full Home Detector.

Ví dụ:

```text
>= 2–3 plausible candidates
```

hoặc một candidate rất nổi bật.

Nếu chưa đủ:

Memory Journey tiếp tục.

---

# 18. Reverse Geocoding

Không reverse-geocode hàng trăm cluster.

Chỉ geocode:

```text
Top 3 Home Candidates
```

Ví dụ:

```text
candidate coordinates
      ↓
CLGeocoder
      ↓
Thanh Xuân, Hà Nội
Cầu Giấy, Hà Nội
Long Biên, Hà Nội
```

Cache kết quả.

Không để geocoding block scanner.

Nếu geocode chậm:

có thể tạm hiện map/coordinate candidate rồi update label sau.

---

# 19. HomeCandidate

Concept:

```swift
struct HomeCandidate: Identifiable {
    let id: UUID

    let coordinate: CLLocationCoordinate2D
    let radiusMeters: Double

    let displayName: String?

    let score: Double

    let distinctYears: Int
    let distinctMonths: Int
}
```

Không expose score trong production UI.

---

# 20. User Confirmed Home

Khi user chọn candidate:

```swift
HomeAnchor {
    source = .userConfirmed
    confidence = 1.0
}
```

Model nên phân biệt:

```swift
enum HomeAnchorSource {
    case inferred
    case userConfirmed
}
```

Nếu persistence hiện có `HomeAnchor`, mở rộng model thay vì tạo hệ Home thứ hai.

---

# 21. User-confirmed Home luôn thắng

Nếu có:

```text
Full Home Detector = location A
User Confirmed = location B
```

Production sử dụng:

```text
B
```

Không tự động overwrite user choice.

Chỉ user mới có thể thay đổi Home đã xác nhận.

---

# 22. Chọn địa điểm khác

Nếu 3 candidate đều sai:

```text
Chọn địa điểm khác...
```

Mở map picker đơn giản.

User:

```text
pan / zoom
↓
tap/select location
↓
Confirm Home
```

Không cần nhập địa chỉ.

Reverse-geocode selected coordinate sau.

Không xây Location Search phức tạp nếu chưa có infrastructure.

---

# 23. Skip Home

Home confirmation không được block onboarding.

Có:

```text
Bỏ qua
```

Nếu user skip:

```text
scan continues
First Memory continues
```

Nizi có thể hỏi lại sau.

Không repeatedly nag trong cùng session.

---

# 24. Scan vẫn chạy khi Home Card mở

Bắt buộc.

Flow:

```text
Scanner actor/task
      ↓
progress stream
      ↓
Memory Journey UI

Home card presented
      ↓
scanner continues
```

Không:

```text
await userHomeSelection()
```

trong scan pipeline.

Home selection là side interaction.

---

# 25. Home có thể cải thiện Event/Trip sau đó

Nếu user xác nhận Home khi scan chưa xong:

store ngay.

Các bước Event/Trip chạy sau có thể sử dụng Home đã xác nhận.

Nếu Event Discovery đã chạy trước Home selection:

không bắt buộc rebuild ngay trong task này.

Có thể sử dụng Home ở lần discovery/update tiếp theo.

Không làm orchestration quá phức tạp.

---

# 26. Memory Journey Cards

Ngoài Home card, sprint này không cần tạo hệ card lớn.

Nhưng architecture Presentation có thể cho phép:

```text
MemoryPreview
ProgressMoment
HomeConfirmation
```

Không xây generic card framework quá mức.

---

# 27. Suggested Journey

Ví dụ production:

```text
Đang tìm lại những kỷ niệm của bạn


2014
12 năm trước

[photo]
[photo] [photo]

8.421 ảnh đã được xem


        ↓


2017
9 năm trước

[favorite hero]
[photo] [photo]

21.632 ảnh đã được xem


        ↓


🏠 Giúp Nizi nhận ra những chuyến đi của bạn

Đâu là nơi bạn gọi là Nhà?

○ Thanh Xuân, Hà Nội
○ Cầu Giấy, Hà Nội
○ Long Biên, Hà Nội

Chọn nơi khác...

[Xác nhận]    Bỏ qua


        ↓

scanner vẫn chạy


2020
6 năm trước

[photo]
[photo] [photo]

53.120 ảnh đã được xem


        ↓


Đang kết nối những khoảnh khắc...

1.739 sự kiện


        ↓


Nizi vừa tìm thấy một kỷ niệm

[MEMORY COVER]

[Xem lại]
```

---

# 28. Không biến scan thành slideshow quá nhanh

Ảnh/năm phải đủ thời gian để user nhìn.

Nhưng Presentation không được làm chậm scanner.

Tách:

```text
scanner progress speed
```

khỏi:

```text
presentation transition speed
```

Nếu scanner xử lý 5 năm trong 1 giây:

UI có thể queue/coalesce state để user nhìn được một số representative years.

Không cần hiển thị mọi year nếu quá nhanh.

Không fake scan state; chỉ coalesce các state thật đã đi qua.

---

# 29. Performance

Memory Journey không được làm scan chậm đáng kể.

Không:

- request full-resolution;
- request thumbnail cho mọi asset;
- reverse-geocode mọi cluster;
- query SwiftData mỗi frame;
- chạy Vision;
- chạy AI;
- giữ nhiều UIImage;
- build Event chỉ để update UI.

Thumbnail request phải có:

- bounded concurrency;
- cancellation;
- small target size;
- opportunistic delivery nếu phù hợp.

---

# 30. Persistence

Persist:

```text
user-confirmed Home
```

và candidate geocode cache nếu infrastructure phù hợp.

Không cần persist scan preview thumbnails.

Không duplicate Photos assets.

---

# 31. Returning User

Nếu đã có:

```text
HomeAnchor.source == userConfirmed
```

không hỏi Home lại.

Nếu scan/index đã hoàn tất:

không show Initial Scan Journey lại.

Nếu scan bị kill giữa chừng:

resume checkpoint hiện có.

Memory Journey resume dựa trên progress thật.

---

# 32. Home thay đổi

Không cần giải quyết multi-home/history trong sprint này.

V1:

```text
Current Home
```

Sau này Settings có thể:

```text
Home
Thanh Xuân, Hà Nội
[Thay đổi]
```

Data model không nên ngăn việc mở rộng multi-home về sau.

---

# 33. Error / Edge Cases

### No GPS

Nếu library chưa có đủ GPS observations:

- không hiện candidate card;
- hoặc Home card chỉ có:
  `Chọn trên bản đồ`.

Không block scan.

### Limited Photos permission

Dùng dữ liệu được phép.

Không coi là error.

### Geocoder unavailable

Candidate vẫn có thể tồn tại.

Cho phép map picker / retry label.

### Candidate appears late

Không sao.

Nếu scan gần hoàn tất mới đủ candidate, card có thể xuất hiện trước Event Discovery hoặc bỏ qua initial journey và hỏi sau.

### User ignores card

Không block.

---

# 34. Diagnostics

Giữ Full Home Detector hiện tại.

Bổ sung DEBUG info cho Fast Candidate nếu cần:

```text
Fast Home Candidates

Candidate A
distinct years: 11
distinct months: 96
sampled days: 420
score: ...

Candidate B
...
```

Production không hiện các số này.

---

# 35. Logging

Local debug logging:

```text
initial_scan_started
scan_year_changed
scan_preview_candidate_added

fast_home_candidate_started
fast_home_candidates_ready
home_card_presented
home_candidate_selected
home_map_selected
home_confirmation_skipped

initial_scan_completed
event_discovery_started
first_memory_ready
```

Không log raw coordinates ra remote analytics.

---

# 36. Acceptance Criteria

## AC-01

Sau Photos permission, scan bắt đầu ngay.

## AC-02

User thấy processed photo count tăng bằng dữ liệu thật.

## AC-03

User thấy year/time period scanner đang đi qua.

## AC-04

Ảnh preview xuất hiện trong lúc scan.

## AC-05

Favorite được ưu tiên nếu có.

## AC-06

Memory Journey UI không làm scan chậm đáng kể.

## AC-07

Fast Home Candidate không cần chờ scan toàn bộ library.

## AC-08

Không chạy Full Home Detector trong production onboarding.

## AC-09

Chỉ top candidates được reverse-geocode.

## AC-10

Home card xuất hiện như một phần của Memory Journey, không phải một blocking onboarding page.

## AC-11

Scanner tiếp tục chạy trong lúc Home card đang mở.

## AC-12

User có thể chọn một candidate.

## AC-13

User có thể chọn Home trên map nếu candidate sai.

## AC-14

User có thể Skip.

## AC-15

User-confirmed Home được persist và không bị inference overwrite.

## AC-16

Returning user đã có confirmed Home không bị hỏi lại.

## AC-17

Sau scan, flow tiếp tục Event Discovery → First Memory như hiện tại.

---

# 37. Không làm trong task này

Không scope creep:

- không cải tiến Event segmentation;
- không tune Event Boundary;
- không phát triển Full Home Detector;
- không multi-home history;
- không Work detection;
- không face recognition;
- không cloud AI;
- không backend;
- không account;
- không upload GPS;
- không reverse-geocode toàn bộ Event;
- không Event location enrichment hàng loạt;
- không Trip UI redesign;
- không Memory Feed;
- không photobook changes.

---

# 38. Các khu vực Claude cần khảo sát trước khi code

Đọc implementation thực tế của:

```text
ContentView
FirstExperienceCoordinator
UserScanProgressView / DiscoveringMemoriesView

ScanPhotoLibraryUseCase
LibraryScanProgress
LibraryScanScope

MemoryIndexStore
SQLiteMemoryIndexStore

LocationIntelligenceEngine
HomeAnchor
Home persistence

PhotoKit thumbnail provider / existing image manager

FirstMemoryView
MemoryViewerView
```

Không tạo duplicate PhotoKit image loader nếu project đã có.

Không tạo scanner thứ hai.

---

# 39. Implementation Order

```text
STEP 1
Expose richer real scan progress:
count + total + current year

STEP 2
Add bounded preview candidate stream

STEP 3
Build Memory Journey presentation

STEP 4
Add Favorite-first preview selection

STEP 5
Implement Fast Home Candidate accumulator
using already-scanned GPS metadata

STEP 6
Expose top 3 candidates when ready

STEP 7
Reverse-geocode only top candidates

STEP 8
Insert Home Confirmation Card into Journey

STEP 9
Persist user-confirmed Home

STEP 10
Add map fallback + Skip

STEP 11
Verify scanner never waits for Home interaction

STEP 12
Run on real large library and profile performance
```

---

# 40. Definition of Done

Test trên real iPhone với library lớn:

```text
1. Fresh install.
2. Grant Photos access.
3. Scan starts automatically.
4. User immediately sees Memory Journey.
5. Photo count visibly increases.
6. Year changes as real scan progresses.
7. Old/favorite thumbnails begin appearing.
8. UI feels alive while scanner continues.
9. After enough GPS samples exist, Nizi offers plausible Home candidates.
10. User selects Home or chooses it on map.
11. Scan never pauses for this interaction.
12. Confirmed Home is saved.
13. Journey continues through remaining years.
14. Event Discovery starts.
15. First Memory appears.
16. Relaunch does not ask Home again.
17. Initial scan performance remains close to baseline.
```

---

# 41. Product Principle

The initial scan is not a technical inconvenience to hide.

It is the first time Nizi walks through years of a person's photo history.

Use that time to create the feeling:

> **“Nizi đang cùng tôi quay lại những năm tháng đã qua.”**

Home confirmation follows the same principle:

> **Nizi proposes. The user confirms.**

Do not spend minutes computing a probabilistic Home when a lightweight inference plus a five-second human confirmation can produce a better answer.
