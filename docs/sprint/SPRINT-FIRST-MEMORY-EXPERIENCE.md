# SPRINT — FIRST MEMORY EXPERIENCE

> **Project:** Nizi  
> **Status:** Proposed  
> **Priority:** P0  
> **Goal:** Biến Nizi từ một tập hợp các engine/diagnostics thành một trải nghiệm người dùng mới hoàn chỉnh: mở app lần đầu → cấp quyền Photos → Nizi tự scan, discover, curate → hiển thị một Memory đáng xem trước khi vào Home.

---

## 1. Bối cảnh

Nizi hiện đã có phần lớn engine cốt lõi:

- Scan toàn bộ thư viện Photos.
- Lưu metadata vào Local Memory Index.
- Chia ảnh thành session.
- Gom session thành Event.
- Chạy Event Discovery.
- Curation ảnh theo Event.
- Người dùng có thể chọn lại ảnh.
- Tạo Album/Photobook từ ảnh đã chọn.
- Album Viewer / Editor đã hoạt động ở mức tương đối hoàn chỉnh.

Tuy nhiên, trải nghiệm hiện tại vẫn mang tính developer-oriented.

Các bước quan trọng như:

- Local Memory Index
- Event Discovery
- kiểm tra Event
- kiểm tra Curation

được phát triển và kiểm chứng rất nhiều thông qua Diagnostics.

Production flow đã có onboarding, nhưng chưa tạo được một khoảnh khắc rõ ràng để user hiểu ngay:

> “Nizi vừa tìm lại một kỷ niệm của mình.”

Đây là vấn đề UX quan trọng nhất cần giải quyết trong sprint này.

---

# 2. Mục tiêu sản phẩm

Mục tiêu của sprint:

> Người dùng mới không cần hiểu Scan, Index, Event Discovery hay Curation.

Sau khi cấp quyền Photos, Nizi phải tự động thực hiện toàn bộ pipeline cần thiết và đưa ra một Memory đáng xem.

Flow mong muốn:

```text
Open Nizi
    ↓
Welcome
    ↓
Photos Permission
    ↓
Discovering Memories
    ↓
Scan + Index
    ↓
Event Discovery
    ↓
Auto Curation
    ↓
First Memory
    ↓
Memory Viewer
    ↓
Home
```

User không cần:

- vào Diagnostics;
- chạy Local Memory Index thủ công;
- bấm Event Discovery;
- mở Event rồi mới kích hoạt curation;
- chọn ảnh trước khi được xem Memory.

---

# 3. Nguyên tắc UX

## 3.1 Memory phải xuất hiện trước khi user phải làm việc

Không dùng flow:

```text
Event
 ↓
Chọn ảnh
 ↓
Memory
```

Dùng:

```text
Event
 ↓
Auto Curation
 ↓
Memory
 ↓
User có thể chỉnh lại sau
```

Nguyên tắc:

> Nizi làm trước, user sửa sau.

Memory đầu tiên là một kết quả gợi ý hoàn chỉnh đủ để xem.

Nó không cần hoàn hảo.

---

## 3.2 Không expose thuật ngữ kỹ thuật

Không hiển thị các thuật ngữ:

- Local Memory Index
- IndexedAsset
- Session
- Event Discovery Engine
- Curation Engine
- Checkpoint
- Rebuild events

trong onboarding production.

Các thuật ngữ này tiếp tục tồn tại trong code và Diagnostics.

Production UI chỉ nên dùng ngôn ngữ như:

- Đang tìm những kỷ niệm của bạn
- Đang xem lại những năm tháng đã qua
- Đang tìm những chuyến đi đáng nhớ
- Đã tìm thấy một kỷ niệm
- Nizi vừa tìm thấy...

---

# 4. Thay đổi onboarding

## 4.1 Flow hiện tại

Hiện tại `ContentView` quản lý:

```swift
checking
helloNizi
scopeSelection
permission
scanning
home
```

Sprint này chuyển về:

```swift
checking
welcome
permission
discovering
firstMemory
home
```

Có thể giữ tên enum hiện tại nếu tránh refactor không cần thiết, nhưng flow UX phải tương đương.

---

## 4.2 Scope Selection

`LibraryScanScope` vẫn giữ nguyên ở Domain.

Tuy nhiên:

> Không yêu cầu user chọn scan scope trong onboarding mặc định.

Default:

```text
Full accessible photo library
```

hoặc scope production mặc định hiện hệ thống đang dùng.

`ScopeSelectionView`:

- không xóa;
- không refactor engine;
- giữ lại để Diagnostics / Settings / Advanced flow sử dụng sau này;
- không xuất hiện trong First User Experience.

Lý do:

User mới không cần đưa ra một quyết định kỹ thuật trước khi hiểu giá trị của app.

---

# 5. FirstExperienceCoordinator

Tạo orchestration layer mới.

Tên đề xuất:

```swift
FirstExperienceCoordinator
```

hoặc:

```swift
FirstMemoryCoordinator
```

Không nhồi orchestration vào SwiftUI View.

Coordinator chịu trách nhiệm điều phối:

```text
ScanPhotoLibraryUseCase
        ↓
DiscoverEventsUseCase
        ↓
Memory Candidate Selection
        ↓
EventPhotoCurationService
        ↓
MemoryBuilder
        ↓
First Memory Ready
```

Coordinator không thay thế các engine hiện có.

Nó chỉ gọi chúng theo đúng flow production.

---

## 5.1 State đề xuất

Ví dụ:

```swift
enum FirstExperienceState {
    case idle
    case requestingPermission
    case scanning
    case discovering
    case curating
    case memoryReady(MemoryCandidate)
    case completed
    case failed(FirstExperienceError)
}
```

Có thể chi tiết hơn nếu cần UI progress.

Không persist enum UI này nếu không cần.

---

# 6. MemoryCandidate

Hiện tại Nizi có:

- IndexedAsset
- PhotoSession
- PhotoEvent
- PhotoCurationGroup
- PhotoCurationItem
- AlbumDraft

Nhưng thiếu một object product-level đại diện cho:

> “Một Memory đã đủ tốt để user xem.”

Tạo model mới:

```swift
struct MemoryCandidate: Identifiable {
    let id: UUID

    let eventID: UUID

    let title: String
    let subtitle: String?

    let dateRange: DateInterval?
    let placeName: String?

    let coverAssetID: String
    let selectedAssetIDs: [String]

    let totalPhotoCount: Int

    let score: Double

    let status: MemoryStatus
}
```

Tên property có thể điều chỉnh theo convention code hiện tại.

---

## 6.1 MemoryStatus

Ví dụ:

```swift
enum MemoryStatus {
    case provisional
    case ready
    case saved
    case dismissed
}
```

Sprint này chỉ bắt buộc:

```text
provisional
ready
```

Không mở rộng quá mức.

---

# 7. MemoryCandidate không phải AlbumDraft

Không reuse `AlbumDraft` để đại diện Memory.

Hai khái niệm khác nhau:

```text
PhotoEvent
    ↓
MemoryCandidate
    ↓
Memory
    ↓
optional
    ↓
AlbumDraft
    ↓
Photobook
```

Memory là trải nghiệm xem lại ký ức.

Album/Photobook là một output sau đó.

Sprint này không yêu cầu thay đổi `AlbumCreation`.

---

# 8. Event → Memory

## 8.1 Current behavior

Hiện tại curation có xu hướng được chạy khi user mở Event Detail lần đầu.

Sprint này chuyển curation cho First Memory thành:

> system-triggered

Flow:

```text
PhotoEvent
   ↓
eligible?
   ↓
score
   ↓
EventPhotoCurationService
   ↓
selected photos
   ↓
cover selection
   ↓
MemoryCandidate
```

User không phải mở Event để kích hoạt bước này.

---

# 9. First Memory Scoring

Không hiển thị Event đầu tiên scanner gặp được.

Cần chọn một Event đủ tốt.

Tạo abstraction:

```swift
protocol MemoryCandidateScoring {
    func score(event: PhotoEvent, ...) -> Double
}
```

Implementation đầu tiên có thể deterministic.

Không cần AI.

---

## 9.1 Yếu tố scoring gợi ý

Score có thể dựa trên dữ liệu hiện có:

### Positive signals

- Event có số ảnh đủ lớn.
- Event kéo dài đủ lâu.
- Event có nhiều session.
- Ảnh trải đều theo timeline.
- Location tương đối nhất quán.
- Có place name rõ.
- Location khác vùng thường xuyên xuất hiện.
- Curation giữ lại được đủ ảnh tốt.
- Có nhiều ảnh landscape / portrait hữu ích.
- Event có cover candidate tốt.

### Negative signals

- Screenshot ratio cao.
- Duplicate / near-duplicate ratio cao.
- Event quá ngắn.
- Event quá ít ảnh.
- Event chủ yếu là ảnh tài liệu.
- Event có location / time inconsistency cao.
- Curation chỉ chọn được rất ít ảnh.
- Event confidence thấp.

Không cần implement tất cả nếu dữ liệu hiện chưa có.

Chỉ sử dụng signal hiện có đáng tin cậy.

---

## 9.2 Threshold

Định nghĩa config:

```swift
firstMemoryMinimumScore
```

Không hard-code rải rác trong UI.

Ví dụ ban đầu:

```text
0...100
First Memory threshold ~ 70–80
```

Con số thật phải tune bằng dữ liệu thực.

---

# 10. Không cần chờ scan hoàn tất toàn bộ mới nghĩ về First Memory

Mục tiêu dài hạn:

```text
scan batch
   ↓
provisional discovery
   ↓
candidate
   ↓
first memory
```

Tuy nhiên cần tránh refactor lớn trong sprint đầu tiên.

Triển khai theo 2 cấp:

---

## Phase A — bắt buộc trong sprint

Giữ `ScanPhotoLibraryUseCase` hiện tại.

Sau khi đủ dữ liệu production để Discover Event:

```text
Scan
 ↓
Discover
 ↓
Score
 ↓
Curate
 ↓
First Memory
```

Hoàn thành end-to-end UX trước.

---

## Phase B — nếu đơn giản và không phá engine

Cho coordinator quan sát scan progress.

Khi Local Memory Index đã có đủ dữ liệu:

```text
run provisional discovery
```

để First Memory xuất hiện trước khi full scan kết thúc.

Phase B không được làm sprint phình to.

Nếu cần refactor sâu `DiscoverEventsUseCase`, để sprint sau.

---

# 11. Discovering Memories Screen

Thay trải nghiệm scan thuần kỹ thuật bằng màn:

```text
DiscoveringMemoriesView
```

hoặc reuse `UserScanProgressView` nhưng redesign presentation.

---

## 11.1 Hero message

Ví dụ:

```text
Nizi đang tìm những kỷ niệm của bạn
```

Secondary message thay đổi theo state:

```text
Đang xem lại những năm tháng đã qua...

Đang kết nối những khoảnh khắc gần nhau...

Đang tìm những chuyến đi đáng nhớ...

Đang chọn những khoảnh khắc nổi bật...
```

Các message chỉ phản ánh state thật.

Không fake progress.

---

## 11.2 Progress

Có thể hiển thị progress bar.

Không cần show:

```text
IndexedAsset 43,228
Checkpoint 149
Batch 52
```

Có thể show nhẹ:

```text
43.000 ảnh đã được xem
```

nếu UX thấy hữu ích.

Không biến màn này thành Diagnostics.

---

# 12. First Memory Ready

Khi có Memory Candidate đủ threshold:

UI phải đổi trạng thái rõ ràng.

Ví dụ:

```text
Nizi vừa tìm thấy một kỷ niệm

[ LARGE COVER ]

Đà Nẵng
12–15 tháng 7, 2023

32 khoảnh khắc

[Xem lại]
```

Đây là First Wow Moment.

Không đưa user trực tiếp về Home trước khi họ có cơ hội xem Memory này.

---

# 13. FirstMemoryView / MemoryViewer

Tạo một Viewer nhẹ.

Không dùng toàn bộ Photobook engine để render First Memory.

Mục tiêu:

> nhanh, đơn giản, cảm xúc.

---

## 13.1 Layout ban đầu

Có thể sử dụng:

- hero full-width image;
- single photo;
- 2-photo row;
- 3-photo group;
- date/location text block.

Chỉ cần khoảng 5–10 composition rule.

Không cần user chọn template.

Không cần page editor.

Không cần drag-drop.

---

## 13.2 Memory Viewer content

Ví dụ:

```text
Cover

Đà Nẵng
Mùa hè 2023

↓

Photo

↓

Photo + Photo

↓

Photo

↓

Photo + Photo + Photo
```

Scroll dọc là lựa chọn phù hợp cho V1.

Không cần mô phỏng photobook trong Memory Viewer.

---

# 14. Actions trong First Memory

Ở cuối hoặc toolbar:

```text
♡ Lưu
Chỉnh ảnh
Tạo album
```

Trong sprint này:

### Bắt buộc

- Xem Memory.
- Vào chỉnh ảnh selection.
- Continue vào Home.

### Optional

- Lưu Memory.
- Tạo Album.

Nếu wiring sang AlbumCreation hiện tại đơn giản thì có thể làm.

Không được để phần này làm chậm First Memory Experience.

---

# 15. Edit Selection

Reuse khả năng curation hiện có.

Khi user chọn:

```text
Chỉnh ảnh
```

mở UI lựa chọn hiện tại hoặc extract phần phù hợp từ `EventDetailView`.

Nguyên tắc:

- ảnh Nizi chọn sẵn = selected;
- user có thể deselect;
- user có thể select thêm;
- manual user selection luôn override algorithm;
- quay lại Memory → layout refresh.

Không tạo một photo picker mới nếu UI hiện tại đã đáp ứng.

---

# 16. Home sau First Memory

Home hiện tại đang thiên về Album.

Sprint này thay hierarchy UX:

```text
HOME

Những kỷ niệm
────────────────

[ HERO MEMORY ]

Nizi vừa tìm thấy
[Memory] [Memory] [Memory]


Album của bạn
[Album] [Album]

Xem tất cả
```

Memory là primary content.

Album là secondary content.

Event không còn là Quick Action nổi bật.

---

# 17. Event vẫn tồn tại

Không xóa:

- EventListView
- EventDetailView
- EventCardView
- DiscoverEventsUseCase
- PhotoEvent
- Event Discovery Diagnostics

Event tiếp tục là domain + management layer.

Có thể giữ đường vào Event trong:

- More
- Advanced
- Developer
- Diagnostics
- secondary navigation

Không coi Event List là trải nghiệm chính của user.

---

# 18. Diagnostics

Giữ nguyên toàn bộ Diagnostics.

Không xóa:

- PhotoLibraryDiagnosticsView
- LibraryIndexScanView
- EventDiscoveryDebugListView
- PhotoLocationDiagnosticsView
- RealAlbumPhotoDiagnosticsView
- Album Layout diagnostics
- Photo Editor diagnostics

Diagnostics vẫn cần cho:

- tune clustering;
- tune thresholds;
- inspect Event;
- inspect curation;
- debug PhotoKit;
- inspect Local Memory Index.

Nguyên tắc:

> Production flow tự chạy engine. Diagnostics vẫn cho developer quan sát engine.

---

# 19. Background / continuation behavior

Nếu First Memory xuất hiện trước khi scan toàn thư viện hoàn tất:

```text
user xem Memory
      +
scanner tiếp tục
```

Nếu iOS không cho background execution đầy đủ:

- không giả vờ chạy background;
- pause/resume bằng checkpoint hiện có;
- khi app active lại, coordinator tiếp tục.

Không thay đổi kiến trúc scan/resume hiện tại nếu không cần.

---

# 20. Persistence

Sprint này không cần backend.

Tất cả giữ local.

Persist tối thiểu:

```text
MemoryCandidate
event association
selected asset IDs
cover asset ID
status
score
createdAt
```

Nếu có thể derive lại một field dễ dàng, không persist thừa.

Không duplicate ảnh.

Chỉ lưu reference tới Photos asset.

---

# 21. First Launch

Flow acceptance:

```text
Fresh install
 ↓
Welcome
 ↓
Permission
 ↓
Discovering
 ↓
Memory Ready
 ↓
Memory Viewer
 ↓
Home
```

User không phải:

```text
Diagnostics
Local Memory Index
Event Discovery Debug
Event List
```

để đạt tới Memory.

---

# 22. Returning User

Nếu Local Memory Index đã tồn tại:

Không chạy onboarding lại.

Nếu đã có Memory:

```text
Open App
 ↓
Home
```

Nếu Index có nhưng chưa có Memory Candidate:

```text
Open App
 ↓
auto discover / curate
 ↓
Memory
```

Không ép scan full lại nếu checkpoint/index còn valid.

---

# 23. Empty / weak library cases

Không phải mọi library đều tìm được Event mạnh.

Cần graceful fallback.

Nếu scan/discovery hoàn tất nhưng không có candidate đạt threshold:

```text
Nizi đã xem qua thư viện của bạn.

Chưa tìm thấy một kỷ niệm đủ rõ để tạo tự động.

[Xem các sự kiện]
```

Hoặc:

```text
Hãy tiếp tục chụp ảnh.
Nizi sẽ tìm lại những kỷ niệm cho bạn sau.
```

Không tạo Memory rác chỉ để hoàn tất onboarding.

---

# 24. Error states

Phải xử lý tối thiểu:

### Permission denied

```text
Nizi cần quyền truy cập Photos để tìm những kỷ niệm của bạn.

[Mở Settings]
```

### Limited Photos access

Nizi hoạt động trên tập ảnh user cho phép.

Không coi Limited là error.

### Scan failure

Hiển thị retry.

Không xóa index đã scan thành công trước đó.

### Event discovery failure

Retry discovery.

Không bắt scan lại toàn bộ.

### Curation failure

Có thể fallback chọn cover + một tập ảnh đơn giản nếu an toàn.

Không crash First Experience.

---

# 25. Logging

Dùng `NiziLogger.discovery`.

Log các milestone:

```text
first_experience_started
photo_permission_granted
photo_scan_started
photo_scan_progress
photo_scan_completed
event_discovery_started
event_discovery_completed
memory_candidate_scored
first_memory_selected
first_memory_ready
first_memory_opened
first_memory_selection_edited
first_experience_completed
```

Không log raw photo content.

Không log sensitive EXIF ngoài nhu cầu debug local.

---

# 26. Metrics nội bộ cần quan sát

Chưa cần analytics backend.

Có thể log local trong DEBUG.

Quan trọng nhất:

```text
Time To First Memory
```

Tính:

```text
permission granted
→
first_memory_ready
```

Các metric phụ:

```text
scan duration
number of indexed assets
number of discovered events
number of eligible memory candidates
winning candidate score
curated photo count
first memory opened?
selection edited?
```

---

# 27. Acceptance Criteria

Sprint chỉ được coi là hoàn thành khi đạt các điều kiện sau.

## AC-01 Fresh install

Given app mới / local data bị xóa

When user mở Nizi

Then user đi qua:

```text
Welcome → Permission → Discovering
```

không qua Diagnostics.

---

## AC-02 No Scope Selection

Fresh user không bị yêu cầu chọn scan scope.

---

## AC-03 Automatic pipeline

Sau khi user cấp quyền:

```text
Scan
Event Discovery
Scoring
Curation
Memory Build
```

đều chạy tự động.

---

## AC-04 First Memory

Nếu có candidate đạt threshold:

User nhìn thấy:

```text
First Memory Ready
```

trước Home.

---

## AC-05 No manual Event prerequisite

User không cần mở `EventListView` hoặc `EventDetailView` để tạo Memory đầu tiên.

---

## AC-06 Auto selection

Memory xuất hiện với ảnh đã được Nizi chọn sẵn.

---

## AC-07 Manual override

User có thể chỉnh selection.

Manual selection tiếp tục thắng algorithm.

---

## AC-08 Home hierarchy

Sau First Memory:

- Memory là primary section;
- Album là secondary;
- Event không phải CTA chính.

---

## AC-09 Diagnostics preserved

Toàn bộ Diagnostics hiện tại vẫn hoạt động trong DEBUG.

---

## AC-10 No backend

Sprint không yêu cầu:

- account;
- server;
- upload original;
- cloud DB;
- payment.

---

# 28. QA Scenarios

Test ít nhất các case:

### Scenario A — Library lớn

```text
50k–100k assets
```

Kiểm tra:

- app không freeze;
- scan progress update;
- Memory eventually appears;
- app không giữ full-resolution ảnh hàng loạt trong RAM.

---

### Scenario B — Library nhỏ

```text
< 500 assets
```

Nếu có Event tốt:

Memory vẫn xuất hiện.

---

### Scenario C — Không có Event tốt

Không tạo Memory sai.

Show fallback.

---

### Scenario D — Limited permission

App chỉ xử lý assets được phép.

---

### Scenario E — Kill app khi scan

Relaunch:

```text
resume checkpoint
```

Không scan lại từ đầu.

---

### Scenario F — Kill app sau Event Discovery

Relaunch không duplicate Event / Memory Candidate.

---

### Scenario G — User chỉnh ảnh

Memory refresh đúng selection mới.

---

### Scenario H — User không chỉnh gì

Memory hoàn toàn dùng được ngay.

---

# 29. Không làm trong Sprint này

Không scope creep.

Explicitly out of scope:

- Backend.
- Login/account.
- Cloud sync.
- Subscription.
- Payment.
- Print order.
- CMS production.
- Export 4000×4000.
- PDF production.
- AI title generation qua cloud.
- Face recognition mới.
- People timeline.
- On This Day.
- Multi-event thematic Memory.
- Home redesign toàn diện ngoài phần cần cho Memory.
- Rebuild AlbumCreation.
- Rebuild PhotoEditor.
- New Album template system.
- Social features.
- Sharing network.
- Android.
- Web app.

---

# 30. File / component dự kiến ảnh hưởng

Claude cần khảo sát code thực tế trước khi sửa.

Các vùng dự kiến:

```text
Nizi/ContentView.swift

Nizi/Features/MemoryDiscovery/
    Domain/
        MemoryCandidate.swift
        MemoryStatus.swift
        MemoryCandidateScore.swift        // nếu cần

    Application/
        FirstExperienceCoordinator.swift
        MemoryCandidateScoring.swift
        MemoryBuilder.swift

    Presentation/
        UserScanProgressView.swift
        DiscoveringMemoriesView.swift      // nếu tách view mới
        FirstMemoryView.swift
        MemoryViewerView.swift
        HomeView.swift
```

Có thể reuse:

```text
ScanPhotoLibraryUseCase
DiscoverEventsUseCase
EventPhotoCurationService
EventDetail selection UI
ProductionAlbumSlotPhotoProvider / PhotoKit provider
```

Không tạo duplicate service nếu functionality đã tồn tại.

---

# 31. Quy tắc triển khai cho Claude Code

Trước khi code:

1. Đọc `PROJECT-SURVEY.md`.
2. Khảo sát implementation thật của:
   - `ContentView`
   - `UserScanProgressView`
   - `ScanPhotoLibraryUseCase`
   - `DiscoverEventsUseCase`
   - `EventPhotoCurationService`
   - `EventDetailView`
   - `HomeView`
3. Xác định phần nào reuse được.
4. Không refactor engine chỉ để đổi tên.
5. Không phá Diagnostics.
6. Không thay persistence model hàng loạt nếu chưa cần.
7. Không viết một hệ thống Memory phức tạp vượt scope sprint.

---

# 32. Definition of Done

Sprint hoàn tất khi developer có thể thực hiện đúng test sau:

```text
1. Delete Nizi local app data / fresh install.
2. Run app on real iPhone.
3. Tap through Welcome.
4. Grant Photos permission.
5. Do nothing else.
6. Nizi scans/indexes automatically.
7. Nizi discovers Events automatically.
8. Nizi chooses an eligible Event automatically.
9. Nizi curates photos automatically.
10. A Memory cover appears.
11. Tap "Xem lại".
12. Memory can be viewed immediately.
13. User may optionally edit selected photos.
14. Continue to Home.
15. No Diagnostics screen was used.
```

Nếu bước 10 không xảy ra dù library có Event đủ tốt, Sprint chưa hoàn thành.

---

# 33. Product Principle sau Sprint

Sau sprint này, mọi quyết định UX tiếp theo của Memory Discovery nên ưu tiên nguyên tắc:

> **Nizi không yêu cầu người dùng tổ chức ảnh trước.  
> Nizi tự tìm một thứ đáng xem, rồi để người dùng sửa nếu muốn.**

Và KPI kỹ thuật/UX quan trọng nhất ở giai đoạn này:

> **Time to First Meaningful Memory**

Không tối ưu cho:

- số Event tạo được;
- số IndexedAsset;
- số Album;
- số template.

Tối ưu cho:

> User mở Nizi và nhanh chóng gặp một kỷ niệm khiến họ muốn dừng lại xem.
