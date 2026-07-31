# SPRINT — LAZY EVENT PLACE ENRICHMENT

> **Project:** Nizi  
> **Priority:** P1 — Event UX  
> **Scope:** Bổ sung địa danh dễ hiểu cho các `PhotoEvent` đã tồn tại  
> **Dependency:** Event Discovery đã hoạt động và Event đã được persist  
> **Goal:** Mỗi Event có thể hiển thị một địa danh ngắn gọn, dễ hiểu mà không làm chậm initial scan, Event Discovery hoặc First Memory Experience.

---

# 1. Bối cảnh

Nizi hiện đã có Event Discovery và đã tạo được số lượng lớn `PhotoEvent`.

Chất lượng chia Event hiện đã đủ tốt để tiếp tục phát triển UX.

Vấn đề còn lại:

> Event chưa có tên địa danh dễ hiểu.

Trong metadata ảnh đã có GPS ở một phần assets, nhưng nếu reverse-geocode toàn bộ Event ngay sau initial scan sẽ:

- tăng đáng kể thời gian xử lý;
- tạo nhiều geocoding request;
- làm First User Experience chậm;
- không cần thiết vì user có thể chỉ xem một phần nhỏ trong hàng nghìn Event.

Sprint này không thay đổi Event Discovery.

Sprint chỉ làm:

```text
EXISTING PHOTO EVENT
        ↓
representative coordinate
        ↓
lazy reverse geocode
        ↓
display place
        ↓
persistent cache
```

---

# 2. Product Decision

Không enrich địa danh cho toàn bộ Event ngay sau scan.

Sử dụng chiến lược:

> **Lazy + Prefetch + Persistent Cache**

Nghĩa là:

```text
Event được tạo ngay
      ↓
không cần place name
      ↓
Event sắp xuất hiện trên UI
      ↓
resolve place nếu chưa có
      ↓
persist
      ↓
lần sau hiện ngay
```

---

# 3. Mục tiêu UX

Event card nên có dạng:

```text
[ COVER ]

Mỹ An - Đà Nẵng
12 tháng 7, 2025

87 ảnh
```

hoặc:

```text
[ COVER ]

Tokyo - Nhật Bản
18 tháng 4, 2024

126 ảnh
```

Không cần:

- POI chính xác;
- tên khách sạn;
- nhà hàng;
- đường;
- số nhà;
- tọa độ GPS;
- route.

Mục tiêu chỉ là:

> User nhìn Event và ngay lập tức nhớ “mình đang ở đâu”.

---

# 4. Quy ước địa danh

## 4.1 Trong Việt Nam

Ưu tiên:

```text
Phường/Xã - Thành phố
```

Ví dụ:

```text
Mỹ An - Đà Nẵng
Thượng Đình - Hà Nội
Bến Nghé - Hồ Chí Minh
```

Nếu dữ liệu hành chính của Apple không map chính xác theo cách gọi Việt Nam thì formatter phải fallback hợp lý.

Không cố xây database hành chính Việt Nam riêng trong sprint này.

---

# 5. Địa danh nước ngoài

Ưu tiên:

```text
Thành phố - Quốc gia
```

Ví dụ:

```text
Tokyo - Nhật Bản
Kyoto - Nhật Bản
Seoul - Hàn Quốc
Paris - Pháp
```

Không cần district/ward đối với nước ngoài.

---

# 6. Fallback hierarchy

Không assume reverse geocoder luôn trả đủ field.

## Việt Nam

Ưu tiên:

```text
subLocality + locality
```

Nếu thiếu `subLocality`:

```text
locality
```

Nếu thiếu `locality`:

```text
administrativeArea
```

Nếu chỉ có country:

```text
Việt Nam
```

---

## Nước ngoài

Ưu tiên:

```text
locality + country
```

Nếu thiếu locality:

```text
administrativeArea + country
```

Nếu vẫn thiếu:

```text
country
```

---

# 7. Home Country

Formatter cần biết home country để quyết định format.

V1 có thể ưu tiên theo thứ tự:

```text
1. User-confirmed Home country nếu đã có.
2. Locale/region của device nếu Home chưa có.
3. VN nếu project hiện có assumption hợp lý cho test/dev.
```

Không hard-code Việt Nam sâu trong formatter nếu tránh được.

Concept:

```swift
struct PlaceDisplayContext {
    let homeCountryCode: String?
}
```

---

# 8. Không dùng tọa độ trung bình ngây thơ

Một Event có thể có nhiều GPS observations.

Không làm:

```swift
averageLatitude
averageLongitude
```

một cách đơn giản nếu Event trải rộng.

Ví dụ:

```text
50 ảnh Đà Nẵng
10 ảnh Hội An
```

tọa độ trung bình có thể rơi vào một nơi không có ý nghĩa.

Phải chọn:

> **Representative Coordinate**

từ location cluster chính của Event.

---

# 9. Representative Coordinate

Tạo service hoặc reuse clustering hiện có.

Concept:

```swift
protocol EventRepresentativeLocationProviding {
    func representativeCoordinate(
        for event: PhotoEvent
    ) async -> CLLocationCoordinate2D?
}
```

Không bắt buộc tên đúng như trên.

---

# 10. Cách chọn Representative Coordinate

V1:

1. Lấy GPS observations thuộc Event.
2. Group theo location cluster hiện có nếu có thể reuse.
3. Chọn cluster có representation mạnh nhất.
4. Chọn centroid/representative coordinate của cluster đó.

Không cần geocode từng cluster.

Không cần hiểu toàn bộ route.

---

# 11. Dominant Place

Trong sprint này, mỗi Event chỉ cần:

```text
ONE display place
```

Đây là `dominant place`.

Nó không có nghĩa:

> nơi có nhiều ảnh nhất một cách ngây thơ.

Nó có nghĩa:

> địa danh đại diện dễ hiểu nhất cho Event.

V1 dùng representative location cluster để suy ra dominant place.

---

# 12. Không giải quyết Multi-place Event trong V1

Ví dụ Event có:

```text
Đà Nẵng
+
Hội An
```

V1 vẫn có thể hiển thị một dominant place.

Không bắt buộc:

```text
Đà Nẵng · Hội An
```

Multi-place display để sprint sau nếu thực sự cần.

---

# 13. EventPlace Model

Không nhét logic geocoder vào View.

Tạo representation rõ ràng.

Concept:

```swift
struct EventPlace {
    let coordinate: CLLocationCoordinate2D

    let subLocality: String?
    let locality: String?
    let administrativeArea: String?

    let country: String?
    let countryCode: String?

    let displayName: String
}
```

Nếu project đã có `PhotoPlace`, ưu tiên reuse/extend thay vì tạo model duplicate.

---

# 14. Persistence

Kết quả reverse-geocode phải được persist.

Không geocode lại mỗi lần app mở.

Có thể lưu vào Event hoặc relation/cache riêng tùy persistence architecture hiện tại.

Tối thiểu cần:

```text
eventID
representative latitude
representative longitude

subLocality
locality
administrativeArea

country
countryCode

displayName

resolvedAt
```

Không cần persist raw `CLPlacemark`.

---

# 15. Place Resolution State

Event cần biết trạng thái enrichment.

Concept:

```swift
enum EventPlaceResolutionState {
    case unresolved
    case resolving
    case resolved
    case unavailable
}
```

Không nhất thiết persist `.resolving`.

Persist được:

```text
resolved
unavailable
```

nếu phù hợp.

---

# 16. Lazy Resolution

Không chạy:

```text
for event in allEvents {
    reverseGeocode(event)
}
```

sau Event Discovery.

Thay vào đó:

```text
Event Card appears
       ↓
place resolved?
       ↓
YES --------→ display cached
       ↓ NO
enqueue resolution
       ↓
reverse geocode
       ↓
persist
       ↓
UI updates
```

---

# 17. Không chờ click mới bắt đầu

Không chỉ resolve khi user tap vào Event.

Tốt hơn:

> Resolve khi Event sắp xuất hiện trên viewport.

Ví dụ list có 10 Event visible/near-visible:

```text
Event 1   resolve
Event 2   resolve
Event 3   resolve
...
```

Các Event thứ 200 chưa cần làm gì.

---

# 18. Viewport Prefetch

Nếu SwiftUI implementation hiện tại phù hợp:

Có thể trigger qua:

```swift
.task
```

hoặc:

```swift
.onAppear
```

trên Event card.

Nhưng không để mỗi lần cell appear tạo request duplicate.

Service phải deduplicate.

---

# 19. Prefetch Window

Không cần chỉ resolve đúng card visible.

Có thể resolve:

```text
visible
+
một lượng nhỏ next events
```

để khi scroll, place đã sẵn sàng.

Không prefetch hàng trăm Event.

Suggested initial window:

```text
5–15 events
```

Tune sau.

---

# 20. Request Queue

Apple geocoder không nên bị spam request.

Tạo queue có bounded concurrency.

Ví dụ:

```text
1–2 geocoding operations đồng thời
```

Không launch 20 `CLGeocoder` cùng lúc.

Không block main thread.

---

# 21. Deduplication

Nếu nhiều Event có representative coordinate rất gần nhau:

Không nhất thiết reverse-geocode lại.

Tạo coordinate/place cache.

Ví dụ key:

```text
rounded coordinate
```

hoặc location cluster ID nếu có.

Concept:

```text
Event A → Mỹ An
Event B → cùng cluster
Event C → cùng cluster
```

có thể reuse cùng resolved place.

---

# 22. Cache Strategy

Ưu tiên:

```text
LocationCluster ID → Place
```

nếu Event đã dùng cluster system ổn định.

Nếu không:

```text
rounded coordinate → Place
```

Không cần precision GPS cao.

Địa danh ở mức ward/city nên cache theo vùng.

---

# 23. Production Event Card

Trước khi place resolve:

```text
[cover]

12 tháng 7, 2025
87 ảnh
```

Không bắt buộc hiện:

```text
Đang xác định địa điểm...
```

vì dễ tạo cảm giác loading.

Có thể đơn giản để dòng place trống/placeholder nhẹ.

---

# 24. Khi place resolve

Card update:

```text
[cover]

Mỹ An - Đà Nẵng
12 tháng 7, 2025
87 ảnh
```

Transition nhẹ.

Không reload toàn list.

---

# 25. Event Detail

Nếu user tap Event trước khi card resolve xong:

Event Detail phải ưu tiên resolve Event đó ngay.

Priority:

```text
Event Detail current event
>
visible Event cards
>
prefetch events
```

---

# 26. First Memory

Nếu First Memory sử dụng một Event chưa có place:

Place resolver có thể ưu tiên Event đó.

Không bắt First Memory chờ địa danh nếu geocoder chậm.

Flow:

```text
Memory ready
↓
show immediately
↓
place resolves asynchronously
↓
title/subtitle updates
```

Nếu UX hiện tại yêu cầu title có place, có thể chờ rất ngắn nhưng không block toàn pipeline lâu.

---

# 27. Event Discovery không thay đổi

Sprint này tuyệt đối không:

- thay Event boundary;
- rebuild Event logic;
- tune Event score;
- thay Session;
- thay Trip detection.

Event Discovery chỉ cần cung cấp:

```text
event
+
assets / GPS observations
```

Place enrichment là downstream.

---

# 28. Không enrich toàn bộ 1.000+ Event

Ngay cả khi background idle:

V1 không cần tự động geocode toàn bộ library.

Lý do:

- user có thể không bao giờ xem phần lớn Event;
- không cần tốn request;
- tránh kéo dài initial processing;
- local cache sẽ tự hoàn thiện theo usage.

Sau này có thể có idle enrichment riêng.

Không nằm trong sprint này.

---

# 29. Reverse Geocoder Service

Tạo Application/Infrastructure abstraction.

Concept:

```swift
protocol EventPlaceResolving {
    func resolvePlace(
        for event: PhotoEvent
    ) async -> EventPlace?
}
```

Implementation dùng:

```text
Representative Location Provider
+
CLGeocoder
+
Place Formatter
+
Cache
+
Repository
```

---

# 30. Place Formatter

Tách formatting khỏi geocoder.

Concept:

```swift
protocol EventPlaceFormatting {
    func displayName(
        from place: PhotoPlace,
        homeCountryCode: String?
    ) -> String
}
```

Test formatter độc lập.

---

# 31. Việt Nam Formatter

Logic concept:

```text
countryCode == VN
```

Then:

```text
subLocality + " - " + locality
```

Fallback:

```text
locality
administrativeArea
country
```

Không hiển thị duplicate:

```text
Đà Nẵng - Đà Nẵng
```

Nếu `subLocality == locality`, chỉ hiện một lần.

---

# 32. International Formatter

Nếu:

```text
countryCode != homeCountryCode
```

Then:

```text
locality + " - " + country
```

Fallback:

```text
administrativeArea + " - " + country
country
```

Không hiện ward/district nếu không cần.

---

# 33. Localization

Tên country nên ưu tiên representation user-friendly từ geocoder/system locale.

Không xây bảng dịch tên quốc gia riêng nếu Foundation đã cung cấp đủ.

Nếu `CLPlacemark.country` trả localized name phù hợp, dùng nó.

---

# 34. Error Handling

Reverse geocoding có thể fail vì:

- network;
- rate limit;
- coordinate invalid;
- Apple service unavailable.

Không coi là fatal.

Event vẫn hoạt động bình thường.

State:

```text
unresolved / unavailable
```

Retry sau.

---

# 35. Retry

Không retry liên tục.

Có backoff hoặc chỉ retry khi:

- Event xuất hiện lại;
- user mở Event Detail;
- app session sau.

Không tạo request loop.

---

# 36. No GPS Event

Nếu Event không có bất kỳ GPS usable:

```text
place = unavailable
```

UI chỉ hiện:

```text
date
photo count
```

Không đoán địa danh từ EXIF khác nếu chưa có infrastructure.

---

# 37. Sparse GPS

Nếu chỉ một số ảnh có GPS:

vẫn dùng được.

Ví dụ:

```text
100 photos
12 photos with GPS
```

Nếu 12 GPS observations tạo cluster đủ rõ:

resolve place.

Không yêu cầu 100% ảnh có GPS.

---

# 38. Privacy

Toàn bộ GPS/Event location:

```text
local-first
```

Không upload.

Reverse geocoding sử dụng system geocoder theo implementation hiện có.

Không thêm backend.

---

# 39. Diagnostics

DEBUG có thể thêm:

```text
Event Place

Event ID
GPS assets: 124 / 187
Dominant cluster: ...
Representative coordinate: ...
Resolution: resolved

subLocality: Mỹ An
locality: Đà Nẵng
country: Việt Nam

Display:
Mỹ An - Đà Nẵng
```

Không cần tạo Diagnostics lớn.

Có thể thêm vào Event Detail diagnostics hiện tại.

---

# 40. Metrics / Logging

DEBUG logging:

```text
event_place_requested
event_place_cache_hit
event_place_geocode_started
event_place_resolved
event_place_failed
```

Có thể log Event ID.

Không log raw GPS vào remote analytics.

---

# 41. Tests

Tạo unit tests tối thiểu cho formatter:

### VN full data

```text
subLocality = Mỹ An
locality = Đà Nẵng
countryCode = VN

Expected:
Mỹ An - Đà Nẵng
```

### VN missing ward

```text
locality = Đà Nẵng

Expected:
Đà Nẵng
```

### International

```text
locality = Tokyo
country = Nhật Bản

Expected:
Tokyo - Nhật Bản
```

### International missing city

```text
administrativeArea = Kyoto
country = Nhật Bản

Expected:
Kyoto - Nhật Bản
```

### Duplicate names

Không tạo:

```text
Đà Nẵng - Đà Nẵng
```

### No location

Return nil/unavailable cleanly.

---

# 42. Performance Tests

Test với Event list lớn:

```text
1,000–2,000 Events
```

Expected:

- list mở nhanh;
- không geocode toàn bộ;
- chỉ visible/prefetch window enqueue;
- scroll không freeze;
- request queue bounded;
- cached Event hiện place ngay;
- Event không có place vẫn usable.

---

# 43. Acceptance Criteria

## AC-01

Existing Event không cần rebuild để sử dụng sprint này.

## AC-02

Event list mở mà không chờ reverse geocoding toàn library.

## AC-03

Event visible được lazy resolve place.

## AC-04

Không reverse-geocode từng photo.

## AC-05

Mỗi Event V1 chỉ cần một representative/dominant place.

## AC-06

Trong Việt Nam hiển thị ưu tiên:

```text
Phường/Xã - Thành phố
```

## AC-07

Nước ngoài hiển thị ưu tiên:

```text
Thành phố - Quốc gia
```

## AC-08

Place được persist/cache.

## AC-09

Event đã resolve không geocode lại ở lần mở sau.

## AC-10

Event Detail được priority nếu chưa resolve.

## AC-11

Geocoder failure không ảnh hưởng Event UX chính.

## AC-12

No-GPS Event vẫn hiển thị bình thường.

## AC-13

Initial Scan không chậm thêm vì task này.

## AC-14

Event Discovery không chậm thêm đáng kể.

## AC-15

Không có backend mới.

---

# 44. Không làm trong Sprint này

Explicitly out of scope:

- geocode toàn bộ Event sau scan;
- POI detection;
- restaurant/hotel naming;
- street address;
- route reconstruction;
- multi-place Event display;
- Trip location enrichment;
- Event boundary changes;
- Home Detector;
- Home Candidate UX;
- AI naming;
- semantic place recognition;
- server geocoding;
- map redesign;
- Event clustering redesign.

---

# 45. Claude Code — khảo sát trước khi sửa

Đọc implementation thật của:

```text
PhotoEvent
Event persistence model
Event repository

EventListView
EventCardView
EventDetailView

IndexedAsset
PhotoSession

PhotoLocationService
PhotoLocationRepository
PhotoLocationClusterer
PhotoPlace

LocationIntelligenceEngine

PhotoKit / GPS metadata access

FirstMemoryView
MemoryViewerView
```

Ưu tiên reuse:

```text
PhotoPlace
location cluster
reverse geocoder
repository
```

Không tạo hệ location thứ hai nếu project đã có abstraction tương đương.

---

# 46. Implementation Order

```text
STEP 1
Audit existing Event + PhotoLocation models.

STEP 2
Add representative location provider for existing Event.

STEP 3
Implement Event Place Formatter.

STEP 4
Add persistent place cache / Event enrichment fields.

STEP 5
Implement bounded EventPlaceResolver queue.

STEP 6
Wire lazy resolution to visible Event cards.

STEP 7
Add small viewport prefetch.

STEP 8
Give Event Detail high-priority resolution.

STEP 9
Wire place into First Memory where appropriate.

STEP 10
Add formatter + cache tests.

STEP 11
Test with real 1,000+ Event library.
```

---

# 47. Definition of Done

Test trên thư viện Event hiện có:

```text
1. Open Event list.
2. List appears immediately.
3. No bulk geocoding starts.
4. Visible Event cards begin receiving place names.
5. VN Event displays e.g.:
   Mỹ An - Đà Nẵng
6. International Event displays e.g.:
   Tokyo - Nhật Bản
7. Scroll down.
8. Newly visible Events resolve progressively.
9. Scroll back.
10. Previously resolved places appear immediately.
11. Close app.
12. Relaunch.
13. Previously resolved places remain available without geocoding again.
14. Open unresolved Event Detail.
15. Its place is prioritized.
16. No-GPS Event still works.
17. Initial Scan and Event Discovery behavior remain unchanged.
```

---

# 48. Product Principle

Nizi không cần hoàn thiện metadata của toàn bộ thư viện trước khi user có thể sử dụng app.

Event phải có trước.

Địa danh được bổ sung khi có giá trị cho user.

```text
DISCOVER FAST
     ↓
SHOW IMMEDIATELY
     ↓
ENRICH WHEN NEEDED
     ↓
CACHE FOREVER
```

Đây cũng nên là nguyên tắc chung cho các enrichment tốn thời gian khác của Nizi sau này.
