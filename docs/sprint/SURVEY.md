
# SURVEY — EVENT → MEMORY PROMOTION MODEL

## Mục tiêu khảo sát

KHÔNG sửa code trong task này.

Tôi đang thay đổi product model của Nizi như sau:

### Event

Event là toàn bộ những sự kiện Nizi tự phát hiện từ Photo Library.

Ví dụ hiện có khoảng hàng nghìn Event.

### Memory

Memory không còn là một bước user phải chủ động "Create".

Một Event có thể trở thành Memory theo 2 cách:

1. **User Love**
   - User bấm ♥ trên Event.
   - Event đó lập tức trở thành Memory.

2. **Nizi Auto Promote**
   - Nizi đánh giá Event đủ đáng nhớ.
   - Nizi tự tạo Memory luôn.
   - Không cần user confirm trước.
   - User có thể mở Memory và chỉnh lại ảnh sau.

Flow sản phẩm mong muốn:

```text
Photo Library
      ↓
    Events
      │
      ├── User ♥
      │      ↓
      │    Memory
      │
      └── Nizi Memory Score
             ↓
        score đủ cao
             ↓
           Memory
````

Không có trạng thái UI bắt buộc kiểu:

```text
Suggested Memory
→ user approve
→ Memory
```

Nếu Nizi đề xuất thì nó đã là Memory.

User có thể:

```text
xem
chỉnh ảnh
bỏ Memory
love/unlove
tạo Album
```

sau đó.

---

# 1. Những yếu tố dự kiến để Nizi tự promote Event thành Memory

Chưa implement scoring trong survey.

Chỉ khảo sát architecture để chuẩn bị.

Các signal dự kiến:

```text
- chuyến đi kéo dài khoảng 2–4 ngày hoặc nhiều ngày có cohesion tốt;
- Event ở xa Home;
- Trip trong nước;
- Trip nước ngoài;
- Event có nhiều Favorite photos;
- Favorite ratio cao;
- Event có nhiều ảnh đủ chất lượng;
- Event quality / cohesion cao;
- Event có location/travel context rõ.
```

Không dùng photo count một mình để quyết định.

---

# 2. Cần khảo sát toàn bộ Memory implementation hiện tại

Tìm và mô tả chính xác:

```text
MemoryCandidate
MDMemoryCandidate
MemoryStatus

MemoryBuilder

MemoryCandidateRepository
SwiftDataMemoryDiscoveryStore.save(memory)
fetchLatest()
các fetch Memory khác nếu có

FirstExperienceCoordinator

FirstMemoryView
MemoryViewerView

HomeView phần Memory

EventPhotoCurationService
PhotoCurationGroup
PhotoCurationItem
EventCurationResult
```

Grep toàn repo tất cả chỗ:

```text
MemoryCandidate(
MemoryBuilder(
store.save(
fetchLatest(
MemoryStatus
MDMemoryCandidate
```

Cho biết call site cụ thể.

---

# 3. Memory hiện tại thực sự là gì?

Trả lời rõ:

### A.

`MemoryCandidate` hiện là:

* một temporary candidate?
* một persisted final Memory?
* hay đang đóng cả hai vai trò?

### B.

`MemoryStatus` hiện có những state nào?

State nào thực sự được ghi trong code?

### C.

Memory sau khi First Experience tạo ra có được coi là final object không?

### D.

Có màn Memory List / Memory Feed thật chưa?

Hay hiện chỉ có:

```text
latestMemory
```

?

---

# 4. Source identity

Đây là phần quan trọng nhất.

Khảo sát xem Memory hiện tại có giữ relationship ổn định về nguồn không.

Ví dụ:

```text
Memory
→ source Event ID
```

Có field nào tương đương:

```swift
eventID
sourceEventID
sourceID
```

không?

Nếu có:

* có unique constraint không?
* repository có query Memory theo Event ID không?

Nếu không:

* nói rõ hiện Memory identity đang dựa vào gì.

---

# 5. Duplicate risk

Kiểm tra trường hợp:

```text
Event #100
↓
được FirstExperienceCoordinator tạo thành Memory
```

Sau này:

```text
Auto Memory Promotion
```

gặp lại Event #100.

Hệ thống hiện tại sẽ:

A. update Memory cũ?

hay:

B. tạo một Memory mới?

Tương tự:

```text
Event #100
↓
user ♥
```

sau khi Auto Promotion đã tạo Memory.

Có nguy cơ tạo Memory thứ hai không?

Đưa ra bằng chứng từ code.

---

# 6. UUID behavior

Khảo sát lại:

```text
MemoryBuilder.build()
MemoryBuilder.buildFallback()
```

Memory ID được tạo như thế nào?

Nếu vẫn:

```swift
UUID()
```

mỗi lần build:

hãy giải thích tác động với mô hình mới.

Không sửa trong survey.

---

# 7. Persistence behavior

Khảo sát `save()`.

Trả lời:

```text
save(memory)
```

upsert dựa vào:

* memory ID?
* source Event ID?
* field khác?

Nếu upsert theo memory UUID nhưng builder luôn tạo UUID mới:

ghi rõ đây có phải duplicate risk không.

---

# 8. Curation relationship

Hiện First Memory:

```text
Event
↓
EventPhotoCurationService
↓
MemoryBuilder
↓
Memory
```

Khảo sát:

### A.

Curation result được persist theo Event ID hay Memory ID?

### B.

Nếu Event đã từng curate:

lần sau tạo Memory có reuse selection không?

### C.

Manual selection của user hiện persist ở đâu?

### D.

Nếu Memory tự được tạo trước khi user chỉnh:

sau đó user chỉnh selection từ Memory thì cần sửa object nào?

### E.

Có thể reuse `EventDetailView` selection UI không?

---

# 9. Event Love hiện đã tồn tại chưa?

Search toàn repo:

```text
isLoved
favorite event
liked event
heart
love
saved event
```

Cho biết:

* Event model đã có flag tương tự chưa?
* Event status hiện có những gì?
* có UI heart nào hiện hữu không?
* có repository method persist trạng thái user-selection không?

Không implement.

---

# 10. Event status hiện tại

Khảo sát:

```swift
PhotoEventStatus
```

Đặc biệt:

```text
accepted
convertedToAlbum
```

Báo cáo trước từng nói hai status này được khai báo nhưng chưa được ghi.

Xác nhận trạng thái code HIỆN TẠI.

Có nên reuse status cho Memory hay không?

Chỉ phân tích, chưa đề xuất migration code.

---

# 11. Event rebuild risk

Event Discovery hiện có behavior rebuild Event.

Khảo sát lại:

```text
replaceRebuildableEvents()
```

Nếu Event chưa committed:

```text
delete old
insert new
```

thì Memory tham chiếu Event ID có ổn định không?

Đây là câu hỏi cực kỳ quan trọng.

Kiểm tra:

* Event ID có deterministic không?
* cùng Event sau rebuild có cùng ID không?
* hay Event mới nhận UUID mới?

Nếu Event ID không ổn định:

Memory → Event relationship sẽ ra sao sau rediscovery?

User ♥ Event rồi rebuild thì có mất link không?

Phải trả lời bằng code.

---

# 12. Auto Promotion có ảnh hưởng Event rebuild không?

Mô hình mới:

```text
Event
↓
auto promote
↓
Memory
```

Nếu Event đã thành Memory:

Event có cần được coi là committed để không bị delete khi rebuild không?

Khảo sát current repository behavior và giải thích.

Không sửa.

---

# 13. Memory delete / dismiss

Tìm xem hiện có:

```text
delete memory
dismiss memory
remove memory
```

hay chưa.

Mô hình mới cần phân biệt:

### User không muốn Memory này nữa

Nếu Nizi auto-promote lại trong lần discovery sau thì sao?

Cần biết architecture hiện có hỗ trợ trạng thái kiểu:

```text
dismissed
```

hay chưa.

Chỉ khảo sát.

---

# 14. User Love vs Auto Promotion

Khảo sát data model hiện tại xem có chỗ lưu được provenance không.

Tương lai Memory có thể cần:

```swift
enum MemoryOrigin {
    case firstExperience
    case autoPromoted
    case userLoved
}
```

KHÔNG implement.

Chỉ cho biết:

* hiện có field nào tương đương không;
* thêm field này sẽ ảnh hưởng những model/repository nào.

---

# 15. User Love sau Auto Promotion

Product behavior mong muốn:

```text
Auto Memory
↓
user ♥
```

Không tạo Memory mới.

Chỉ có thể tăng trạng thái user significance.

Khảo sát architecture hiện tại có hỗ trợ update một Memory đã có không.

---

# Kết quả khảo sát — 2026-07-31

Phạm vi: chỉ đọc mã nguồn, không thay đổi implementation.

## 1. Bản đồ implementation và call site

| Thành phần | Vai trò hiện tại | Call site / persistence |
| --- | --- | --- |
| `MemoryCandidate` | Domain object của một Memory đã được chọn ảnh | `MemoryBuilder.build` và `buildFallback` là hai nơi duy nhất khởi tạo production. |
| `MDMemoryCandidate` | SwiftData row, giữ các trường materialized của `MemoryCandidate` | `SwiftDataMemoryDiscoveryStore.save` insert/update row. |
| `MemoryStatus` | Lifecycle enum: `provisional`, `ready`, `saved`, `dismissed` | Chỉ `MemoryBuilder` ghi `.ready`. |
| `MemoryBuilder` | Tạo Memory từ Event + curation, hoặc fallback Event | Được `FirstExperienceCoordinator` inject và gọi tại `curateAndBuild` / fallback. |
| `MemoryCandidateRepository` | `save`, `fetchLatest`, `updateSelection` | Chỉ `SwiftDataMemoryDiscoveryStore` implement. |
| `FirstExperienceCoordinator` | Scan → discover → score → curate → build → save một Memory đầu tiên | `UserScanProgressView` tạo coordinator và gọi `run`. |
| `FirstMemoryView` | Màn announcement onboarding, không phải feed | `ContentView` stage `.firstMemory`. |
| `MemoryViewerView` | Viewer của đúng một `MemoryCandidate` | `ContentView` stage `.memoryViewer`; Home mở candidate từ `fetchLatest`. |
| `HomeView` Memory section | Chỉ tải và hiển thị `latestMemory` | `loadMemory` gọi `store.fetchLatest()`. |
| `EventPhotoCurationService` | Tạo/reuse curation cho đúng một Event | `FirstExperienceCoordinator` và `EventDetailView`. |
| `EventCurationResult` / `PhotoCurationGroup` / `PhotoCurationItem` | Curation persist theo Event, gồm group và từng ảnh | `MDEventCurationResult`, `MDPhotoCurationGroup`, `MDPhotoCurationItem`; repository query bằng `eventCandidateID`. |

Grep xác nhận các production call site sau: `MemoryCandidate(` chỉ trong `MemoryBuilder`; `MemoryBuilder(` chỉ tại default dependency của `FirstExperienceCoordinator`; `store.save(memory)` và `store.save(fallback)` chỉ trong coordinator; `fetchLatest()` chỉ trong `ContentView` và `HomeView`. Không có fetch-all, fetch-by-event, delete, hay dismiss Memory.

## 2. Memory hiện thực sự là gì?

`MemoryCandidate` đang đóng hai vai trò. Tên và comment nói đây là “candidate” cho First Memory Experience, nhưng sau `store.save` nó là một SwiftData object được mở lại từ Home và có thể cập nhật selection. Vì vậy về hành vi hiện tại nó là persisted Memory, không phải temporary candidate thuần túy; architecture lại vẫn mang giả định “một row là đủ”.

`MemoryStatus` có bốn state: `provisional`, `ready`, `saved`, `dismissed`. Cả `build` và `buildFallback` đều luôn ghi `.ready`; không tìm thấy code nào ghi ba state còn lại. Sau First Experience, object được persist và `ContentView` dùng việc tồn tại của `fetchLatest()` để bỏ qua onboarding ở lần mở app sau, nên nó đang được coi là final object về mặt flow.

Chưa có Memory List / Feed. `fetchLatest()` sort `createdAt` giảm dần, giới hạn 1; Home cũng chỉ giữ `latestMemory`.

## 3. Source identity và duplicate risk

Memory có `eventID: UUID` và `MDMemoryCandidate.eventID`, nhưng field này không unique. Không có `fetchMemory(eventID:)`, không có unique constraint theo Event, và `save` query duy nhất theo `candidateID`.

`MemoryBuilder.build` và `buildFallback` đều gọi `UUID()` cho `MemoryCandidate.id`. Vì thế nếu cùng một Event được build lại, `save` sẽ không thấy candidate ID cũ và sẽ insert một row mới. Với model Auto Promotion hoặc User Love, đây là duplicate risk trực tiếp: auto-promote Event #100 rồi build/love lại Event #100 sẽ tạo Memory thứ hai, không update Memory cũ. Hiện flow onboarding thường tránh lặp vì `ContentView` chỉ chạy discovery lại khi `fetchLatest()` là `nil`; đó không phải deduplication ở repository và không bảo vệ flow mới.

## 4. UUID và persistence behavior

`save(memory)` là upsert theo `MemoryCandidate.id` / `MDMemoryCandidate.candidateID` (`@Attribute(.unique)`), không theo `eventID`. Khi ID builder luôn mới, “upsert” không có hiệu lực để tránh duplicate giữa các lần build.

`updateSelection(id:selectedAssetIDs:)` cho thấy repository có thể update một Memory đã biết ID: cập nhật danh sách ảnh, total count và `updatedAt`. Nó không hỗ trợ update theo source Event, và không có method đổi status/origin hay delete/dismiss.

## 5. Curation relationship và chỉnh ảnh

Curation có identity ổn định theo Event ở mức hiện tại: `EventCurationResult.id == photoEventID`; `MDEventCurationResult.eventCandidateID` là unique; group/item cũng mang `eventCandidateID`. `EventPhotoCurationService` reuse kết quả cũ nếu cùng Event ID, status `.completed`, cùng algorithm version và cùng số ảnh nguồn.

Manual selection được persist trên `MDPhotoCurationItem.isSelected` và `selectionSource` (`userAdded` / `userRemoved`), qua `updateItemSelection`. Khi chỉnh Memory, `MemorySelectionEditView` tải curation bằng `candidate.eventID`, ghi lựa chọn item vào curation, rồi gọi `updateSelection` cho Memory. Như vậy selection cuối cùng hiện nằm ở cả curation của Event và snapshot `selectedAssetIDs` của Memory.

Nếu auto-created Memory được chỉnh, object cần update là Memory row (selection snapshot) và curation item của source Event như UI hiện tại đang làm. Có thể reuse logic/repository curation của `EventDetailView`, nhưng không thể tái sử dụng trực tiếp toàn bộ UI: `EventDetailView` gắn với navigation, delete Event và create Album; các selection view hiện là private, tách riêng cho Event và Memory.

## 6. Event Love và Event status

Không có `isLoved`, liked/favorite/saved Event, repository method hoặc Event UI heart. Các icon tim hiện có trong `EventDetailView` là chọn **ảnh** trong curation (`PhotoCurationItem.isSelected`), không phải Love Event. Favorite hiện chỉ là metadata của ảnh (`IndexedAsset.isFavorite`) dùng cho discovery/scoring.

`PhotoEventStatus` gồm `new`, `viewed`, `accepted`, `dismissed`, `snoozed`, `merged`, `convertedToAlbum`. Code discovery chỉ tạo `.new`; search không thấy production code ghi `accepted`, `convertedToAlbum`, `viewed`, `dismissed`, `snoozed` hay `merged`. Do đó không nên coi các status hiện hữu là dữ liệu đáng tin hay reuse ngay cho Memory: chúng là lifecycle của Event, không mang origin/provenance của Memory.

## 7. Event rebuild: rủi ro đứt source identity

`EventDiscoveryEngine` tạo mỗi `PhotoEvent` bằng `id: UUID()`. ID không deterministic. `DiscoverEventsUseCase.execute` luôn gọi `replaceRebuildableEvents`; store sẽ xóa mọi Event không có status `accepted` hoặc `convertedToAlbum`, rồi insert Event freshly discovered. Vì production hiện chỉ tạo `.new`, Event thông thường sẽ bị xóa và thay bằng ID mới trong lần rediscovery.

Vì vậy một Memory đang giữ `eventID` của Event cũ sẽ thành orphan sau rebuild. Curation cũng dựa vào old Event ID và `replaceRebuildableEvents` không xóa/relocate curation rows, nên có thể còn stale rows nhưng Event source đã không còn. User Love trên Event cũng sẽ mất link với event mới nếu chỉ lưu bằng Event UUID hiện tại.

Auto Promotion không tự bảo vệ Event khỏi rebuild: repository chỉ bảo vệ `.accepted` và `.convertedToAlbum`; promotion hiện không cập nhật Event status. Nếu chọn cách bảo vệ Event đã thành Memory bằng status committed thì phải xử lý trường hợp discovery tạo lại cùng nội dung với ID khác; nếu không, Memory cần một source identity bền vững/deterministic hoặc cơ chế remap. Đây là blocker kiến trúc quan trọng trước khi thêm Auto Promotion/Love.

## 8. Delete/dismiss và provenance

Không có delete Memory, dismiss Memory hoặc remove Memory trong `MemoryCandidateRepository`, `SwiftDataMemoryDiscoveryStore`, `MemoryViewerView` hay Home. Dù enum có `.dismissed`, state này chưa có UI/API/persistence transition. Vì vậy hiện không có suppression record để ngăn auto-promotion lại sau khi user bỏ Memory.

Không có field provenance tương đương `MemoryOrigin`. `MemoryCandidate` / `MDMemoryCandidate` chỉ có score, status, dates, source Event ID và asset selection. Để có `firstExperience` / `autoPromoted` / `userLoved`, cả domain model, SwiftData schema/mapping, builder/promotion writer, repository update/query và UI/filter hiển thị (nếu cần) đều sẽ bị ảnh hưởng. User Love sau Auto Promotion có thể update Memory đã có về mặt kỹ thuật nếu caller biết `candidateID`, nhưng architecture hiện không thể tìm Memory bằng Event/source identity, cũng chưa có field lưu “user significance”; vì vậy chưa hỗ trợ đúng product behavior đó.

## 9. Kết luận kiến trúc

Current implementation phù hợp cho “một First Memory” onboarding, không phù hợp an toàn cho nhiều Memory được promote liên tục. Trước khi implement scoring, cần giải quyết ba điểm: source identity bền qua rebuild, uniqueness/query theo source, và lifecycle/provenance (đặc biệt dismissed + userLoved). Nếu không, Auto Promotion và Love có thể tạo duplicate Memory, làm orphan Memory sau discovery, và không thể suppress một Memory user đã bỏ.

---

# 16. User ♥ Event chưa có Memory

Behavior mong muốn:

```text
Event
↓ ♥
Curation nếu cần
↓
Memory created immediately
```

"Immediately" ở đây nghĩa là:

* UI không cần approval step;
* có thể dùng auto-selected photos;
* curation có thể chạy async nếu cần;
* Memory xuất hiện sau khi build xong.

Khảo sát xem pipeline hiện tại có reusable để thực hiện điều này không.

---

# 17. Auto Memory Promotion

Behavior mong muốn:

```text
Event Discovery completed
↓
Memory scoring
↓
qualified Events
↓
curation
↓
MemoryBuilder
↓
persist Memory
```

Nhưng không được làm initial UX chậm quá mức.

Khảo sát:

* EventPhotoCurationService tốn bao nhiêu loại operation?
* có load pixel/thumbnail không?
* có Vision analysis không?
* có thể curate hàng chục/hàng trăm Event sau discovery không?
* phần nào có thể lazy/background?

Chỉ phân tích từ code.

Không benchmark nếu không có runtime.

---

# 18. Number of Memories

Khảo sát repository hiện tại có support:

```text
fetch all Memories
fetch by year
fetch by source
sort by date
```

không.

Nếu chỉ có:

```text
fetchLatest()
```

ghi rõ.

---

# 19. Home architecture

Khảo sát Home hiện tại:

* chỉ render First Memory?
* có section Memories chưa?
* data source là single object hay array?
* muốn có nhiều auto Memories sẽ phải thay đổi những gì?

Không redesign Home trong task này.

---

# 20. Trip as Memory source

Smart Event & Travel sprint đã có `PhotoTrip`.

Khảo sát:

```text
PhotoTrip
Trip repository
TravelClassification
```

và trả lời:

Memory hiện tại có thể source từ Trip không?

Hay `MemoryBuilder` chỉ nhận `PhotoEvent`?

Không implement Trip Memory.

Chỉ đánh giá mức độ coupling.

---

# 21. Đưa ra Conflict Matrix

Cuối báo cáo hãy có bảng:

| New behavior                  | Current architecture | Conflict? | Why |
| ----------------------------- | -------------------- | --------- | --- |
| User ♥ Event → Memory         | ...                  | Yes/No    | ... |
| Auto Event → Memory           | ...                  | Yes/No    | ... |
| Same Event promoted twice     | ...                  | ...       | ... |
| First Memory + Auto Promotion | ...                  | ...       | ... |
| Event rebuild after Memory    | ...                  | ...       | ... |
| User removes auto Memory      | ...                  | ...       | ... |
| Multiple Memories in Home     | ...                  | ...       | ... |
| Trip → Memory                 | ...                  | ...       | ... |

---

# 22. Kết luận bắt buộc

Không code.

Đưa ra:

## A. Những gì có thể reuse nguyên trạng

## B. Những gì cần sửa trước khi Auto Promotion được bật

## C. Những risk có thể gây duplicate/orphan Memory

## D. Event identity có đủ ổn định để làm Memory source hay không

## E. Curation có đủ reusable cho:

* First Memory
* User Love
* Auto Promotion

## F. Có nên giữ `MemoryCandidate` hay đổi semantics thành final `Memory`

Chỉ đề xuất dựa trên code hiện tại.

---

# 23. Không làm trong Survey

Không:

* sửa code;
* migration;
* tạo Memory Feed;
* thêm heart UI;
* thêm scoring;
* đổi Event Discovery;
* sửa SwiftData;
* refactor MemoryCandidate;
* thêm Trip Memory.

Task này chỉ nhằm xác định chính xác:

> Kiến trúc Memory hiện tại có xung đột gì với mô hình:
>
> **Nizi tự thấy đáng nhớ → tạo Memory luôn**
>
> và
>
> **User ♥ Event → tạo Memory luôn**

---

## 10. Pipeline cho User Love và Auto Promotion

Pipeline hiện tại có thể reuse một phần cho User Love: đã có `EventPhotoCurationService.curate(event:)`, cache curation hợp lệ theo Event ID, `MemoryBuilder.build`, và `store.save`. Tuy nhiên không có entry point UI/repository cho Love, không có lookup Memory theo Event để idempotent, và fallback/candidate selection hiện chỉ nằm trong `FirstExperienceCoordinator`.

Auto Promotion có thể đi theo cùng pipeline sau khi discovery hoàn tất, nhưng curation không rẻ. `EventPhotoCurationService` lấy assets/sessions, sau đó `VisionEventPhotoAnalyzer` tải thumbnail 256×256 cho từng ảnh và chạy Vision face landmarks, image feature print, document segmentation, pixel sharpness/exposure. Analyzer giới hạn tối đa hai phân tích đồng thời và xử lý từng session; không có benchmark trong repo. Vì vậy curate hàng chục/hàng trăm Event ngay trong critical path sau discovery có nguy cơ kéo dài initial UX. API là `async` và có progress callback, nên về mặt cấu trúc có thể schedule lazy/background; không nên suy luận rằng hiện tại đã có job queue, cancellation hoặc batch promotion vì chưa có.

## 11. Số lượng Memories và Home

Repository không hỗ trợ fetch-all, fetch-by-year, fetch-by-source hay sort Memory theo event date. Chỉ có `fetchLatest()` (sort `createdAt` descending, limit 1) và update selection theo Memory ID.

Home có một `MemoryHeroCard` duy nhất, data source là `@State private var latestMemory: MemoryCandidate?`; không có section/list Memories. Nhiều auto Memories sẽ cần repository query collection + sorting/filtering, state array và UI section/feed. Đây là khảo sát, không phải đề xuất redesign UI.

## 12. Trip as a Memory source

`PhotoTrip` tồn tại, gồm `eventIDs`, date range, place/country, `TravelClassification` (`local`, `dayTrip`, `domesticTrip`, `internationalTrip`, `unknown`) và `TravelContext`. `TravelClassificationService` reverse-geocode tối đa một representative coordinate mỗi trip cộng một Home coordinate, có cache. Nhưng `PhotoTrip` có `UUID()` mới và `PhotoTripRepository.replaceRebuildableTrips` xóa rồi tạo lại toàn bộ trips ở mỗi rebuild.

Memory hiện không thể source trực tiếp từ Trip: `MemoryBuilder` chỉ nhận `PhotoEvent`; Memory schema chỉ có `eventID`; curation service cũng chỉ nhận Event/sessions/assets của Event. Trip chứa các Event IDs nhưng không có curation aggregate hay asset list. Coupling hiện là rõ ràng và sẽ cần một source abstraction hoặc builder riêng nếu sau này hỗ trợ Trip Memory.

## 13. Conflict matrix

| New behavior | Current architecture | Conflict? | Why |
| --- | --- | --- | --- |
| User ♥ Event → Memory | Có curation + builder + save, nhưng không có Love state/entry point | Có | Thiếu persistence Love, provenance và idempotent lookup theo source. |
| Auto Event → Memory | First Experience có pipeline tương tự | Có | Chỉ được thiết kế chọn một First Memory; curation Vision có chi phí và không có batch/lifecycle. |
| Same Event promoted twice | Builder tạo UUID mới; save theo candidate ID | Có | Insert duplicate, không update row cũ. |
| First Memory + Auto Promotion | Cùng model/repository nhưng chỉ `fetchLatest` | Có | Nhiều row không có feed, origin hay policy phân biệt. |
| Event rebuild after Memory | Event ID UUID mới; rebuild xóa Event `.new` | Có, nghiêm trọng | Memory/curration tham chiếu old Event ID thành orphan/stale. |
| User removes auto Memory | Có enum `.dismissed` nhưng không có API/UI/transition | Có | Không lưu suppression nên không ngăn promote lại. |
| Multiple Memories in Home | Home chỉ giữ `latestMemory` | Có | Không có fetch collection hoặc Memory list. |
| Trip → Memory | Builder/schema/curation đều Event-only | Có | Trip chỉ có event IDs, không phải Memory source trực tiếp. |

## 14. Kết luận bắt buộc

### A. Có thể reuse nguyên trạng

`EventPhotoCurationService`, Vision analyzer, `EventCurationResult` persistence, `MemoryBuilder` (logic chọn cover/ảnh), `MemoryViewerView`, và `MemorySelectionEditView` là các khối có thể tái sử dụng về chức năng. Reuse cần đi kèm một source identity ổn định trước khi chạy trên nhiều lần discovery.

### B. Cần giải quyết trước khi bật Auto Promotion

1. Identity source bền qua event rebuild và mapping/lookup Memory theo source.
2. Uniqueness/idempotency để một source chỉ có một Memory, không phụ thuộc UUID mới của builder.
3. Lifecycle/provenance: auto-promoted, user-loved, first experience, dismissed và suppression.
4. Collection query/feed nếu nhiều Memory phải xuất hiện ngoài Home.
5. Chính sách chạy curation bất đồng bộ/batch để tránh làm chậm initial flow.

### C. Risk duplicate/orphan

Duplicate do `MemoryBuilder` tạo UUID mới trong khi store upsert theo UUID đó. Orphan do Event UUID không deterministic và `replaceRebuildableEvents` xóa Event `.new`; Memory lưu UUID cũ. Curation có thể stale vì cũng khóa theo Event UUID cũ. Trip có cùng lớp rủi ro vì cũng rebuilt bằng UUID mới.

### D. Event identity có đủ ổn định làm Memory source không?

Không. Nó chỉ ổn định trong một vòng đời discovery hiện tại. Code chứng minh `EventDiscoveryEngine` tạo `UUID()` và store replace Event rebuildable wholesale. Đây là điểm không thể bỏ qua cho Memory/Love persistence.

### E. Curation có đủ reusable không?

Curation đủ reusable về thuật toán và persistence cho First Memory, User Love và Auto Promotion **khi source Event ID còn hợp lệ**. Nó chưa đủ như một nền tảng promotion hoàn chỉnh do stale/rebuild risk, Event-only coupling, và chi phí Vision. First Memory hiện chạy ít nhất có thể (top 3, rồi fallback); Auto Promotion hàng loạt cần scheduling riêng.

### F. Giữ `MemoryCandidate` hay đổi semantics thành final `Memory`?

Theo code hiện tại, object được persist, mở lại và chỉnh sửa sau onboarding; semantics thực tế là final Memory. Giữ tên `MemoryCandidate` sẽ tiếp tục gây mơ hồ giữa đối tượng tạm để scoring và object đã được promote. Không thực hiện refactor trong survey này, nhưng product model mới nên tách candidate/scoring transient khỏi persisted final Memory, hoặc đổi semantics/tên một cách nhất quán.
