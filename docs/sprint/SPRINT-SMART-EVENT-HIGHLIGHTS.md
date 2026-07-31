# SPRINT — SMART EVENT HIGHLIGHTS

## 1. Mục tiêu

Nâng cấp cơ chế tự chọn ảnh của Event để:

1. Giảm mạnh ảnh trùng / gần giống nhau.
2. Loại những ảnh có chất lượng quá kém khỏi auto-selection.
3. Ưu tiên ảnh Favorite của user.
4. Giữ được sự đa dạng của Event thay vì chọn nhiều ảnh cùng một cảnh.
5. Không làm mất lựa chọn thủ công của user khi thuật toán chạy lại.
6. Có Diagnostics trực quan để developer đánh giá kết quả trên thư viện ảnh thật.

Không thay đổi Event Discovery.

Không thay đổi cách chia Event.

Không thay đổi PhotoSession.

Không sử dụng Cloud AI.

Không tạo Memory entity mới.

Không thay đổi flow:

Event → Love → Home Memories.

Curation vẫn chạy lazy khi Event được mở lần đầu.

---

# 2. Bối cảnh implementation hiện tại

Survey đã xác nhận flow:

EventDetailView.task
    ↓
runCurationIfNeeded()
    ↓
EventPhotoCurationService.curate()
    ↓
VisionEventPhotoAnalyzer
    ↓
EventPhotoCurationEngine
    ↓
EventCurationResult
    ↓
SwiftData

Nếu cache hợp lệ thì Event mở lần sau không chạy Vision lại.

Current cache validity dựa trên:

- status
- algorithmVersion
- sourceAssetCount

Current algorithmVersion:

    1

---

# 3. Các vấn đề đã xác nhận

## 3.1 Near duplicate phạm vi quá hẹp

Current:

    same PhotoSession
    AND
    time gap <= 60 seconds
    AND
    featurePrintDistance <= 0.3

mới được coi là near duplicate.

Do đó:

- ảnh giống nhau cách nhau >60s không được so sánh;
- ảnh giống nhau thuộc session khác không được so sánh;
- nhiều ảnh cùng cảnh vẫn có thể cùng được selected.

Ngoài ra cluster hiện chỉ so với representative đầu tiên và representative không update.

---

## 3.2 Quality filtering quá mềm

Hard exclusion hiện chỉ có:

    screenshot
    document

Các signal:

    sharpness
    exposure
    faceScore

chỉ tham gia composite score.

Do đó một ảnh chất lượng kém vẫn có thể được chọn nếu nó là ảnh tốt nhất trong cluster.

---

## 3.3 Favorite chưa đủ mạnh

Favorite hiện chỉ đóng góp:

    +0.15

vào composite score.

Favorite:

- không được force select;
- không được bảo vệ khi global trim;
- có thể thua một ảnh gần giống khác.

---

## 3.4 Không có global visual diversity

Feature print hiện chỉ dùng trong local near-duplicate clustering.

Không có bước:

    candidate A selected
    candidate B visually very similar
    → suppress B

ở cấp toàn Event.

---

## 3.5 Manual selection có thể bị mất

Khi recurate:

    saveResult()
        ↓
    clearResult()
        ↓
    recreate groups/items

`userAdded` / `userRemoved` không được merge lại.

Đây là blocker phải sửa TRƯỚC khi bump algorithmVersion.

---

# 4. Nguyên tắc kiến trúc

Không viết lại pipeline.

Giữ:

    FILTER
       ↓
    LOCAL GROUPING
       ↓
    LOCAL REPRESENTATIVE
       ↓
    GLOBAL DEDUP
       ↓
    BALANCE / DIVERSITY
       ↓
    RESULT

Cụ thể:

Event Photos
      ↓
Vision Analysis
      ↓
Local Near-Duplicate Clusters
      ↓
Best Representative
      ↓
Global Duplicate Suppression
      ↓
Quality / Favorite / Diversity
      ↓
Event Highlights

---

# 5. PHASE A — Preserve User Selection

Đây là việc PHẢI làm đầu tiên.

## 5.1 Trước khi replace result

Khi recurate Event, đọc result hiện tại.

Tạo hai tập:

    userAddedAssetIDs
    userRemovedAssetIDs

dựa trên:

    selectionSource == .userAdded
    selectionSource == .userRemoved

---

# 6. Merge sau recuration

Sau khi algorithm tạo result mới:

Nếu assetID nằm trong:

    userAddedAssetIDs

thì:

    isSelected = true
    selectionSource = .userAdded

Nếu assetID nằm trong:

    userRemovedAssetIDs

thì:

    isSelected = false
    selectionSource = .userRemoved

Algorithm không được override explicit user choice.

---

# 7. Asset không còn trong Event

Nếu một asset:

    userAdded

nhưng không còn thuộc Event:

không cần preserve nó trong EventCurationResult mới.

Không tạo orphan item.

---

# 8. Acceptance — Manual Selection

Test:

Event curate:

    A selected
    B selected
    C not selected

User:

    remove A
    add C

Sau recurate:

    A remains unselected / userRemoved
    C remains selected / userAdded

bất kể algorithm mới đề xuất gì.

---

# 9. PHASE B — Fix Cache Identity

Current cache validity chỉ so:

    sourceAssetCount

Điều này không đủ.

Ví dụ:

Old:

    A B C D

New:

    A B C E

count vẫn = 4.

Cache hiện vẫn valid.

---

# 10. Source Asset Fingerprint

Thêm deterministic fingerprint cho tập asset của Event.

Ví dụ:

    sourceAssetFingerprint

Tạo từ:

    sorted(assetIDs)

Không phụ thuộc thứ tự.

Có thể hash thành String.

Ví dụ conceptual:

    SHA256(sorted IDs joined)

Không yêu cầu cryptographic security.

Chỉ cần deterministic và collision risk đủ thấp.

---

# 11. Cache validity mới

Cache valid khi:

    status == completed
    AND
    algorithmVersion == current
    AND
    sourceAssetFingerprint == currentFingerprint

Có thể giữ `sourceAssetCount` cho diagnostics nhưng không dùng nó làm identity duy nhất.

---

# 12. PHASE C — Curation Diagnostics

Trước khi tune thuật toán, cần nhìn được engine đang làm gì.

Thêm:

    CurationDiagnosticsView

vào Diagnostics Hub hiện tại.

Không đưa vào production navigation chính.

---

# 13. Event picker trong Diagnostics

Diagnostics hiển thị danh sách Event:

    date
    photo count
    selected count
    location nếu có

Tap Event:

    Curation Diagnostics Detail

---

# 14. Diagnostics Detail

Hiển thị tất cả ảnh của Event.

Mỗi ảnh cần thấy tối thiểu:

    thumbnail

    creationDate
    sessionID
    similarityClusterID

    sharpness
    exposure
    faceScore
    favorite
    compositeScore

    isScreenshot
    isDocument

    isSuggested
    isSelected
    selectionSource

---

# 15. Visual states

Diagnostics cần phân biệt trực quan:

    SELECTED
    REJECTED
    USER ADDED
    USER REMOVED
    FAVORITE

Không cần UI đẹp.

Ưu tiên khả năng debug.

---

# 16. Rejection reason

Nếu có thể derive rõ ràng, hiển thị:

    Screenshot
    Document
    Low Quality
    Near Duplicate
    Global Duplicate
    Trimmed
    User Removed

Không cần xây rule engine phức tạp.

Có thể bổ sung lightweight diagnostic reason vào curation result nếu cần.

---

# 17. Cluster inspection

Cho phép nhìn:

    Cluster #12
        photo A ← selected
        photo B
        photo C

Điều này đặc biệt quan trọng để tune near duplicate.

---

# 18. PHASE D — Quality Gate

Không thay thế composite score.

Composite score vẫn dùng để ranking.

Nhưng thêm bước:

    usability / quality gate

trước auto-selection.

---

# 19. Hard reject philosophy

Không được aggressive.

Mục tiêu:

> Chỉ loại những ảnh rõ ràng không nên được Nizi tự chọn.

Không cố định nghĩa "ảnh đẹp".

---

# 20. Hard reject candidates

Bắt đầu với:

    screenshot
    document

đã có.

Bổ sung:

    extremely blurred
    extremely bad exposure

Không hard reject dựa trên faceScore.

Ảnh phong cảnh hoặc ảnh không có người vẫn hoàn toàn hợp lệ.

---

# 21. Threshold

Không tự đặt threshold cực đoan.

Đưa threshold vào config:

    minimumUsableSharpness
    minimumUsableExposure

Các threshold phải dễ tune từ Diagnostics.

Không hard-code rải rác.

---

# 22. Favorite exception

Favorite của user là strong signal.

Nếu ảnh Favorite bị:

    moderately blurred
    moderately underexposed

không nên hard reject dễ dàng.

Nhưng Favorite KHÔNG override:

    screenshot
    document

và không nhất thiết override ảnh hỏng hoàn toàn.

Thiết kế rule rõ ràng.

---

# 23. PHASE E — Improve Local Duplicate Grouping

Không chuyển local clustering thành O(n²).

Giữ mục tiêu performance:

    approximately O(n)

---

# 24. Representative update

Khảo sát hiện tại representative của cluster cố định ở ảnh đầu tiên.

Thay đổi để giảm cluster drift problem.

Có thể dùng một trong hai cách:

### Option A

Compare với ảnh gần nhất trong cluster.

### Option B

Update representative khi có candidate tốt hơn / gần trung tâm hơn.

Ưu tiên implementation đơn giản.

Không xây centroid feature vector nếu Vision API không hỗ trợ thuận tiện.

---

# 25. Time window

Current:

    60 seconds

Không đơn giản tăng thành một con số rất lớn.

Local clustering vẫn có nhiệm vụ:

> burst / same moment.

Có thể tune:

    60–120 seconds

sau khi xem Diagnostics.

Không dùng local clustering để giải quyết duplicate toàn Event.

---

# 26. Session boundary

Local clustering có thể vẫn giữ session boundary.

Không cần phá PhotoSession architecture.

Duplicate xuyên session sẽ được xử lý ở Global Dedup Pass.

---

# 27. PHASE F — Global Duplicate Suppression

Đây là thay đổi chính.

Sau local selection, ta đã giảm:

    Event Photos
        ↓
    Local Representatives

Ví dụ:

    300 photos
        ↓
    45 candidates

Chỉ lúc này mới chạy global visual dedup.

---

# 28. Global candidate set

Global pass chỉ chạy trên:

    auto-selected candidate representatives

Không chạy trên toàn bộ source photos.

Không chạy all-pairs trên 300–500 ảnh.

---

# 29. Global visual comparison

Sử dụng feature print đã có.

Mục tiêu:

Nếu:

    Candidate A
    Candidate B

rất giống nhau dù:

    khác session
    hoặc
    cách nhau >60 seconds

thì chỉ giữ representative tốt hơn.

---

# 30. Global threshold

Tách config:

    localNearDuplicateThreshold
    globalSimilarityThreshold

Không giả định hai threshold phải giống nhau.

Global suppression nên conservative hơn.

Mục tiêu là:

    obvious visual redundancy

không phải:

    cùng chủ đề = duplicate.

Ví dụ:

Hai ảnh biển khác nhau:

    KHÔNG nhất thiết duplicate.

Hai ảnh cùng người, cùng pose, cùng background:

    có thể duplicate.

Tune bằng Diagnostics.

---

# 31. Không cần global O(n²) lớn

Candidate count sau local grouping nhỏ.

Nếu candidate count khoảng:

    20–60

thì pairwise comparison có thể chấp nhận được.

Nhưng phải có safety cap.

Ví dụ:

    maxGlobalCandidates

Nếu Event cực lớn:

- chỉ lấy top candidate pool;
- hoặc dùng streaming representative comparison.

Không để pathological Event làm UI freeze.

---

# 32. Global representative selection

Khi hai candidate bị coi là duplicate:

ưu tiên theo thứ tự:

    explicit user selection
        ↓
    Favorite
        ↓
    composite quality
        ↓
    deterministic tie breaker

User choice không được global dedup override.

---

# 33. PHASE G — Favorite Priority

Không biến Favorite thành:

    always selected no matter what.

Nhưng Favorite phải mạnh hơn hiện tại.

---

# 34. Favorite behavior

Nếu Favorite:

    passes usability gate
    AND
    không bị userRemoved

thì nên được ưu tiên rất cao.

Trong duplicate cluster:

    Favorite vs non-Favorite
        ↓
    prefer Favorite

trừ khi Favorite có chất lượng rõ ràng kém hơn đáng kể.

---

# 35. Multiple Favorites gần giống nhau

Nếu user Favorite cả 5 ảnh gần giống:

Không nhất thiết auto-select cả 5.

Có thể:

    select best Favorite representative

Các Favorite còn lại vẫn tồn tại trong Event và user có thể thêm lại.

Không thay đổi `PHAsset.isFavorite`.

---

# 36. Global trim

Favorite usable không nên là những ảnh đầu tiên bị trim.

Khi `balanceAcrossEvent` cần giảm số ảnh:

ưu tiên giữ:

    userAdded
    Favorite
    high quality
    diversity representatives

---

# 37. PHASE H — Lightweight Diversity

Không xây AI storytelling.

Không dùng location trong sprint này.

Chỉ cần tránh kết quả quá tập trung.

---

# 38. Temporal diversity

Event dài nhiều giờ/ngày không nên chỉ chọn ảnh ở một đoạn.

Sau global dedup, chia Event thành lightweight temporal buckets.

Ví dụ dựa trên:

    day
    hoặc
    normalized event timeline

Không cần tạo domain model mới.

---

# 39. Diversity principle

Nếu cần trim:

không chỉ:

    sort all by score
    remove lowest

Thay vào đó:

    preserve reasonable temporal coverage
    then optimize quality

Không ép quota cứng nếu bucket chỉ chứa ảnh xấu.

Quality gate vẫn có quyền loại toàn bộ bucket.

---

# 40. Không dùng Location Diversity trong sprint này

Location enrichment đang là một concern riêng.

Không coupling:

    reverse geocode
    location clustering

vào Curation Engine trong sprint này.

Có thể làm sau nếu thực tế cần.

---

# 41. Selection count

Giữ targetRange hiện tại trong sprint này:

    <50       → 8...20
    50..<150  → 15...30
    150..<300 → 20...40
    >=300     → 30...60

Không tune selection count đồng thời với duplicate/quality nếu chưa cần.

Tránh thay quá nhiều biến cùng lúc.

---

# 42. Manual selection luôn thắng

Invariant:

    USER DECISION > ALGORITHM

Nếu:

    selectionSource == userAdded

algorithm không được bỏ.

Nếu:

    selectionSource == userRemoved

algorithm không được thêm lại.

Áp dụng cho:

    quality gate
    duplicate suppression
    global balancing
    future algorithm versions

---

# 43. Vision Analysis Cache — chưa làm

Survey xác nhận hiện mỗi lần recurate:

    toàn bộ Event
        ↓
    3 Vision requests/photo
        ↓
    analyze lại từ đầu

Trong sprint này KHÔNG xây persistent Vision cache theo asset.

Ghi TODO.

Lý do:

Scope chính hiện tại là chất lượng selection.

Nếu performance thực tế trở thành vấn đề sau algorithm V2, làm sprint riêng:

    ASSET ANALYSIS CACHE

---

# 44. Progress UI

Giữ EventDetailView hiện tại.

Không redesign.

Nếu dễ thực hiện, đổi progress từ:

    Processed X/Y groups

thành wording phù hợp hơn:

    Đang chọn những khoảnh khắc đẹp...
    43 / 120

nhưng không bắt buộc.

Không để scope UI làm chậm sprint.

---

# 45. Algorithm Version

KHÔNG bump algorithmVersion ngay đầu sprint.

Thứ tự bắt buộc:

    Preserve manual selection
        ↓
    Cache fingerprint
        ↓
    Diagnostics
        ↓
    New algorithm
        ↓
    Tests
        ↓
    bump algorithmVersion

Sau khi tất cả hoàn tất:

    algorithmVersion = 2

---

# 46. Migration behavior

Không cần chạy batch recuration toàn thư viện.

Sau bump:

Event được mở:

    old algorithmVersion
        ↓
    cache invalid
        ↓
    lazy recurate V2
        ↓
    preserve user overrides
        ↓
    save V2 result

Event chưa mở:

    giữ cache V1

Không chạy background recuration 1.700+ Event.

---

# 47. Testing — User Overrides

Test:

    algorithm V1 result
    userAdded A
    userRemoved B
    algorithmVersion V2
    recurate

Expected:

    A selected/userAdded
    B unselected/userRemoved

---

# 48. Testing — Asset Fingerprint

Test:

Old:

    A B C

New:

    A B D

Expected:

    cache invalid

dù:

    sourceAssetCount == 3

---

# 49. Testing — Local Duplicate

Test burst:

    A
    A'
    A''
    A'''

gần thời gian và visually similar.

Expected:

    1 representative

hoặc tối đa runner-up theo existing large-burst policy.

---

# 50. Testing — Cross-session Duplicate

Test:

Session 1:
    A

Session 2:
    A'

visually near-identical.

Expected:

    global dedup chỉ giữ 1 auto-selected representative.

---

# 51. Testing — Time-separated Duplicate

Test:

    A at 10:00
    A' at 10:05

cùng visual scene.

Expected:

Local grouping có thể không merge.

Global suppression phải phát hiện redundancy.

---

# 52. Testing — Different scene

Test:

    beach portrait A
    beach portrait B

cùng người nhưng:

    pose khác
    composition khác
    background/camera angle khác đáng kể

Expected:

Không được aggressive merge nếu feature distance không đủ gần.

---

# 53. Testing — Low Quality

Test:

    severely blurred image

Expected:

    auto-selection false

nhưng ảnh vẫn:

    tồn tại trong Event
    có thể xem trong All Photos
    user có thể manual add nếu UI cho phép.

---

# 54. Testing — Favorite

Test cluster:

    A quality 0.85 non-favorite
    B quality 0.80 favorite

Expected:

Ưu tiên B nếu quality difference nằm trong acceptable range.

Không hard-code behavior chỉ dựa vào ví dụ này;
test theo rule thực tế được implement.

---

# 55. Testing — Favorite bad photo

Favorite:

    screenshot

Expected:

Không auto-select.

Favorite:

    extremely unusable image

Expected:

Không bắt buộc auto-select.

---

# 56. Testing — Temporal Diversity

Event 3 ngày:

    Day 1: rất nhiều candidate score cao
    Day 2: một số candidate usable
    Day 3: một số candidate usable

Nếu cần global trim:

Expected:

Không trim gần như toàn bộ Day 2/Day 3 chỉ vì Day 1 score cao hơn một chút.

---

# 57. Diagnostics acceptance

Developer phải có khả năng chọn một Event thật và trả lời:

    Vì sao ảnh này được chọn?

    Vì sao ảnh này bị bỏ?

    Ảnh này thuộc duplicate cluster nào?

    Ảnh nào thắng cluster?

    Favorite có được ưu tiên không?

    Score của ảnh là bao nhiêu?

Nếu Diagnostics chưa trả lời được các câu này thì chưa đủ.

---

# 58. Real-library tuning workflow

Sau khi implementation xong:

KHÔNG tune dựa trên synthetic tests בלבד.

Chọn tối thiểu:

    3–5 Event thực tế

bao gồm:

1. Event nhiều ảnh burst.
2. Event kéo dài nhiều ngày.
3. Event có nhiều Favorite.
4. Event có ảnh tối/mờ.
5. Event có ảnh cùng cảnh cách nhau vài phút.

Dùng Diagnostics để đánh giá.

---

# 59. Không tối ưu theo một Event duy nhất

Không thay threshold chỉ vì một Event cụ thể.

Mỗi threshold adjustment phải kiểm tra lại trên toàn bộ sample set.

---

# 60. Metrics cần ghi trong Diagnostics/log

Cho mỗi Event:

    source photo count
    usable photo count
    local cluster count
    local selected count
    global duplicate suppressed count
    final selected count
    favorite source count
    favorite selected count
    user override count

Không cần analytics/backend.

Chỉ local diagnostics.

---

# 61. Performance guardrails

Curation vẫn phải:

    lazy
    local
    bounded

Không:

    upload ảnh
    gọi API
    chạy Cloud AI

Global similarity pass không được chạy trên toàn bộ library.

Chỉ trong một Event đang curate.

---

# 62. Không làm trong sprint

Không:

- thay Event Discovery;
- thay Session Discovery;
- reverse geocode;
- Location Diversity;
- Auto Memory;
- Memory scoring;
- Album generation;
- backend;
- Cloud AI;
- persistent Vision analysis cache;
- face recognition;
- person clustering;
- semantic image understanding;
- aesthetic ML model;
- rebuild toàn bộ Event;
- recurate toàn library.

---

# 63. Implementation order bắt buộc

Thực hiện theo thứ tự:

### Step 1
Preserve `userAdded/userRemoved`.

### Step 2
Asset fingerprint cache validity.

### Step 3
Curation Diagnostics.

### Step 4
Quality Gate.

### Step 5
Improve local near-duplicate clustering.

### Step 6
Global duplicate suppression.

### Step 7
Favorite priority.

### Step 8
Temporal diversity.

### Step 9
Tests.

### Step 10
Bump:

    algorithmVersion 1 → 2

### Step 11
Test trên thư viện thật qua Diagnostics.

Không đảo Step 10 lên trước Step 1.

---

# 64. Definition of Done

Sprint hoàn thành khi:

- Manual user selections survive recuration.
- Cache invalid khi tập asset thay đổi dù count bằng nhau.
- Có Curation Diagnostics.
- Screenshot/document vẫn bị loại khỏi auto-selection.
- Ảnh cực mờ/cực exposure xấu không còn dễ lọt.
- Burst gần giống được giảm tốt.
- Near-duplicate khác session hoặc >60s được suppress ở global pass.
- Favorite usable được ưu tiên rõ hơn.
- Global trim không chỉ dựa thuần quality score.
- Event nhiều ngày giữ được temporal diversity hợp lý.
- Không làm mất ảnh khỏi Event.
- User vẫn có thể xem toàn bộ ảnh.
- Không thay Event Discovery.
- Không Cloud AI.
- Curation vẫn lazy khi mở Event.
- Algorithm V2 chỉ recurate Event khi cần.
- Build succeeds.
- Existing tests pass.
- New tests pass.

---

# 65. Product invariant

Điều quan trọng nhất:

> Curation không quyết định ảnh nào tồn tại trong Event.

Nó chỉ quyết định:

> Những ảnh nào Nizi đề xuất là những khoảnh khắc nổi bật.

Luôn giữ:

    Event
    ├── All Photos
    └── Highlights

Nếu Nizi chọn sai:

    user sửa được.

Và sau khi user đã sửa:

    Nizi không được tự ý ghi đè quyết định đó.