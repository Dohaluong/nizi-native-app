
# SURVEY — KẾT QUẢ: VÌ SAO TRIP DIAGNOSTICS PHẦN LỚN "UNKNOWN"

Khảo sát thuần đọc code, không sửa gì. Toàn bộ câu trả lời trích trực tiếp từ implementation hiện tại.

---

## 1. Location input

### PhotoEvent có representative coordinate không?

**Không.** `PhotoEvent` ([PhotoEvent.swift:15-38](Nizi/Features/MemoryDiscovery/Domain/PhotoEvent.swift#L15-L38)) không có field `latitude`/`longitude` nào cả — chỉ có `sessionIDs`/`assetIDs`, `primaryLocationLabel` (string), `eventPlace`. Coordinate của một Event luôn phải **suy ra** từ các `PhotoSession` của nó tại thời điểm dùng, không lưu sẵn.

### TripDiscoveryEngine lấy coordinate từ đâu?

`TripDiscoveryEngine.representativeCoordinate(for:sessionsByID:)` ([TripDiscoveryEngine.swift:93-103](Nizi/Features/MemoryDiscovery/Domain/TripDiscoveryEngine.swift#L93-L103)): lấy tất cả `PhotoSession` thuộc Event đó, lọc còn session có `centerLatitude`/`centerLongitude` khác nil, rồi **trung bình cộng** các session đó. Nếu Event không có session nào có coordinate → trả `nil`.

`PhotoSession.centerLatitude/centerLongitude` bản thân nó cũng là suy ra: `EventDiscoveryEngine.buildSession` ([EventDiscoveryEngine.swift:126-152](Nizi/Features/MemoryDiscovery/Domain/EventDiscoveryEngine.swift#L126-L152)) lọc các **asset (ảnh)** trong session có GPS EXIF (`asset.latitude != nil`), rồi trung bình cộng. Nếu **không ảnh nào** trong session có GPS → `centerLatitude`/`centerLongitude` cả hai đều `nil`.

→ Chuỗi suy luận: Event coordinate phụ thuộc hoàn toàn vào **tỷ lệ ảnh có GPS EXIF** trong thư viện thật của user — code không kiểm soát được, chỉ phản ánh dữ liệu gốc.

### Event Boundary Evaluator lấy distance từ đâu?

Cùng nguồn: `previous.centerLatitude/centerLongitude` và `next.centerLatitude/centerLongitude` — **cấp session**, không phải cấp event hay cấp ảnh riêng lẻ ([EventBoundaryEvaluating.swift:40-45](Nizi/Features/MemoryDiscovery/Domain/EventBoundaryEvaluating.swift#L40-L45)).

### Bao nhiêu Event thực tế có coordinate?

Không thể trả lời bằng đọc code — phụ thuộc dữ liệu thật (bao nhiêu % ảnh trong thư viện của user có GPS). Đây chính là **biến số duy nhất** quyết định câu trả lời của toàn bộ khảo sát này, và hiện **không có diagnostics nào đo/hiển thị con số này** (xem mục 6).

### Khi nào distance trở thành unknown?

- `EventBoundaryEvaluator`: khi `previous` **hoặc** `next` thiếu `centerLatitude`/`centerLongitude` → `distanceKm = nil` → hiển thị `"unknown"`, contribution = 0 ([EventBoundaryEvaluating.swift:106-109](Nizi/Features/MemoryDiscovery/Domain/EventBoundaryEvaluating.swift#L106-L109)).
- `LocationContextResolver.resolve`: khi `latitude`/`longitude` truyền vào là `nil` → trả thẳng `.unknown`, **không phải** `.home`/`.away`/`.local` ([LocationContext.swift:30](Nizi/Features/MemoryDiscovery/Domain/LocationContext.swift#L30)). Một Event `.unknown` **không** vào nhóm Trip (chỉ `.away` mới vào), coi như một điểm ngắt giống như về nhà.

---

## 2. Home input

### HomeAnchor được persist ở đâu?

`MDHomeAnchor` (SwiftData model), qua `SwiftDataMemoryDiscoveryStore.replaceLocationIntelligence(clusters:home:familiarPlaces:)` ([SwiftDataMemoryDiscoveryStore.swift:486-507](Nizi/Features/MemoryDiscovery/Infrastructure/SwiftDataMemoryDiscoveryStore.swift#L486-L507)) và `confirmUserHome(_:)` ([:509-515](Nizi/Features/MemoryDiscovery/Infrastructure/SwiftDataMemoryDiscoveryStore.swift#L509-L515)). Có bảo vệ: nếu Home hiện tại có `source == .userConfirmed`, `replaceLocationIntelligence` **không ghi đè** nó bằng Home tính lại.

### TripDiscoveryEngine có nhận HomeAnchor thật (đã persist/user-confirmed) không?

**Không, chưa bao giờ.** Đây là phát hiện quan trọng nhất của khảo sát này.

`EventDiscoveryEngine.discover(from:config:...)` ([EventDiscoveryEngine.swift:26-67](Nizi/Features/MemoryDiscovery/Domain/EventDiscoveryEngine.swift#L26-L67)) **luôn** tự tính Home mới toanh ngay trong lần gọi đó: dòng 42 `let locationIntelligence = LocationIntelligenceEngine.analyze(from: sorted, config: config)`, rồi dùng `locationIntelligence.home` (dòng 48, 57, 63) cho mọi thứ tiếp theo — Event Boundary, Trip Discovery. **Không có tham số nào** để truyền một `HomeAnchor` đã persist/user-confirmed vào `discover(...)`.

`replaceLocationIntelligence`'s bảo vệ "không ghi đè Home đã confirm" chỉ áp dụng cho **việc lưu vào DB** — nó không hề ảnh hưởng đến Home mà `discover()` **thực sự dùng để tính toán** trong lần chạy đó. Nói cách khác: user confirm Home xong, giá trị đó vẫn an toàn trong DB, nhưng **mọi lần discovery chạy lại** (kể cả trong Diagnostics lẫn production `DiscoverEventsUseCase`) đều bỏ qua nó và tính một Home `.inferred` mới từ tập asset hiện có tại thời điểm đó.

Xác nhận thêm: `DiscoverEventsUseCase.execute()` ([DiscoverEventsUseCase.swift:42-59](Nizi/Features/MemoryDiscovery/Application/DiscoverEventsUseCase.swift#L42-L59)) gọi `EventDiscoveryEngine.discover(from: assets, config: config)` — không có bước đọc `store.fetchHome()` trước rồi truyền vào. `TripDiscoveryDiagnosticsView`, `EventBoundaryDiagnosticsView`, `HomeDetectionDiagnosticsView` đều giống hệt: gọi `store.fetchClusterableAssets()` rồi tính lại từ đầu, **không nơi nào** gọi `store.fetchHome()`.

### Diagnostics Run có load Home trước khi detect Trip không?

**Không.** Cả hai Diagnostics screen liên quan đều tính Home lại từ đầu mỗi lần Run (xem trên) — chưa từng đọc `MDHomeAnchor` đã lưu.

### Nếu Home nil thì LocationContextResolver trả gì?

Nhánh `home == nil`: match Familiar Place vẫn chạy bình thường (không cần Home). Nhưng nếu không khớp Familiar Place nào, dòng cuối `guard let home else { return .unknown }` ([LocationContext.swift:53](Nizi/Features/MemoryDiscovery/Domain/LocationContext.swift#L53)) → trả `.unknown`, không phải `.away`. Và `TripDiscoveryEngine.detectTrips`: `guard let home else { return [] }` ([TripDiscoveryEngine.swift:36](Nizi/Features/MemoryDiscovery/Domain/TripDiscoveryEngine.swift#L36)) — Home nil thì **không tạo Trip nào cả**, không lỗi, engine chạy tiếp bình thường như thiết kế.

### Vì sao gần như tất cả Departure/Return đều NO?

Ba nguyên nhân cộng dồn, đều xác nhận được từ code:

1. **Home bị tính lại mỗi lần** (mục trên) — nếu tập asset hiện tại (đầy đủ hơn hoặc khác lần trước) khiến cluster Home không đạt `homeConfidenceLowThreshold = 0.35` ([EventDiscoveryConfig.swift:45](Nizi/Features/MemoryDiscovery/Domain/EventDiscoveryConfig.swift#L45)) → Home = nil → **mọi** Departure/Return = NO, không có Trip nào cả.
2. `hasDepartureFromHome`/`hasReturnToHome` yêu cầu Event **ngay trước/ngay sau** nhóm away phải resolve đúng `.home` ([TripDiscoveryEngine.swift:59, 68](Nizi/Features/MemoryDiscovery/Domain/TripDiscoveryEngine.swift#L68)) — tức phải có ảnh (có GPS) chụp **trong bán kính `familiarPlaceRadiusMeters` = 500m quanh Home** ([EventDiscoveryConfig.swift:49](Nizi/Features/MemoryDiscovery/Domain/EventDiscoveryConfig.swift#L49)) ngay trước khi đi / ngay sau khi về. Người dùng thực tế thường **không chụp ảnh ở nhà** ngay trước/sau chuyến đi → Event đó không tồn tại → điều kiện tự động NO, không liên quan gì đến việc chuyến đi có thật hay không.
3. Nếu Event ngay trước/sau đó **không có coordinate** (mục 1) → context = `.unknown`, không phải `.home` → cũng tính là NO.

---

## 3. Trip creation rule

Code: `TripDiscoveryEngine.detectTrips` ([TripDiscoveryEngine.swift:29-85](Nizi/Features/MemoryDiscovery/Domain/TripDiscoveryEngine.swift#L29-L85)).

**Điều kiện tạo `PhotoTrip` — chỉ đúng một điều kiện**: một hoặc nhiều Event **liên tiếp theo thời gian** có `LocationContextResolver` trả về `.away` (dòng 55 `guard annotatedEvent.context == .away else { ... }`), và khoảng cách thời gian giữa các Event liên tiếp trong nhóm đó ≤ `minimumTripTerminationGapHours = 72` giờ ([EventDiscoveryConfig.swift:60](Nizi/Features/MemoryDiscovery/Domain/EventDiscoveryConfig.swift#L60), dùng ở dòng 71). Hết.

### Một Event duy nhất có thể thành Trip không?

**Có.** `buildTrip(from group:...)` ([:105-164](Nizi/Features/MemoryDiscovery/Domain/TripDiscoveryEngine.swift#L105-L164)) không kiểm tra `group.count >= 2` ở bất kỳ đâu — nhận `group` có 1 phần tử vẫn tạo `PhotoTrip` với `eventIDs.count == 1` bình thường.

### Điều kiện nào? Có yêu cầu away from Home không?

Có — nhưng "away" ở đây **chỉ là**: khoảng cách tới Home > `localRadiusKm = 20km` ([EventDiscoveryConfig.swift:48](Nizi/Features/MemoryDiscovery/Domain/EventDiscoveryConfig.swift#L48)) **và** không nằm trong bán kính 500m của bất kỳ Familiar Place nào ([LocationContext.swift:22-58](Nizi/Features/MemoryDiscovery/Domain/LocationContext.swift#L22-L58)). Không có ngưỡng khoảng cách "trip-specific" nào khác.

### Có yêu cầu distance không? Có yêu cầu nhiều Event không? Có yêu cầu overnight không?

**Không có cả ba.** Không có ngưỡng khoảng cách tối thiểu riêng cho Trip (dùng chung ngưỡng away 20km ở trên), không yêu cầu số Event tối thiểu (mục trên), và **không yêu cầu overnight để được TẠO thành Trip** — overnight chỉ quyết định **classification** sau đó (mục 4), không phải điều kiện tạo.

---

## 4. `dayTrip` classification

Code: `TravelClassificationService.classify(trip:homeCountryCode:)` ([TravelClassificationService.swift:45-79](Nizi/Features/MemoryDiscovery/Application/TravelClassificationService.swift#L45-L79)).

**Rule chính xác**:
```swift
guard trip.travelContext.overnightCount > 0 else {
    trip.classification = .dayTrip
    return trip   // ← return NGAY, không geocode, không kiểm tra gì khác
}
```
`overnightCount` tính từ `TripDiscoveryEngine.buildTrip` ([:114-120](Nizi/Features/MemoryDiscovery/Domain/TripDiscoveryEngine.swift#L114-L120)): số ngày lịch (calendar day) chênh lệch giữa `startDate` và `endDate` của Trip. Nếu Trip gói gọn trong 1 ngày lịch → `overnightCount == 0` → `.dayTrip` **ngay lập tức**.

### Vì sao Trip có Departure=NO, Return=NO, Countries rỗng, Unknown place vẫn có thể là dayTrip?

Vì điều kiện `.dayTrip` **chỉ đọc đúng một field** (`overnightCount`) — hoàn toàn độc lập với `hasDepartureFromHome`, `hasReturnToHome`, `primaryPlaceName`, `countryCodes`. Khi rơi vào nhánh `.dayTrip`, hàm `return` ngay dòng 52, **không bao giờ chạy tới đoạn geocode** (dòng 55-67) — nên `primaryPlaceName`/`primaryCountryCode`/`countryCodes` giữ nguyên giá trị mặc định từ `TripDiscoveryEngine.buildTrip` (`nil`/`[]`, dòng 158-159, 140 trong TripDiscoveryEngine.swift). Đây không phải bug hiển thị — là **thiết kế cố ý** để tiết kiệm reverse-geocode cho các chuyến trong ngày (comment SPEC § 29 tại dòng 49).

---

## 5. Place / country enrichment

### Reverse geocode chạy ở đâu?

Duy nhất tại `TravelClassificationService.classify`/`resolvePlace` ([TravelClassificationService.swift:81-94](Nizi/Features/MemoryDiscovery/Application/TravelClassificationService.swift#L81-L94)), dùng `ApplePhotoPlaceResolver` (Infrastructure, `CLGeocoder` thật — [ApplePhotoPlaceResolver.swift:12-38](Nizi/Features/PhotoLocation/Infrastructure/ApplePhotoPlaceResolver.swift#L12-L38)).

### Chỉ Diagnostics mới chạy hay persistence đã có?

**Cả hai, cùng một pipeline.** `TravelClassificationService` được gọi từ `DiscoverEventsUseCase.execute()` ([DiscoverEventsUseCase.swift:53](Nizi/Features/MemoryDiscovery/Application/DiscoverEventsUseCase.swift#L53)) — dùng cả trong flow onboarding thật (`FirstExperienceCoordinator`) lẫn trong nút Run của `TripDiscoveryDiagnosticsView` ([TripDiscoveryDiagnosticsView.swift:112-120](Nizi/Features/MemoryDiscovery/Presentation/TripDiscoveryDiagnosticsView.swift#L112-L120), gọi đúng `DiscoverEventsUseCase`). Kết quả **có persist thật** vào `MDPhotoTrip` (bao gồm `travelCountryCodes`, `classification`, `primaryPlaceName` — [MDPhotoTrip.swift:8-32](Nizi/Features/MemoryDiscovery/Infrastructure/MDPhotoTrip.swift#L8-L32)), không phải chỉ hiển thị tạm trong Diagnostics.

### Representative coordinate nào được geocode?

`trip.primaryLatitude/primaryLongitude` — là **điểm xa Home nhất** trong nhóm Event của Trip đó ([TripDiscoveryEngine.swift:122-134](Nizi/Features/MemoryDiscovery/Domain/TripDiscoveryEngine.swift#L122-L134), comment dòng 122-124 giải thích rõ lý do). Không phải điểm đầu, không phải trung bình.

### Failure/cache behavior?

`InMemoryPhotoPlaceCache` ([InMemoryPhotoPlaceCache.swift:11-22](Nizi/Features/PhotoLocation/Infrastructure/InMemoryPhotoPlaceCache.swift#L11-L22)) — **chỉ tồn tại trong bộ nhớ**, không persist. Vì `TravelClassificationService` (và cache của nó) được khởi tạo **mới hoàn toàn** mỗi lần `DiscoverEventsUseCase` được tạo (default parameter, [DiscoverEventsUseCase.swift:30](Nizi/Features/MemoryDiscovery/Application/DiscoverEventsUseCase.swift#L30)) → cache reset mỗi lần Run, không bao giờ "ấm" giữa các lần chạy. Nếu geocode fail (network, `CLGeocoder` lỗi) → log lỗi rồi trả `nil` ([TravelClassificationService.swift:90-92](Nizi/Features/MemoryDiscovery/Application/TravelClassificationService.swift#L90-L92)) → trip rơi vào `.unknown`, `countryCodes` rỗng.

### Vì sao Countries trống?

Hai khả năng, cả hai đều dẫn tới cùng kết quả:
1. Trip được classify `.dayTrip` → geocode **chưa từng chạy** (mục 4) — khả năng cao nhất nếu hầu hết Trip hiện có đều 1-ngày.
2. Trip overnight thật nhưng geocode fail/không có coordinate → `.unknown`, `countryCodes` rỗng.

---

## 6. Diagnostics quality

### Màn hiện tại đang hiển thị gì?

- **`TripDiscoveryDiagnosticsView`**: `.task` chỉ gọi `load()` → `store.fetchTrips()` ([TripDiscoveryDiagnosticsView.swift:99-106](Nizi/Features/MemoryDiscovery/Presentation/TripDiscoveryDiagnosticsView.swift#L99-L106)) — **hiển thị Trip đã persist từ lần discovery gần nhất** (có thể cũ, từ onboarding hoặc lần Run trước), không tự rebuild khi mở màn.
- **`EventBoundaryDiagnosticsView`**: `.task` gọi thẳng `run()` ([EventBoundaryDiagnosticsView.swift:101](Nizi/Features/MemoryDiscovery/Presentation/EventBoundaryDiagnosticsView.swift#L101)) — **luôn tính lại from scratch** mỗi lần mở màn, và **không bao giờ persist** bất cứ gì (không gọi repository nào để save — chỉ gọi `fetchClusterableAssets()` rồi tính thuần trong bộ nhớ, [:108-151](Nizi/Features/MemoryDiscovery/Presentation/EventBoundaryDiagnosticsView.swift#L108-L151)).

### Nút Run có làm gì?

| Màn | rebuild Location Intelligence? | rebuild Home? | rebuild Trips? | classify country? | persist? |
|---|---|---|---|---|---|
| **Trip Discovery Diagnostics** | Có (qua `DiscoverEventsUseCase`) | Có (nhưng luôn tính mới, mục 2) | Có | Có | **Có**, ghi thật vào DB |
| **Event Boundary Diagnostics** | Có (gọi `EventDiscoveryEngine.discover` trực tiếp) | Có (tính mới) | Có (tính, nhưng không hiển thị/dùng ở màn này) | Không | **Không** — chỉ tính để xem, không lưu gì |

Nút "Run" của `TripDiscoveryDiagnosticsView` là **pipeline thật 100%**, giống hệt production. Nút "Run" của `EventBoundaryDiagnosticsView` là **preview thuần túy, không side-effect** trên DB.

---

## 7. Kết luận

### A. Dữ liệu hiện tại thô vì engine thiếu input hay chỉ vì UI chưa enrich?

**Chủ yếu vì thiếu input (GPS trên ảnh) + một lỗ hổng kiến trúc thật (Home không bao giờ được tái sử dụng), không phải vì UI chưa enrich.** UI (`TripDiscoveryDiagnosticsView`) đã gọi đúng pipeline enrich thật (`TravelClassificationService`, có geocode, có persist) — vấn đề nằm ở **input tới engine**: (1) tỷ lệ ảnh có GPS EXIF trong thư viện thật, không kiểm soát được; (2) mục B dưới đây.

### B. Home có đang được sử dụng thật không?

**Không, theo đúng nghĩa "dùng Home đã xác nhận".** Toàn bộ hệ thống — kể cả production `DiscoverEventsUseCase` — luôn tính lại `HomeAnchor` từ đầu mỗi lần `EventDiscoveryEngine.discover()` chạy, không hề đọc `MDHomeAnchor` đã persist/user-confirmed để dùng cho việc tính toán (dù chuyện *lưu trữ* nó đã được bảo vệ đúng cách khỏi bị ghi đè). Đây là gốc rễ hợp lý nhất cho phần lớn Departure/Return = NO và Home-context không ổn định giữa các lần chạy.

### C. Trip Detection có đang tạo quá nhiều one-event trip không?

**Có khả năng cao, và có bằng chứng cấu trúc rõ ràng**: không có ngưỡng số Event tối thiểu, không có ngưỡng khoảng cách/overnight riêng cho việc TẠO Trip (mục 3) — bất kỳ Event `.away` đơn lẻ nào (chỉ cần > 20km khỏi Home tính lại được) đều tự động thành một Trip riêng. Không thể đếm chính xác bao nhiêu % Trip hiện có là one-event chỉ bằng đọc code (Diagnostics hiện không hiển thị `eventIDs.count` dưới dạng có thể lọc/thống kê), nhưng cấu trúc rule cho phép — thậm chí khuyến khích — điều này xảy ra thường xuyên với dữ liệu thưa GPS.

### D. `.dayTrip` có đang bị classify quá dễ không?

**Có, rõ ràng.** Điều kiện duy nhất là `overnightCount == 0` (mục 4) — không cân nhắc số Event, khoảng cách, hay việc có xác định được địa điểm hay không. Một Trip một-Event, không rõ nơi chốn, không rõ có thật sự "rời khỏi nhà" hay không (vì Departure/Return có thể NO do lỗi mục B chứ không phải vì trip không có thật), vẫn nghiễm nhiên là `.dayTrip` hợp lệ.

### E. Phần nào có thể tái sử dụng cho Major Event sau khi sửa?

- `LocationContextResolver` ([LocationContext.swift](Nizi/Features/MemoryDiscovery/Domain/LocationContext.swift)) — logic home/familiar/local/away thuần, tách biệt tốt, chỉ cần được cấp đúng Home thật là dùng lại được ngay.
- `TravelClassificationService` + `PhotoPlaceResolving`/`PhotoPlaceCaching` — pipeline geocode + phân loại quốc gia đã đúng kiến trúc (tách Domain thuần / Application có I/O), chỉ cần cache bền hơn (persist thay vì in-memory) nếu muốn tái dùng ở quy mô lớn hơn.
- `EventDiscoveryEngine.haversineDistanceKm`/`geoCell` — tiện ích khoảng cách thuần, không phụ thuộc gì, dùng lại tự do.
- **Cần sửa trước khi tái sử dụng**: cách `EventDiscoveryEngine.discover`/`DiscoverEventsUseCase` không truyền Home đã persist vào — đây là điểm sẽ lặp lại y hệt vấn đề này ở bất kỳ tính năng "Major Event" nào dựa vào khái niệm Home/Away trong tương lai nếu không sửa tận gốc.
