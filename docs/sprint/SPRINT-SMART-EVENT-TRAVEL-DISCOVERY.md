# SPRINT — SMART EVENT & TRAVEL DISCOVERY

> **Project:** Nizi  
> **Status:** Proposed  
> **Priority:** P0 — Memory Quality Foundation  
> **Depends on:** Local Memory Index, Event Discovery foundation  
> **Related sprint:** First Memory Experience  
> **Goal:** Nâng Event Discovery từ cơ chế gom ảnh chủ yếu theo thời gian/địa điểm thành một hệ thống hiểu ngữ cảnh tốt hơn: biết khi nào một sự kiện bắt đầu/kết thúc, đâu là Nhà, đâu là địa điểm quen thuộc, khi nào user đang đi xa, đâu là chuyến đi trong nước và đâu là chuyến đi nước ngoài.

---

# 1. Bối cảnh

Nizi hiện đã có nền tảng:

- `IndexedAsset`
- `PhotoSession`
- `PhotoEvent`
- `EventDiscoveryEngine`
- `EventDiscoveryConfig`
- `DiscoverEventsUseCase`
- Local Memory Index
- GPS metadata
- Photo Location clustering
- reverse geocoding / `PhotoPlace`
- Event curation

Pipeline hiện tại về cơ bản:

```text
Photos
  ↓
IndexedAsset
  ↓
PhotoSession
  ↓
PhotoEvent
  ↓
Curation
  ↓
Memory / Album
```

Kiến trúc này đúng hướng và không cần phá bỏ.

Tuy nhiên chất lượng Event hiện chưa đủ tốt cho Memory Experience.

Các lỗi thực tế đã quan sát:

1. Một nhóm ảnh nhỏ ở địa điểm khác nhưng gần về thời gian vẫn bị dính vào Event trước.
2. Event có thể kéo dài 5–7 ngày dù các ảnh trong đó không thực sự thuộc cùng một câu chuyện.
3. Một chuyến đi nhiều ngày có thể bị hiểu như một Event duy nhất thay vì một Trip chứa nhiều Event nhỏ.
4. Nizi chưa hiểu đâu là `Home`.
5. Chưa phân biệt rõ:
   - ở nhà;
   - địa điểm quen thuộc;
   - hoạt động local;
   - đi xa;
   - chuyến du lịch;
   - chuyến du lịch nước ngoài.
6. Khoảng cách địa lý lớn đôi khi cần SPLIT Event, nhưng trong một Trip nhiều thành phố lại không nên SPLIT Trip.
7. Developer hiện khó biết chính xác vì sao engine quyết định MERGE hoặc SPLIT hai session.

Sprint này giải quyết các vấn đề trên.

---

# 2. Product Principle

Event Discovery không được dựa vào một rule kiểu:

```text
timeGap < X
→ same event
```

Thay vào đó:

> Hai session chỉ được merge khi tổng hợp nhiều signal cho thấy chúng có cùng context.

Các signal chính:

```text
Time
Location
Home/Away context
Place continuity
Travel context
Day boundary
Return-home pattern
Photo activity
```

Visual similarity có thể bổ sung sau nhưng không phải dependency bắt buộc của sprint này.

---

# 3. Mục tiêu Sprint

Sau sprint:

Nizi phải có khả năng tốt hơn trong việc trả lời:

### Event

```text
Những ảnh nào thực sự thuộc cùng một sự kiện?
```

### Boundary

```text
Khi nào sự kiện trước kết thúc và sự kiện mới bắt đầu?
```

### Home

```text
Vùng nào có khả năng là nơi user sinh hoạt thường xuyên nhất?
```

### Familiar Place

```text
Địa điểm nào user thường xuyên quay lại nhưng không phải Home?
```

### Away

```text
Khi nào user đang ở ngoài vùng sinh hoạt quen thuộc?
```

### Trip

```text
Nhiều Event này có thuộc cùng một chuyến đi không?
```

### Travel classification

```text
Local outing
Day trip
Domestic trip
International trip
```

---

# 4. Không thay đổi kiến trúc nền tảng nếu không cần

Giữ:

```text
IndexedAsset
PhotoSession
PhotoEvent
EventDiscoveryEngine
DiscoverEventsUseCase
Local Memory Index
```

Không rewrite Event Discovery từ đầu.

Thêm các lớp intelligence phía trên / xung quanh engine hiện có.

Kiến trúc mục tiêu:

```text
PHOTOS
   ↓
IndexedAsset
   ↓
Temporal Sessionization
   ↓
PhotoSession
   ↓
Location Intelligence
   │
   ├── LocationCluster
   ├── HomeAnchor
   └── FamiliarPlace
   ↓
Event Boundary Analysis
   ↓
PhotoEvent
   ↓
Travel Context Analysis
   ↓
PhotoTrip
   ↓
Travel Classification
   ↓
Memory Candidate
```

---

# 5. Phase 1 — Session Quality

`PhotoSession` tiếp tục là đơn vị nhỏ nhất để Event Discovery làm việc.

Không bắt buộc thêm persistent `MicroEvent`.

Mục tiêu:

> Những ảnh được chụp gần nhau trong cùng một hoạt động nhỏ phải nằm cùng session.

Ví dụ:

```text
10:01 photo
10:01 photo
10:02 photo
10:03 photo
```

→ same session.

Nhưng:

```text
10:02 hotel
10:45 beach
12:30 restaurant
15:00 museum
```

không nên trở thành một session duy nhất chỉ vì cùng ngày.

---

## 5.1 Session signals

Session boundary sử dụng tối thiểu:

```text
capture time gap
GPS distance nếu có
day boundary
```

Config phải tập trung trong:

```swift
EventDiscoveryConfig
```

hoặc config riêng nếu kiến trúc hiện tại phù hợp hơn.

Không hard-code threshold trong View.

---

# 6. Location Intelligence

Tạo layer mới:

```text
Location Intelligence
```

Mục đích không phải chỉ reverse-geocode.

Nó phải hiểu lịch sử xuất hiện của user tại các location cluster.

---

# 7. LocationCluster

Nếu PhotoLocation module hiện đã có clustering phù hợp thì reuse.

Không tạo clustering engine thứ hai nếu không cần.

Một cluster cần có tối thiểu:

```swift
struct LocationCluster {
    let id: UUID

    let centroid: CLLocationCoordinate2D
    let radiusMeters: Double

    let assetCount: Int

    let distinctDayCount: Int
    let distinctMonthCount: Int

    let firstSeenAt: Date
    let lastSeenAt: Date

    let place: PhotoPlace?
}
```

Tên/type cụ thể phải theo convention project.

---

# 8. Home Detection

Tạo:

```swift
struct HomeAnchor {
    let clusterID: UUID
    let coordinate: CLLocationCoordinate2D
    let confidence: Double
}
```

Không cần biết địa chỉ nhà chính xác.

Nizi chỉ cần biết:

> Đây là vùng user xuất hiện lặp lại trong thời gian dài và có xác suất cao là Home.

---

# 9. Home Score

Không xác định Home bằng tổng số ảnh.

Sai:

```text
cluster có nhiều ảnh nhất = Home
```

Vì user có thể chụp hàng nghìn ảnh trong một chuyến du lịch.

Home score ưu tiên:

```text
distinct days
distinct weeks/months
long-term recurrence
evening/night presence nếu dữ liệu đủ
return frequency
time span between first/last appearance
```

Concept:

```text
HomeScore =
    recurrenceScore
  + distinctDayScore
  + distinctMonthScore
  + longTermPresenceScore
  + eveningPresenceScore
  + returnScore
```

Không bắt buộc mọi signal trong V1.

Ưu tiên signal deterministic và đã có data.

---

# 10. Home confidence

Không gán Home nếu confidence thấp.

Ví dụ:

```swift
enum HomeConfidence {
    case unknown
    case low
    case medium
    case high
}
```

Hoặc dùng `Double`.

Nếu library chỉ có vài tuần dữ liệu:

```text
Home = unknown
```

Engine phải tiếp tục hoạt động mà không cần Home.

---

# 11. Không assume chỉ có một nơi quen thuộc

Sprint V1 chỉ cần:

```text
dominantHomeAnchor
```

Nhưng data model không nên khóa cứng kiến trúc vào một coordinate duy nhất.

Tương lai có thể có:

```text
Primary Home
Secondary Home
Work
Family Home
Frequent Place
```

Sprint này không cần phân loại Work.

---

# 12. Familiar Place

Tạo khái niệm:

```swift
struct FamiliarPlace {
    let clusterID: UUID
    let confidence: Double
}
```

Một Familiar Place:

- xuất hiện nhiều ngày;
- user quay lại thường xuyên;
- nhưng không đạt HomeScore cao nhất.

Ví dụ:

```text
văn phòng
trường học
nhà ông bà
quán quen
showroom
```

Không cần đặt semantic label chính xác trong sprint.

Chỉ cần:

```text
familiar vs unfamiliar
```

---

# 13. LocationContext

Derive context:

```swift
enum LocationContext {
    case home
    case familiar
    case local
    case away
    case unknown
}
```

Không persist nếu derive rẻ.

Mỗi session/event có thể query:

```text
locationContext
```

---

# 14. Event Boundary Engine

Đây là phần trọng tâm của sprint.

Không quyết định merge/split bằng một threshold đơn.

Tạo abstraction:

```swift
protocol EventBoundaryEvaluating {
    func evaluate(
        previous: PhotoSession,
        next: PhotoSession,
        context: EventBoundaryContext
    ) -> EventBoundaryDecision
}
```

---

# 15. EventBoundaryDecision

Không chỉ trả `Bool`.

Trả cả reasoning để debug.

Ví dụ:

```swift
struct EventBoundaryDecision {
    let action: BoundaryAction

    let score: Double

    let reasons: [BoundarySignalResult]
}
```

```swift
enum BoundaryAction {
    case merge
    case split
}
```

---

# 16. Boundary signals

Tối thiểu xem xét:

```text
time gap
distance
same location cluster
same city/region nếu có
day boundary
home/away transition
return home
travel continuity
```

Visual similarity để sprint sau nếu chưa có infrastructure.

---

# 17. Time continuity

Ví dụ scoring concept:

```text
0–10 min        very strong merge
10–60 min       strong merge
1–3 h           moderate merge
3–8 h           weak
8–16 h          split tendency
>16 h           strong split tendency
```

Không lấy các giá trị trên làm truth cố định.

Phải config + tune bằng real library.

---

# 18. Spatial continuity

Khoảng cách phải được đánh giá theo context.

Ví dụ:

```text
< 200 m       strong same-place signal
< 2 km        likely same local activity
2–20 km       context dependent
20–100 km     weak Event continuity
> 100 km      strong Event boundary
```

Nhưng không dùng distance một mình để quyết định Trip boundary.

---

# 19. Home transition là signal mạnh

Các pattern:

```text
HOME → AWAY
```

có thể bắt đầu một outing/trip.

```text
AWAY → HOME
```

là signal rất mạnh để kết thúc outing/trip.

Ví dụ:

```text
Event conference
↓
16 hour gap
↓
320 km jump
↓
HOME
```

→ hard split.

---

# 20. Hard Boundary

Một số combination đủ mạnh để force split.

Ví dụ:

```text
large time gap
+
large spatial jump
+
return home
```

hoặc:

```text
country changed
+
long gap
+
travel context ended
```

Tạo explicit concept:

```swift
isHardBoundary
```

để tránh một signal merge khác vô tình kéo hai context lại với nhau.

---

# 21. Ngăn Event kéo dài 5–7 ngày vô lý

Event không nên được merge chỉ vì mỗi ngày có một vài ảnh nối tiếp nhau.

Thêm `EventCohesion`.

Một Event dài cần chứng minh có continuity.

Concept:

```text
EventCohesion =
    session continuity
  + location continuity
  + activity density
  + contextual consistency
```

Nếu cohesion giảm mạnh:

```text
split
```

---

# 22. Event duration guardrail

Không hard-cap kiểu:

```text
Event max = 1 day
```

vì có Event thực sự kéo dài.

Nhưng duration càng dài thì evidence để tiếp tục merge phải càng mạnh.

Concept:

```text
merge threshold increases with event duration
```

Ví dụ:

```text
Event mới 2 giờ
→ merge tương đối dễ

Event đã 2 ngày
→ cần evidence mạnh hơn

Event đã 5 ngày
→ chỉ merge nếu context rất rõ
```

---

# 23. PhotoTrip

Không dùng `PhotoEvent` để đại diện cả chuyến du lịch nhiều ngày.

Thêm domain model:

```swift
struct PhotoTrip: Identifiable {
    let id: UUID

    let startDate: Date
    let endDate: Date

    let eventIDs: [UUID]

    let primaryPlace: PhotoPlace?

    let classification: TravelClassification

    let confidence: Double
}
```

Persistence implementation tùy architecture hiện tại.

---

# 24. Event vs Trip

Phân biệt:

```text
EVENT
= một hoạt động / context tương đối liền mạch

TRIP
= một hành trình có thể chứa nhiều Event
```

Ví dụ:

```text
Japan Trip
│
├── Airport
├── Tokyo Day 1
├── Tokyo Day 2
├── Shinkansen
├── Kyoto
├── Osaka
└── Return
```

Không merge tất cả thành một `PhotoEvent`.

---

# 25. Trip Detection

Pattern mạnh nhất:

```text
HOME
 ↓
AWAY
 ↓
AWAY
 ↓
AWAY
 ↓
HOME
```

Tạo:

```swift
protocol TripDetecting {
    func detectTrips(
        events: [PhotoEvent],
        home: HomeAnchor?,
        context: TravelContext
    ) -> [PhotoTrip]
}
```

---

# 26. TravelContext

Ví dụ:

```swift
struct TravelContext {
    let homeCountryCode: String?

    let distanceFromHome: Double?
    let overnightCount: Int

    let countries: Set<String>
    let cities: Set<String>

    let hasDepartureFromHome: Bool
    let hasReturnToHome: Bool
}
```

Không bắt buộc property đúng y hệt nếu code hiện tại có representation tốt hơn.

---

# 27. TravelClassification

Tạo:

```swift
enum TravelClassification {
    case local
    case dayTrip
    case domesticTrip
    case internationalTrip
    case unknown
}
```

---

# 28. Local

Ví dụ:

```text
Home Hanoi
↓
restaurant 5 km away
↓
Home
```

→ `.local`

Không phải Trip.

---

# 29. Day Trip

Ví dụ:

```text
Home Hanoi
↓
Ninh Binh
↓
several sessions
↓
Home same day
```

→ `.dayTrip`

Không cần overnight.

---

# 30. Domestic Trip

Ví dụ:

```text
Home Hanoi
↓
Da Nang
↓
3 nights
↓
Hoi An
↓
Da Nang
↓
Home Hanoi
```

→ `.domesticTrip`

Trip có nhiều Event.

---

# 31. International Trip

Nếu Home country có confidence đủ tốt:

```text
Home country = VN
Trip countries = JP
```

→ `.internationalTrip`

Ví dụ:

```text
Tokyo
Kyoto
Osaka
```

không tách thành 3 Trip chỉ vì khoảng cách lớn.

---

# 32. Country handling

Nếu `PhotoPlace` hiện chưa persist:

```text
country
countryCode
administrativeArea
locality
```

hãy khảo sát trước.

Chỉ bổ sung field thực sự cần.

Không tạo reverse-geocoding request cho từng ảnh.

Reverse geocode theo:

```text
LocationCluster
```

hoặc representative coordinate.

Cache kết quả.

---

# 33. Trip continuity khác Event continuity

Đây là nguyên tắc quan trọng.

### Event

Location jump lớn thường là evidence SPLIT.

### Trip

Location jump lớn có thể hoàn toàn hợp lệ.

Ví dụ:

```text
Tokyo → Kyoto
```

Event:

```text
split
```

Trip:

```text
same trip
```

nếu:

- vẫn away from home;
- time continuity hợp lý;
- chưa return home;
- travel sequence liên tục.

---

# 34. Trip termination

Signal mạnh:

```text
return to Home
```

Các signal khác:

```text
long inactivity
return to familiar long-term area
large temporal break
new unrelated travel sequence
```

Không cần tất cả trong V1.

---

# 35. Missing GPS

Engine phải hoạt động với ảnh không có GPS.

Fallback:

```text
time continuity
neighboring sessions with GPS
day context
existing Event evidence
```

Không discard ảnh chỉ vì thiếu location.

Nếu một session:

```text
photo A GPS Da Nang
photo B no GPS
photo C no GPS
photo D GPS Da Nang
```

có thể infer session context = Da Nang với confidence phù hợp.

Không ghi GPS giả vào asset.

---

# 36. Sparse GPS

Không assume mọi ảnh trong Event đều có GPS.

Location context có thể derive từ:

```text
representative GPS samples
```

và confidence.

---

# 37. Location privacy

Tất cả xử lý sprint này:

```text
LOCAL ONLY
```

Không upload:

- GPS
- Home
- travel history
- country history

Không cần backend.

`HomeAnchor` là internal derived data.

Không cần hiển thị địa chỉ nhà chính xác cho user.

---

# 38. Diagnostics — bắt buộc

Đây là deliverable quan trọng.

Tạo / nâng cấp Event Discovery Diagnostics để developer biết:

> Vì sao hai session được MERGE hoặc SPLIT?

Ví dụ:

```text
Session A → Session B

Time gap          42 min       +0.70
Distance          850 m        +0.45
Same cluster      YES          +0.35
Same city         YES          +0.15
Away from home    YES          +0.10
Return home       NO            0.00
Day boundary      NO            0.00

TOTAL             1.75

DECISION
MERGE
```

Split:

```text
Session A → Session B

Time gap          16 h         -0.65
Distance          322 km       -0.80
Same cluster      NO           -0.30
Return home       YES          -1.00

TOTAL             -2.75

HARD BOUNDARY
YES

DECISION
SPLIT
```

---

# 39. Home Diagnostics

Trong DEBUG thêm view:

```text
Home Detection
```

Hiển thị:

```text
Candidate Cluster
Distinct days
Distinct months
First seen
Last seen
Evening presence
Home score
Confidence
```

Không cần map phức tạp nếu chưa có.

Nếu map đã có infrastructure thì có thể show cluster.

---

# 40. Trip Diagnostics

DEBUG view:

```text
Detected Trips
```

Mỗi Trip:

```text
Japan
7 days
International
Confidence 0.91

Events: 8
Cities:
Tokyo
Kyoto
Osaka

Departure from home: YES
Return home: YES
```

---

# 41. Decision trace

Scoring engine phải trả trace data.

Không chỉ:

```swift
return true
```

Phải có representation đủ để diagnostics hiển thị reason.

Điều này là bắt buộc để tune thuật toán.

---

# 42. Config

Centralize các threshold.

Ví dụ:

```swift
struct SmartEventDiscoveryConfig {

    // Session
    var microSessionGap: TimeInterval

    // Event
    var strongTimeGap: TimeInterval
    var hardTimeGap: TimeInterval

    var nearbyDistanceMeters: Double
    var largeDistanceMeters: Double

    var mergeThreshold: Double
    var hardSplitThreshold: Double

    // Home
    var minimumHomeDistinctDays: Int
    var minimumHomeDistinctMonths: Int
    var homeConfidenceThreshold: Double

    // Travel
    var minimumDayTripDistance: Double
    var minimumTripDuration: TimeInterval
}
```

Tên/config thực tế phải phù hợp architecture hiện tại.

Không copy config nếu `EventDiscoveryConfig` có thể mở rộng sạch.

---

# 43. Không dùng Magic Numbers trong Engine

Không viết:

```swift
if distance > 50000
```

rải rác.

Mọi threshold có ý nghĩa phải nằm trong config.

---

# 44. Determinism

Cùng:

```text
IndexedAsset dataset
+
config
```

phải tạo:

```text
same sessions
same events
same home result
same trips
```

Không random.

Rất quan trọng cho regression testing.

---

# 45. Persistence strategy

Không persist mọi derived value nếu không cần.

Persist khi:

- tính toán tốn kém;
- cần resume;
- cần giữ identity ổn định;
- cần liên kết Memory.

Có thể persist:

```text
HomeAnchor
PhotoTrip
event/trip relation
```

nếu hợp architecture.

Boundary score / trace:

```text
DEBUG only
```

hoặc derive on demand.

---

# 46. Interaction với First Memory Experience

First Memory Coordinator không cần hiểu chi tiết thuật toán mới.

Nó chỉ nhận:

```text
PhotoEvent
PhotoTrip
quality score
travel classification
```

Memory scoring sau này có thể ưu tiên:

```text
internationalTrip
domesticTrip
dayTrip
strong Event
```

Ví dụ:

```text
International Trip      strong Memory candidate
Domestic Trip           strong
Birthday Event          strong
Random local photos     weak
```

Sprint này không rewrite First Memory Coordinator nếu không cần.

---

# 47. Memory Candidate source

Sau sprint, Memory có thể được tạo từ:

```text
PhotoEvent
```

hoặc:

```text
PhotoTrip
```

Không bắt buộc triển khai full Trip → Memory presentation trong sprint này.

Nhưng Domain không được khóa Memory vào Event-only về lâu dài.

---

# 48. Performance

Target library:

```text
100,000+ assets
```

Không được:

- reverse-geocode từng ảnh;
- load full-resolution image để Event Discovery;
- chạy Vision nặng trên toàn bộ library trong sprint này;
- giữ toàn bộ UIImage trong memory.

Dùng:

```text
metadata
coordinates
timestamps
cluster summaries
```

là chính.

---

# 49. Incremental updates

Sau full initial scan, ảnh mới phải có khả năng:

```text
new assets
 ↓
session update
 ↓
event update
 ↓
trip update
```

Không rebuild toàn bộ history nếu không cần.

Tuy nhiên sprint này ưu tiên correctness của initial discovery.

Incremental optimization có thể triển khai sau nếu scope quá lớn.

---

# 50. Regression fixtures

Tạo test fixtures synthetic hoặc từ metadata anonymized.

Ít nhất các case:

---

## Fixture A — Normal local day

```text
Home
↓
Cafe
↓
Restaurant
↓
Home
```

Expected:

```text
No Trip
Multiple Event possible
```

---

## Fixture B — Domestic trip

```text
Hanoi
↓
Da Nang
↓
Hoi An
↓
Da Nang
↓
Hanoi
```

Expected:

```text
1 Domestic Trip
multiple Events
```

---

## Fixture C — International trip

```text
Hanoi
↓
Tokyo
↓
Kyoto
↓
Osaka
↓
Hanoi
```

Expected:

```text
1 International Trip
multiple Events
```

---

## Fixture D — Unrelated tail

```text
Conference Day 1
Conference Day 2
Conference Day 3
↓
large gap
↓
different place
↓
unrelated family photos
```

Expected:

```text
family photos NOT merged into conference Event
```

---

## Fixture E — Long sparse chain

```text
Day 1: 3 photos
Day 2: 2 unrelated photos
Day 3: 4 unrelated photos
Day 5: 2 photos
```

Expected:

```text
NOT one 5-day Event
```

---

## Fixture F — Same trip, large distance

```text
Tokyo
↓
450 km
↓
Kyoto
```

Expected:

```text
different Event
same Trip
```

---

## Fixture G — Missing GPS

Mixed GPS/non-GPS photos.

Expected:

```text
reasonable Event grouping
no asset discarded
```

---

## Fixture H — Photo-heavy vacation vs Home

```text
Home:
300 photos across 18 months

Vacation:
2,000 photos across 5 days
```

Expected:

```text
Home = recurring 18-month cluster
NOT vacation cluster
```

---

# 51. Unit Tests

Bắt buộc test:

```text
Home scoring
Boundary scoring
Hard boundary
Trip grouping
Domestic classification
International classification
Missing GPS fallback
Determinism
```

Nếu engine hiện tại có test target:

reuse.

Không tạo test architecture riêng.

---

# 52. Acceptance Criteria

## AC-01 — Home

Với library có đủ history:

Nizi xác định được dominant Home cluster với confidence hợp lý.

Không chọn vacation cluster chỉ vì có nhiều ảnh hơn.

---

## AC-02 — Familiar

Các location xuất hiện lặp lại nhưng không phải Home có thể được nhận diện là familiar.

---

## AC-03 — Event tail

Một nhóm ảnh khác context sau Event lớn không bị dính chỉ vì gần thời gian.

---

## AC-04 — Long unrelated chain

Chuỗi ảnh 5–7 ngày không bị merge thành một Event nếu cohesion thấp.

---

## AC-05 — Multi-event trip

Một Trip nhiều ngày có thể chứa nhiều PhotoEvent.

---

## AC-06 — Domestic

Trip trong cùng home country được classify `.domesticTrip` khi đủ evidence.

---

## AC-07 — International

Trip ngoài home country được classify `.internationalTrip` khi đủ evidence.

---

## AC-08 — Large travel jump

Khoảng cách lớn giữa hai city:

```text
may split Event
```

nhưng:

```text
must not automatically split Trip
```

---

## AC-09 — Return home

`AWAY → HOME` là strong trip termination signal.

---

## AC-10 — Missing GPS

Ảnh thiếu GPS vẫn tham gia Event Discovery.

---

## AC-11 — Explainability

Trong DEBUG developer có thể inspect:

```text
why MERGE
why SPLIT
why HOME
why TRIP
```

---

## AC-12 — Local only

Không backend/network dependency mới ngoài reverse geocoding behavior hệ thống hiện có.

---

# 53. Không làm trong Sprint

Explicitly out of scope:

- Cloud AI.
- Server-side location analysis.
- Upload GPS.
- Face recognition mới.
- Person identity graph.
- Semantic scene embedding toàn library.
- LLM event naming.
- Automatic story writing.
- Route reconstruction chính xác.
- Transport mode detection.
- Work/Home semantic classification nâng cao.
- Multiple household members.
- Social graph.
- Weather enrichment.
- POI database riêng.
- Travel recommendation.
- Map product redesign.
- Photobook changes.
- Payment.
- Backend.

---

# 54. Files / areas cần khảo sát trước khi code

Claude Code phải khảo sát implementation thật của:

```text
EventDiscoveryEngine.swift
EventDiscoveryConfig.swift
DiscoverEventsUseCase.swift

PhotoSession
PhotoEvent
IndexedAsset

PhotoLocationService.swift
PhotoLocationRepository.swift
PhotoLocationClusterer.swift
PhotoPlace.swift

EventDiscoveryDebugListView.swift
EventListView.swift
EventDetailView.swift

MemoryIndexStore.swift
SQLiteMemoryIndexStore.swift
```

Không assume survey hoàn toàn phản ánh implementation mới nhất.

---

# 55. Components dự kiến thêm

Tên chỉ là đề xuất:

```text
MemoryDiscovery/Domain/

    HomeAnchor.swift
    FamiliarPlace.swift
    LocationContext.swift

    EventBoundaryDecision.swift
    BoundarySignalResult.swift

    PhotoTrip.swift
    TravelContext.swift
    TravelClassification.swift


MemoryDiscovery/Application/

    HomeDetectionService.swift
    EventBoundaryEvaluator.swift
    TripDiscoveryService.swift
    TravelClassificationService.swift


Diagnostics/

    HomeDetectionDiagnosticsView.swift
    EventBoundaryDiagnosticsView.swift
    TripDiscoveryDiagnosticsView.swift
```

Nếu các abstraction hiện tại có chỗ phù hợp hơn, integrate thay vì tạo file thừa.

---

# 56. Implementation order

Không code tất cả cùng lúc.

Thứ tự:

```text
STEP 1
Location cluster statistics

STEP 2
Home detection

STEP 3
LocationContext

STEP 4
Boundary scoring + decision trace

STEP 5
Integrate boundary evaluator into EventDiscoveryEngine

STEP 6
Event cohesion / long-event protection

STEP 7
PhotoTrip model

STEP 8
Trip grouping

STEP 9
Domestic / International classification

STEP 10
Diagnostics

STEP 11
Regression tests

STEP 12
Tune config using real library
```

Build/test sau từng step lớn.

---

# 57. Tuning workflow

Sau khi implementation chạy:

Không tune bằng cảm giác từ một Event.

Dùng Diagnostics và kiểm tra nhiều case.

Workflow:

```text
Bad Event
 ↓
Inspect boundary trace
 ↓
Identify wrong signal
 ↓
Adjust config / scoring
 ↓
Run regression fixtures
 ↓
Rebuild Event
 ↓
Compare
```

Không sửa bằng:

```text
if this specific location...
```

Không special-case dữ liệu cá nhân.

---

# 58. Definition of Done

Sprint hoàn thành khi có thể chạy test trên real iPhone library và:

```text
1. Scan/index library.

2. Nizi derives recurring location clusters.

3. Nizi identifies probable Home when enough history exists.

4. Event Discovery runs automatically.

5. Unrelated photo tails are split correctly more often.

6. Sparse 5–7 day chains are no longer automatically treated
   as one Event.

7. Multi-day travel is represented as multiple Events grouped
   into one Trip where appropriate.

8. Trip can be classified:
   local / day trip / domestic / international.

9. Return Home influences trip termination.

10. Missing-GPS photos are not excluded.

11. Developer can open Diagnostics and inspect exactly why
    a session boundary was MERGE or SPLIT.

12. Developer can inspect why a location was considered Home.

13. Developer can inspect detected Trips.

14. Existing Event and Album flows still build and work.
```

---

# 59. Success Criterion

Success không phải:

```text
Nizi tạo ít Event hơn
```

hay:

```text
Nizi tạo nhiều Trip hơn
```

Success là:

> Khi user nhìn vào một Event hoặc Trip, ranh giới của nó thường phù hợp với cách con người nhớ lại sự việc.

Và quan trọng hơn cho Memory Experience:

> Nizi không chỉ biết các ảnh được chụp gần nhau — Nizi bắt đầu hiểu user đang ở đâu trong cuộc sống của họ: ở nhà, ở nơi quen thuộc, đang đi xa, hay đang trong một chuyến đi.
