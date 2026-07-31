
# SURVEY-2 — KẾT QUẢ KHẢO SÁT: EVENT PHOTO CURATION / HIGHLIGHT SELECTION

Khảo sát thuần đọc code, không sửa gì. Tất cả câu trả lời dưới đây trích trực tiếp từ implementation hiện tại (không suy đoán). Đường dẫn file kèm số dòng để tiện đối chiếu.

---

## 1. Khi nào Curation thực sự chạy?

```text
EventDetailView.body.task   (Nizi/Features/MemoryDiscovery/Presentation/EventDetailView.swift:124-135)
        ↓
runCurationIfNeeded()       (EventDetailView.swift:405-417)
        ↓
runCuration(forceRecurate:) (EventDetailView.swift:419-444)
        ↓
EventPhotoCurationService.curate(event:forceRecurate:onProgress:)
        (Nizi/Features/MemoryDiscovery/Application/EventPhotoCurationService.swift:38-79)
```

Đúng là **`.task`**, không phải `.onAppear`. Không có nút bấm để "chạy curation lần đầu" — nó tự khởi động ngay khi `EventDetailView` xuất hiện. Nút bấm duy nhất liên quan là **"Thử lại" ở trạng thái lỗi** (`errorState`, [EventDetailView.swift:271-273](Nizi/Features/MemoryDiscovery/Presentation/EventDetailView.swift#L271-L273)), gọi `runCuration(forceRecurate: true)`.

Không có coordinator riêng cho việc này — `EventDetailView` tự khởi tạo `EventPhotoCurationService` tại chỗ ([EventDetailView.swift:424-430](Nizi/Features/MemoryDiscovery/Presentation/EventDetailView.swift#L424-L430)).

Một đường trigger thứ hai tồn tại độc lập: `FirstExperienceCoordinator.curateAndBuild` ([FirstExperienceCoordinator.swift:191-206](Nizi/Features/MemoryDiscovery/Application/FirstExperienceCoordinator.swift#L191-L206)) — chạy trong luồng "First Memory Experience" (Scan→Discover→Score→Curate→Build), gọi cùng `EventPhotoCurationService.curate(forceRecurate: false)` cho tối đa 3 event điểm cao nhất.

---

## 2. Lần thứ hai mở Event

Có **hai lớp cache-check**, không phải một:

1. `EventDetailView.runCurationIfNeeded()` ([EventDetailView.swift:405-417](Nizi/Features/MemoryDiscovery/Presentation/EventDetailView.swift#L405-L417)): đọc thẳng `store.result(for: event.id)` từ SwiftData. Nếu `status == .completed && algorithmVersion == current && sourceAssetCount == event.assetIDs.count` → dùng luôn, **không gọi `runCuration` chút nào**.
2. `EventPhotoCurationService.isValid(_:for:)` ([EventPhotoCurationService.swift:81-85](Nizi/Features/MemoryDiscovery/Application/EventPhotoCurationService.swift#L81-L85)) lặp lại đúng 3 điều kiện y hệt — phòng trường hợp `runCuration` bị gọi trực tiếp (ví dụ từ `FirstExperienceCoordinator`).

Nếu cache hợp lệ: **không chạy Vision lại**, không fetch asset/session lại. Thumbnail lưới (`gridThumbnail`, 160×160) vẫn luôn được load — nhưng đó là hiển thị UI, không liên quan Vision/curation.

Bảng điều kiện, đúng như khảo sát nêu:

| Field                | Thay đổi → hệ quả |
|---|---|
| `algorithmVersion`   | khác constant hiện tại → invalid → recurate toàn bộ |
| `sourceAssetCount`   | khác `event.assetIDs.count` → invalid → recurate toàn bộ |
| `status`             | phải đúng `.completed`; `.failed`/`.processing`/`.notStarted` đều invalid → recurate |

⚠️ **Lỗ hổng phát hiện được**: điều kiện chỉ so **count**, không so **tập asset ID**. Nếu Event mất 1 ảnh và có thêm đúng 1 ảnh khác (net count không đổi), cache vẫn được coi là hợp lệ và **không** recurate — dù nội dung ảnh đã đổi hoàn toàn.

---

## 3. Pipeline đầy đủ (từ code thật)

```text
PhotoEvent
    ↓
assetRepository.fetchAssets(ids: event.assetIDs)      [SwiftDataMemoryDiscoveryStore.fetchAssets, :101]
    ↓
sessionRepository.fetchSessions(ids: event.sessionIDs) [SwiftDataMemoryDiscoveryStore.fetchSessions, :180]
    ↓
VisionEventPhotoAnalyzer.analyze(assets:sessions:)     [:47-66]
    │   for each PhotoSession (sorted by startDate):
    │     analyzeSession():
    │       ├─ Vision + pixel analysis mỗi ảnh, bounded concurrency=2  (→ PhotoQualityMetrics, featurePrint, isDocument)
    │       └─ streaming near-duplicate clustering theo thời gian     (→ similarityClusterID)
    ↓
[AnalyzedPhoto] — đã có sẵn score + cluster id + isScreenshot/isDocument (KHÔNG có bước "Grouping"/"Scoring" tách riêng sau đó — đã tính xong ở Infrastructure)
    ↓
EventPhotoCurationEngine.curate() [Domain, pure]           [:36-81]
    ├─ sort theo creationDate, bucket theo sessionID
    ├─ splitIntoMoments (gap ≤ 60s)                → tạo PhotoCurationGroup ("moment")
    ├─ selectWithinGroup (mỗi similarityClusterID → chọn 1, có thể +1 nếu burst lớn)  [:107-143]
    └─ balanceAcrossEvent (trim toàn Event nếu vượt ceiling)                          [:159-188]
    ↓
EventCurationResult (status=.completed, groups=[...])
    ↓
curationRepository.saveResult(result) → SwiftData (MDEventCurationResult/MDPhotoCurationGroup/MDPhotoCurationItem)
```

**Khác với assumption trong khảo sát**: thứ tự thật không phải `Vision → Grouping → Scoring → Selection` tách bạch. `Scoring` (compositeScore) và bước "grouping theo near-duplicate" (`similarityClusterID`) **đều xảy ra trong cùng một bước Vision analysis** (Infrastructure), *trước khi* Domain layer chạy. Domain chỉ còn: nhóm theo thời gian (moment) → chọn đại diện mỗi cluster (dùng score đã tính sẵn) → cân bằng toàn event.

---

## 4. Class/service liên quan — vị trí thật

| Tên | File |
|---|---|
| `EventPhotoCurationService` | [Application/EventPhotoCurationService.swift](Nizi/Features/MemoryDiscovery/Application/EventPhotoCurationService.swift) |
| `EventPhotoCurationEngine` | [Domain/EventPhotoCurationEngine.swift](Nizi/Features/MemoryDiscovery/Domain/EventPhotoCurationEngine.swift) |
| `EventPhotoAnalyzer` (protocol) | [Domain/EventPhotoAnalyzer.swift](Nizi/Features/MemoryDiscovery/Domain/EventPhotoAnalyzer.swift) |
| `VisionEventPhotoAnalyzer` (impl) | [Infrastructure/VisionEventPhotoAnalyzer.swift](Nizi/Features/MemoryDiscovery/Infrastructure/VisionEventPhotoAnalyzer.swift) |
| `PhotoQualityMetrics` / `AnalyzedPhoto` | [Domain/PhotoQualityMetrics.swift](Nizi/Features/MemoryDiscovery/Domain/PhotoQualityMetrics.swift) |
| `PhotoCurationGroup` | [Domain/PhotoCurationGroup.swift](Nizi/Features/MemoryDiscovery/Domain/PhotoCurationGroup.swift) |
| `PhotoCurationItem` | [Domain/PhotoCurationItem.swift](Nizi/Features/MemoryDiscovery/Domain/PhotoCurationItem.swift) |
| `EventCurationResult` | [Domain/EventCurationResult.swift](Nizi/Features/MemoryDiscovery/Domain/EventCurationResult.swift) |
| `EventCurationRepository` (protocol) | [Domain/EventCurationRepository.swift](Nizi/Features/MemoryDiscovery/Domain/EventCurationRepository.swift) |
| `MDEventCurationResult`/`MDPhotoCurationGroup`/`MDPhotoCurationItem` | [Infrastructure/MDEventCurationResult.swift](Nizi/Features/MemoryDiscovery/Infrastructure/MDEventCurationResult.swift) |
| `SwiftDataMemoryDiscoveryStore` (impl repo) | [Infrastructure/SwiftDataMemoryDiscoveryStore.swift:312-438](Nizi/Features/MemoryDiscovery/Infrastructure/SwiftDataMemoryDiscoveryStore.swift#L312-L438) |
| `ImagePixelAnalyzer` (sharpness/exposure) | [Infrastructure/ImagePixelAnalyzer.swift](Nizi/Features/MemoryDiscovery/Infrastructure/ImagePixelAnalyzer.swift) |
| `SelectionSource` | [Domain/SelectionSource.swift](Nizi/Features/MemoryDiscovery/Domain/SelectionSource.swift) |
| `CurationStatus` | [Domain/CurationStatus.swift](Nizi/Features/MemoryDiscovery/Domain/CurationStatus.swift) |
| `EventDetailView` (trigger + UI) | [Presentation/EventDetailView.swift](Nizi/Features/MemoryDiscovery/Presentation/EventDetailView.swift) |
| `MemorySelectionEditView` (edit sau khi đã curate) | [Presentation/MemorySelectionEditView.swift](Nizi/Features/MemoryDiscovery/Presentation/MemorySelectionEditView.swift) |
| `MemoryBuilder` (Curation → MemoryCandidate) | [Application/MemoryBuilder.swift](Nizi/Features/MemoryDiscovery/Application/MemoryBuilder.swift) |
| `FirstExperienceCoordinator` (đường trigger thứ 2) | [Application/FirstExperienceCoordinator.swift](Nizi/Features/MemoryDiscovery/Application/FirstExperienceCoordinator.swift) |

Không có diagnostics view riêng cho Curation (xem mục 29).

---

## 5. FILTER — app hiện loại những ảnh nào?

Chỉ có **2 rule loại hẳn (hard exclusion)**, còn lại **toàn bộ là trừ điểm mềm (soft penalty)**:

| Signal | Threshold | Loại hẳn hay chỉ trừ điểm? |
|---|---|---|
| Screenshot (`PHAsset.mediaSubtypes.contains(.photoScreenshot)`) | boolean | **Loại hẳn** khỏi selection ([EventPhotoCurationEngine.swift:116](Nizi/Features/MemoryDiscovery/Domain/EventPhotoCurationEngine.swift#L116)) — vẫn hiện trong lưới, chỉ không tự chọn |
| Document/whiteboard/receipt (`VNDetectDocumentSegmentationRequest`) | confidence ≥ 0.6 **và** area fraction ≥ 0.5 ([VisionEventPhotoAnalyzer.swift:184-189](Nizi/Features/MemoryDiscovery/Infrastructure/VisionEventPhotoAnalyzer.swift#L184-L189)) | **Loại hẳn** khỏi selection, cùng dòng 116 |
| Blur/sharpness thấp | không có threshold reject | Chỉ trừ điểm, trọng số 0.35 |
| Exposure xấu (quá tối/quá sáng) | không có threshold reject | Chỉ trừ điểm, trọng số 0.25 |
| Face quality kém | không có threshold reject | Chỉ trừ điểm, trọng số 0.25 |
| Tiny image / generic screen-capture (không phải PHAsset screenshot) / QR | **không tồn tại rule riêng** | Không xử lý |

Điểm mấu chốt: `lowQualityFloor = 0.25` ([EventPhotoCurationEngine.swift:16](Nizi/Features/MemoryDiscovery/Domain/EventPhotoCurationEngine.swift#L16)) là ngưỡng loại duy nhất dựa trên chất lượng, và nó áp dụng **sau khi đã chọn ảnh tốt nhất trong cluster** — không phải một bộ lọc trước khi xếp hạng. Vì `faceScore` mặc định trung tính 0.5 khi không có mặt người, một ảnh không có mặt người chỉ cần sharpness/exposure tầm trung là dễ dàng vượt 0.25.

---

## 6. Favorite photo

`IndexedAsset.isFavorite` → `PhotoQualityMetrics.isFavorite` → đúng **một chỗ dùng duy nhất**:

```swift
// PhotoQualityMetrics.swift:23-27
let favoriteBonus = isFavorite ? 1.0 : 0.0
let raw = 0.35 * sharpness + 0.25 * exposure + 0.25 * faceScore + 0.15 * favoriteBonus
```

→ **+0.15 flat weight** vào compositeScore. Không có gì khác:
- Không force-selected tuyệt đối.
- Không có ưu tiên riêng khi chọn đại diện cluster (chỉ là 1 phần của compositeScore để so sánh).
- Không được bảo vệ khi `balanceAcrossEvent` trim toàn Event (trim sort thuần theo `qualityScore` cuối cùng, favorite đã "chìm" vào con số đó, không có cờ "đừng trim ảnh favorite").
- Nếu ảnh favorite đồng thời là screenshot/document → **vẫn bị loại hẳn**, favorite không override rule loại ở mục 5.

---

## 7. Duplicate / Near-Duplicate

**Có** — visual grouping thật, dùng đúng `VNFeaturePrintObservation` ([VisionEventPhotoAnalyzer.swift:93-122](Nizi/Features/MemoryDiscovery/Infrastructure/VisionEventPhotoAnalyzer.swift#L93-L122)).

- Threshold: `nearDuplicateDistanceThreshold: Float = 0.3` ([:22](Nizi/Features/MemoryDiscovery/Infrastructure/VisionEventPhotoAnalyzer.swift#L22))
- Time gap: **có kết hợp**, `nearDuplicateMaxTimeGapSeconds: TimeInterval = 60` ([:27](Nizi/Features/MemoryDiscovery/Infrastructure/VisionEventPhotoAnalyzer.swift#L27))
- Rule đúng như ví dụ khảo sát: `gap ≤ 60s` **và** `featurePrintDistance ≤ 0.3` → cùng cluster ([:102-110](Nizi/Features/MemoryDiscovery/Infrastructure/VisionEventPhotoAnalyzer.swift#L102-L110))

**Caveat quan trọng phát hiện được**: thuật toán chỉ so mỗi ảnh với `clusterRepresentative` — tức feature print của ảnh **đầu tiên** mở ra cluster hiện tại, không phải ảnh liền trước, và representative **không bao giờ được cập nhật** khi cluster mở rộng ([:118](Nizi/Features/MemoryDiscovery/Infrastructure/VisionEventPhotoAnalyzer.swift#L118) chỉ set trong nhánh else — tạo cluster mới). Đây là đánh đổi có chủ đích để đạt O(n) thay vì O(n²) (xem mục 27), nhưng nghĩa là một burst có sự trôi dạt hình ảnh dần dần (đổi góc máy/zoom nhẹ) có thể bị tách cluster sớm dù ảnh liền kề vẫn rất giống nhau.

Đồng thời, near-dup clustering **chỉ hoạt động trong phạm vi 1 PhotoSession** — hai ảnh giống nhau ở hai session khác nhau (hoặc cùng session nhưng cách nhau >60s) **không bao giờ được so sánh**.

---

## 8. Burst / Same Moment

`PhotoSession` **không** được dùng trực tiếp làm proxy "same moment" cho selection — nó chỉ là ranh giới fetch/phân tích thô. "Same moment" thật sự dùng cho *chọn ảnh* là `similarityClusterID` (near-dup); "moment" dùng cho *hiển thị lưới* là `PhotoCurationGroup` (gap ≤ 60s, cố ý tách biệt và chặt hơn session gap — comment tại [EventPhotoCurationEngine.swift:25-31](Nizi/Features/MemoryDiscovery/Domain/EventPhotoCurationEngine.swift#L25-L31)).

Với ví dụ "15 ảnh trong 2 phút": engine **có giới hạn**, không phải "không giới hạn" —
- Mỗi `similarityClusterID` → 1 ảnh mặc định.
- +1 ảnh runner-up **chỉ khi**: cluster size > 5 (`largeBurstSize`), điểm runner-up cách top ≤ 0.15, và cách nhau về thời gian ≥ 8s ([EventPhotoCurationEngine.swift:121-127](Nizi/Features/MemoryDiscovery/Domain/EventPhotoCurationEngine.swift#L121-L127)).
- Engine **không bao giờ** chọn >2 ảnh cho cùng một `similarityClusterID`.

→ Nếu người dùng thấy "15 ảnh gần giống vẫn chọn nhiều hơn 2", nguyên nhân **bắt buộc** phải là: Vision clustering đã chia 15 ảnh đó thành >2 cluster riêng biệt (do threshold/caveat ở mục 7), chứ không phải do rule chọn-trong-cluster nới lỏng.

---

## 9. PhotoCurationGroup được tạo như thế nào?

Là **combination**: bucket theo `sessionID` trước, rồi chia nhỏ tiếp theo thời gian (`splitIntoMoments`, gap ≤ `momentGroupMaxGapSeconds` = 60s) — [EventPhotoCurationEngine.swift:44-66](Nizi/Features/MemoryDiscovery/Domain/EventPhotoCurationEngine.swift#L44-L66). Đây **không phải** near-duplicate cluster và **không phải** visual cluster — nó là "moment" thuần thời gian, chỉ để hiển thị section trong UI. Near-duplicate cluster nằm ở tầng mịn hơn, là field `similarityClusterID` bên trong từng `PhotoCurationItem`, cố ý **không** làm thành card UI lồng nhau riêng (comment tại [PhotoCurationGroup.swift:14-15](Nizi/Features/MemoryDiscovery/Domain/PhotoCurationGroup.swift#L14-L15)).

---

## 10. Chọn bao nhiêu ảnh trong mỗi group?

Không có rule "1 ảnh/group", "2 ảnh/group" hay "% group size" ở cấp `PhotoCurationGroup`. Rule thật nằm ở cấp `similarityClusterID` bên trong group: 1 mặc định, tối đa +1 nếu điều kiện burst-lớn ở mục 8 thỏa. Vì vậy **nếu một group có 10 ảnh gần giống vẫn được chọn nhiều ảnh**, nguyên nhân từ code chỉ có thể là: Vision đã coi 10 ảnh đó là **nhiều `similarityClusterID` khác nhau** (không merge được), mỗi cluster tự chọn ảnh đại diện riêng — không phải vì selection logic cho phép chọn nhiều trong cùng 1 cluster.

---

## 11. Beauty / Quality Score

Formula đầy đủ ([PhotoQualityMetrics.swift:23-27](Nizi/Features/MemoryDiscovery/Domain/PhotoQualityMetrics.swift#L23-L27)):

```text
compositeScore = clamp(
    0.35 * sharpness
  + 0.25 * exposure
  + 0.25 * faceScore
  + 0.15 * (isFavorite ? 1.0 : 0.0),
  0, 1
)
```

Không có term "face count" (chỉ dùng khuôn mặt lớn nhất, xem mục 12), không có term "document penalty" trong công thức (document xử lý bằng loại-hẳn ở tầng khác, không trừ điểm), không có "technical quality" tách riêng ngoài sharpness+exposure.

---

## 12. Face Detection

`VisionEventPhotoAnalyzer.faceScore(from:)` ([:199-213](Nizi/Features/MemoryDiscovery/Infrastructure/VisionEventPhotoAnalyzer.swift#L199-L213)):

- Chỉ lấy khuôn mặt có **bounding box lớn nhất**, bỏ qua hoàn toàn các mặt còn lại — **face count không ảnh hưởng score theo bất kỳ hướng nào** (nhiều mặt không tăng điểm, cũng không giảm).
- `faceScore = 0.4 * sizeScore + 0.2 * centeringScore + 0.4 * eyeOpennessScore`
  - `sizeScore = min(area * 6, 1.0)`
  - `centeringScore = max(1 - 2 * distanceFromCenter, 0)`
  - `eyeOpennessScore`: xấp xỉ qua tỉ lệ khẩu độ landmark mắt, **không bao giờ loại bỏ tuyệt đối** ảnh nhắm mắt (comment [:217](Nizi/Features/MemoryDiscovery/Infrastructure/VisionEventPhotoAnalyzer.swift#L217)).
- Không có mặt → `faceScore = 0.5` trung tính, không bị phạt (ảnh phong cảnh không nên bị coi là lỗi).
- **Không xử lý riêng**: group photo (nhiều mặt), very small faces (ngoài việc `sizeScore` tự nhiên giảm), partial face.

→ Một ảnh nhóm đông người, ai cũng rõ mặt nhưng mỗi mặt nhỏ so với khung hình, sẽ bị `sizeScore` thấp dù là ảnh "tốt" theo trực giác người dùng.

---

## 13. Sharpness

`ImagePixelAnalyzer.laplacianVarianceScore` ([:46-68](Nizi/Features/MemoryDiscovery/Infrastructure/ImagePixelAnalyzer.swift#L46-L68)) — **pixel variance kiểu Laplacian** (giống `cv2.Laplacian(...).var()` của OpenCV), tính trên buffer grayscale 120×120 downsample từ thumbnail 256×256. Không phải Core Image, không phải Vision, không phải custom ML model.

- `score = min(variance / 400.0, 1.0)` — liên tục 0...1.
- **Không có threshold loại**, chỉ penalize liên tục, trọng số 0.35 (lớn nhất trong công thức).

---

## 14. Exposure

`ImagePixelAnalyzer.exposureScore` ([:70-75](Nizi/Features/MemoryDiscovery/Infrastructure/ImagePixelAnalyzer.swift#L70-L75)) — **chỉ brightness trung bình**, khoảng cách tới mid-gray (128):

```text
score = max(1 - |mean - 128| / 128, 0)
```

Không dùng histogram, không dùng clipped-highlights, không dùng shadow-detail riêng. **Không có ảnh nào bị hard reject** vì tối/sáng — chỉ giảm điểm liên tục (trọng số 0.25).

---

## 15. Document Detection

Xác nhận: dùng đúng `VNDetectDocumentSegmentationRequest` ([VisionEventPhotoAnalyzer.swift:160, 164](Nizi/Features/MemoryDiscovery/Infrastructure/VisionEventPhotoAnalyzer.swift#L160)), rule tại `isDocument(from:config:)` ([:184-189](Nizi/Features/MemoryDiscovery/Infrastructure/VisionEventPhotoAnalyzer.swift#L184-L189)): confidence ≥ 0.6 **và** diện tích bounding box ≥ 50% khung hình. Nếu `true` → **loại hẳn** khỏi selection (không phải trừ điểm) tại [EventPhotoCurationEngine.swift:116](Nizi/Features/MemoryDiscovery/Domain/EventPhotoCurationEngine.swift#L116).

---

## 16. Screenshot

Từ `PHAsset.mediaSubtypes.contains(.photoScreenshot)` ([PhotoKitAssetProvider.swift:308](Nizi/Features/MemoryDiscovery/Infrastructure/PhotoKitAssetProvider.swift#L308)) — **PHAsset mediaSubtype, không phải Vision**.

Có loại khỏi curation: đúng, hard exclusion tại `selectWithinGroup` ([EventPhotoCurationEngine.swift:116](Nizi/Features/MemoryDiscovery/Domain/EventPhotoCurationEngine.swift#L116)).

**Nếu screenshot vẫn xuất hiện trong selected photos**, code chỉ ra 2 khả năng (không phải do rule loại bị hỏng):
1. **User đã tự chọn tay** — `toggleSelection`/`MemorySelectionEditView.toggle` cho phép chọn bất kỳ item nào, kể cả screenshot, với `selectionSource = .userAdded` ([EventDetailView.swift:481-505](Nizi/Features/MemoryDiscovery/Presentation/EventDetailView.swift#L481-L505)) — hoàn toàn hợp lệ theo thiết kế.
2. **Cache cũ chưa từng được recompute** — nếu rule loại screenshot này được thêm sau một số Event đã có `EventCurationResult` cũ, kết quả cũ vẫn được coi hợp lệ trừ khi `algorithmVersion`/`sourceAssetCount` đổi (mục 2, 24) — không có cơ chế nào tự động áp rule mới lên cache đã lưu.

---

## 17. Feature Print

Feature print (`VNGenerateImageFeaturePrintRequest`) **chỉ được dùng để group duplicates** ([VisionEventPhotoAnalyzer.swift:93-122](Nizi/Features/MemoryDiscovery/Infrastructure/VisionEventPhotoAnalyzer.swift#L93-L122)).

- **Không** dùng để score quality — không xuất hiện trong `PhotoQualityMetrics.compositeScore`.
- **Không** dùng cho diversity selection ngoài phạm vi "1 đại diện/cluster" (xem mục 18) — không có bước riêng "đảm bảo đa dạng hình ảnh" dùng feature print giữa các cluster khác nhau.

→ Đây là câu trả lời trực tiếp: feature print được tính và dùng cho *một* mục đích (gom near-duplicate trong cùng session/thời gian), chứ **chưa tận dụng đầy đủ** cho quality hay cho diversity toàn Event.

---

## 18. Diversity

**Không có** cơ chế diversity nào ngoài "1 đại diện mỗi `similarityClusterID`" — và cluster đó tự nó đã bị giới hạn phạm vi trong 1 session + gap ≤ 60s (mục 7).

- Không có Maximal Marginal Relevance.
- Không có similarity penalty giữa các cluster khác nhau.
- Không có "one-per-cluster" áp dụng toàn Event — chỉ trong phạm vi hẹp của near-dup clustering.
- Không có temporal diversity ở bước chọn-trong-cluster (xem mục 19 cho tầng global).

Ví dụ khảo sát nêu ("Beach photo A" đã chọn, "Beach photo B" giống ở xa hơn có bị phạt không): **Không** — nếu B cách A hơn 60s hoặc khác session, hai ảnh này **không bao giờ được so sánh với nhau**, B được chọn hoàn toàn độc lập dựa trên score riêng của cluster nó thuộc về. Đây là nguyên nhân code-verified rõ ràng nhất cho vấn đề "ảnh gần giống nhau vẫn được chọn nhiều" khi các ảnh đó cách nhau > 1 phút.

---

## 19. Temporal Coverage

Engine **không** chủ động giữ chỗ cho đầu/giữa/cuối Event. Việc chọn-trong-cluster diễn ra độc lập theo từng cluster (không cạnh tranh điểm số giữa các group/ngày khác nhau) — nên về nguyên tắc mỗi ngày/group vẫn có đại diện riêng.

Rủi ro thật nằm ở bước cuối: `balanceAcrossEvent` ([EventPhotoCurationEngine.swift:159-188](Nizi/Features/MemoryDiscovery/Domain/EventPhotoCurationEngine.swift#L159-L188)) — chỉ kích hoạt khi tổng số ảnh đã chọn vượt `ceiling = targetRange.upperBound × 1.5`, và khi đó trim thuần theo **global score ascending**, không có floor theo ngày/group (chỉ có 1 bảo vệ: không trim group về 0). Với ví dụ Event 3 ngày (Day 1: 100 ảnh đẹp, Day 2: 20, Day 3: 30) và tổng selection vượt ceiling: **có nguy cơ thật** là ảnh Day 2/3 (điểm thấp hơn tương đối) bị trim trước, dồn kết quả cuối cùng nghiêng về Day 1.

---

## 20. Location Diversity

**Không dùng** — grep xác nhận không có tham chiếu `latitude`/`longitude` nào trong `EventPhotoCurationEngine`, `VisionEventPhotoAnalyzer`, hay `PhotoQualityMetrics`/`AnalyzedPhoto`. `IndexedAsset` có `latitude`/`longitude` và `PhotoSession` có `centerLatitude`/`centerLongitude`, nhưng cả hai field này **không bao giờ được đọc** trong toàn bộ pipeline curation. Location hoàn toàn không tham gia — không có cơ chế "mỗi place một đại diện".

---

## 21. Target selection count

`EventPhotoCurationEngine.targetRange(forSourceAssetCount:)` ([:147-154](Nizi/Features/MemoryDiscovery/Domain/EventPhotoCurationEngine.swift#L147-L154)):

| sourceAssetCount | targetRange | ceiling (×1.5 upperBound) |
|---|---|---|
| < 50 | 8...20 | 30 |
| 50..<150 | 15...30 | 45 |
| 150..<300 | 20...40 | 60 |
| ≥ 300 | 30...60 | 90 |

**Quan trọng**: đây chỉ là ngưỡng **soft ceiling** dùng để trim khi vượt quá — engine **không chủ động ép** số lượng chọn về range này (comment rõ: "never force-adds when under the reference range"). Event 20 ảnh có thể ra 3 ảnh chọn nếu chỉ có 3 cluster đạt điểm, không hề bị "ép" lên 8.

---

## 22. Minimum / maximum selection

Không tồn tại field tên `minimumSelected`/`maximumSelected`/`selectionRatio`. Cái gần nhất là `targetRange()` ở mục 21 — chỉ dùng để tính ceiling trim, không có floor ép tối thiểu.

Tồn tại một ngưỡng khác, ở tầng khác: `FirstExperienceCoordinator.minimumSelectedPhotoCount = 3` ([:34](Nizi/Features/MemoryDiscovery/Application/FirstExperienceCoordinator.swift#L34)) — đây là điều kiện để một Event **được đề xuất làm First Memory**, không phải tham số của curation engine; kết quả curation của Event đó (kể cả dưới 3 ảnh) vẫn được lưu và hiển thị bình thường trong `EventDetailView`.

---

## 23. Manual User Selection

`toggleSelection` ([EventDetailView.swift:481-505](Nizi/Features/MemoryDiscovery/Presentation/EventDetailView.swift#L481-L505)) và `MemorySelectionEditView.toggle` ([:64-80](Nizi/Features/MemoryDiscovery/Presentation/MemorySelectionEditView.swift#L64-L80)) set `selectionSource` (`.userAdded`/`.userRemoved`, hoặc `.systemSuggested` nếu toggle về khớp `isSuggested` — chỉ trong `EventDetailView`, `MemorySelectionEditView` không có logic khớp lại này, một khác biệt nhỏ giữa 2 nơi) và lưu ngay qua `curationRepository.updateItemSelection(itemID:isSelected:source:)` ([EventCurationRepository.swift:18](Nizi/Features/MemoryDiscovery/Domain/EventCurationRepository.swift#L18)) — update từng item riêng lẻ, độc lập với một lần curate.

**🔴 Phát hiện quan trọng nhất của khảo sát này**: khi curation chạy lại (algorithm version đổi, hoặc asset count đổi — chính là kịch bản mục 25 hỏi), `saveResult()` ([SwiftDataMemoryDiscoveryStore.swift:368-391](Nizi/Features/MemoryDiscovery/Infrastructure/SwiftDataMemoryDiscoveryStore.swift#L368-L391)) gọi `clearResult()` xoá sạch toàn bộ `MDPhotoCurationGroup`/`MDPhotoCurationItem` cũ rồi tạo mới hoàn toàn từ kết quả thuật toán. **Không có bước merge/carry-forward `userAdded`/`userRemoved` nào cả** — mọi lựa chọn thủ công của người dùng cho Event đó **bị xoá âm thầm** ngay khi cache invalid.

Điều này mâu thuẫn trực tiếp với comment tại [EventCurationRepository.swift:12-14](Nizi/Features/MemoryDiscovery/Domain/EventCurationRepository.swift#L12-L14) ("never touches a result the user has since edited... never re-curated") — comment đó chỉ đúng **khi cache còn valid**; ngay khi invalid (đúng lúc bump `algorithmVersion` để cải thiện thuật toán), toàn bộ chỉnh sửa tay bị mất.

---

## 24. Curation invalidation

Điều kiện invalidate giống hệt mục 2: `status`, `algorithmVersion`, `sourceAssetCount`. Nếu bất kỳ field nào lệch → **toàn bộ analysis chạy lại**, không có incremental. `EventPhotoCurationService.curate` luôn fetch **toàn bộ** `event.assetIDs` và `event.sessionIDs` ([:52-53](Nizi/Features/MemoryDiscovery/Application/EventPhotoCurationService.swift#L52-L53)), truyền hết vào `analyzer.analyze` — không có khái niệm "chỉ ảnh mới". Chỉ thêm 1 ảnh vào Event → Vision chạy lại **trên toàn bộ ảnh** trong Event, không phải chỉ ảnh mới đó.

---

## 25. Algorithm Version

`EventPhotoCurationService.algorithmVersion = 1` ([:19](Nizi/Features/MemoryDiscovery/Application/EventPhotoCurationService.swift#L19)) — hằng số static, global cho toàn app.

Xác nhận: **chỉ cần bump số này lên** → mọi Event đang có cache sẽ bị coi invalid ở lần mở tiếp theo → tự động recurate (lazy, không rebuild hàng loạt ngay lập tức, chỉ khi từng Event được mở lại hoặc `FirstExperienceCoordinator` chạy tới nó). Nhưng như mục 23 chỉ ra: **bump version đồng nghĩa xoá sạch mọi chỉnh sửa tay đã có** trên mọi Event — cần cân nhắc trước khi bump trong lần tối ưu thuật toán tới.

---

## 26. Vision cost

Xác nhận đúng survey trước:
- Thumbnail 256×256 (`config.thumbnailSize`, [VisionEventPhotoAnalyzer.swift:19](Nizi/Features/MemoryDiscovery/Infrastructure/VisionEventPhotoAnalyzer.swift#L19))
- Face landmarks (`VNDetectFaceLandmarksRequest`)
- Feature print (`VNGenerateImageFeaturePrintRequest`)
- Document segmentation (`VNDetectDocumentSegmentationRequest`)
- Sharpness/exposure — **không phải Vision**, CPU thuần qua `ImagePixelAnalyzer`
- Concurrency tối đa 2 (`maxConcurrentAnalyses`, [:20](Nizi/Features/MemoryDiscovery/Infrastructure/VisionEventPhotoAnalyzer.swift#L20)), enforce thủ công bằng seed+refill task group ([:73-91](Nizi/Features/MemoryDiscovery/Infrastructure/VisionEventPhotoAnalyzer.swift#L73-L91))

**Mỗi photo**: đúng 3 Vision request (chạy chung 1 `VNImageRequestHandler.perform([...])`, [:158-164](Nizi/Features/MemoryDiscovery/Infrastructure/VisionEventPhotoAnalyzer.swift#L158-L164)) + 1 pass CPU (Laplacian + brightness) trên cùng 1 thumbnail.

**Reuse**: **không** — không có cache Vision-result theo asset ở cấp nào cả. Mỗi lần recurate (dù chỉ vì thêm 1 ảnh), toàn bộ ảnh trong Event được phân tích Vision lại từ đầu.

---

## 27. Performance khi mở Event lần đầu

- Vision phân tích: **O(n)** request (3 Vision call/ảnh, concurrency cố định 2) — thời gian chạy tỉ lệ tuyến tính với số ảnh, chia cho 2.
- Near-duplicate clustering: **O(n) mỗi session** — xác nhận bằng chính comment thiết kế ([VisionEventPhotoAnalyzer.swift:14-16](Nizi/Features/MemoryDiscovery/Infrastructure/VisionEventPhotoAnalyzer.swift#L14-L16): "O(n) per session, not O(n²)") — mỗi ảnh chỉ so với 1 representative cố định của cluster hiện tại, **không so từng ảnh với từng ảnh**.
- `EventPhotoCurationEngine` (Domain): sort + dictionary grouping, khoảng O(n log n).

→ **Không có O(n²) nào trong pipeline hiện tại.** Đây chính là cái giá phải trả cho việc bỏ qua so sánh toàn cặp (all-pairs) — lý do trực tiếp gây ra giới hạn ở mục 7/18 (duplicate cách xa nhau về thời gian/session không được phát hiện). Event 20/100/500 ảnh: thời gian chủ yếu do độ trễ Vision request × n / 2, không có điểm nghẽn thuật toán bậc hai.

---

## 28. UI Progress

`EventDetailView.curationContent` switch theo `curationStatus` ([:222-245](Nizi/Features/MemoryDiscovery/Presentation/EventDetailView.swift#L222-L245)):

- `.processing` → `processingState` ([:247-260](Nizi/Features/MemoryDiscovery/Presentation/EventDetailView.swift#L247-L260)): nếu `progress` đã có giá trị, hiện text "Processed X/Y groups" + `ProgressView(value:total:)` xác định (determinate); trước khi session đầu tiên xong, `progress` còn `nil` → chỉ hiện spinner vô định (`ProgressView()` không tham số).
- Progress được cập nhật theo **session hoàn thành** (không phải theo từng ảnh) — `onProgress(index+1, orderedSessions.count)` ([VisionEventPhotoAnalyzer.swift:62](Nizi/Features/MemoryDiscovery/Infrastructure/VisionEventPhotoAnalyzer.swift#L62)) → khá thô nếu Event chỉ có 1-2 session lớn.
- **Không có skeleton**, **không có "ảnh xuất hiện dần"** — khi `curate()` xong, toàn bộ `curationResult.groups` render một lượt qua `ForEach` ([:230-240](Nizi/Features/MemoryDiscovery/Presentation/EventDetailView.swift#L230-L240)).
- **Không block toàn UI** — cover ảnh, thông tin Event, timeline session vẫn hiện ngay từ đầu (các section khác không phụ thuộc `curationStatus`); chỉ vùng "ảnh đã chọn" chờ.

---

## 29. Curation Diagnostics

**Không có.** Xác nhận bằng grep toàn bộ `Presentation/`: không màn hình nào hiển thị `qualityScore`/`compositeScore` cho từng ảnh, không có danh sách "rejected + lý do", không hiển thị `similarityClusterID`/duplicate group cho người dùng hay dev xem. Chỉ có vài dòng `NiziLogger.discovery` log nội bộ (ví dụ `preview_open_rejected` — về việc mở preview, không liên quan lý do curation).

Đáng chú ý: các subsystem khác trong cùng `MemoryDiscovery` **đều có** diagnostics view riêng — `EventBoundaryDiagnosticsView`, `HomeDetectionDiagnosticsView`, `TripDiscoveryDiagnosticsView`, `EventDiscoveryDebugListView`, `PhotoLibraryDiagnosticsView`. Photo Curation là subsystem duy nhất **thiếu** đối trọng này — trớ trêu thay, đây chính là phần cần debug nhất theo yêu cầu của khảo sát này.

---

## 30. Phân tích 3 lỗi chính (dựa trên code)

### A. Ảnh gần giống vẫn được chọn nhiều

Nguyên nhân chính: **clustering under-merge**, không phải "chọn nhiều trong 1 cluster":

1. Near-dup clustering chỉ hoạt động trong **1 session** và **≤60s** ([VisionEventPhotoAnalyzer.swift:27](Nizi/Features/MemoryDiscovery/Infrastructure/VisionEventPhotoAnalyzer.swift#L27)) — ảnh giống nhau cách xa hơn (khác moment, khác session) **không bao giờ được so sánh**, mỗi ảnh thành cluster riêng, mỗi cluster tự chọn 1 đại diện (mục 18).
2. So sánh chỉ với representative **cố định** của cluster (không update khi mở rộng, mục 7) — burst trôi dạt dần dễ bị tách cluster sớm dù mắt thường vẫn thấy giống nhau.
3. `nearDuplicateDistanceThreshold = 0.3` tự nhận là "starting point, chưa tune trên thư viện thật" ([:21](Nizi/Features/MemoryDiscovery/Infrastructure/VisionEventPhotoAnalyzer.swift#L21)) — có thể đơn giản là quá chặt.
4. Feature print **chưa được dùng** cho diversity toàn Event (mục 17/18) — chỉ dùng cục bộ trong 1 session/60s.

Rule chọn-nhiều-trong-cluster (burst runner-up, mục 8) là yếu tố phụ, chỉ cộng thêm tối đa 1 ảnh mỗi cluster lớn — không phải nguyên nhân chính.

### B. Ảnh không đáng chọn vẫn lọt

Nguyên nhân chính: **không có hard reject dựa trên chất lượng** — chỉ có 2 exclusion tuyệt đối (screenshot, document), còn sharpness/exposure/face đều là **penalty cộng dồn liên tục**, không bao giờ loại tuyệt đối một ảnh xấu (mục 5, 13, 14). `lowQualityFloor = 0.25` là ngưỡng duy nhất và khá thấp so với cấu trúc công thức (ảnh không có mặt người đã mặc định có 0.125 điểm từ `faceScore` trung tính). Vì selection là "rank rồi chọn nhất trong cluster" chứ không phải "filter trước rồi mới rank", một cluster chỉ có 1 ảnh xấu vẫn được chọn miễn nó vượt 0.25. Không có "minimum quota" hay "forced coverage" nào can thiệp thêm ở đây — nguyên nhân thuần là thiếu absolute quality gate.

### C. Ảnh quan trọng bị bỏ

Ba nguyên nhân code-verified:

1. **Favorite weight thấp và không được bảo vệ**: chỉ +0.15 flat, dễ bị đè bởi sharpness+exposure+face (0.85 tổng) của một ảnh gần-trùng khác trong cùng cluster; không có carve-out bảo vệ favorite khi `balanceAcrossEvent` trim toàn Event (mục 6, 19).
2. **Không có forced coverage theo temporal/location** — nếu tổng selection vượt ceiling, trim thuần theo global score, có nguy cơ dồn về ngày/nhóm điểm cao, bỏ bớt ngày/nhóm điểm thấp hơn dù có ảnh quan trọng (mục 19).
3. **Group representative có thể chọn sai** nếu ảnh quan trọng bị Vision phân loại nhầm thành document (ngưỡng 0.5 diện tích khung hình khá dễ đạt với một số bố cục — ví dụ ảnh có mặt bàn/sách chiếm nửa khung hình) — khi đó bị loại hẳn bất kể favorite hay score cao thế nào (mục 15).

Target count thấp (mục 21) không phải nguyên nhân trực tiếp vì range chỉ là soft ceiling, không ép giảm khi chưa vượt ngưỡng.

---

## 31. Map vào 4 tầng kiến trúc

| Layer | Hiện đã có? | Implementation | Điểm yếu |
|---|---|---|---|
| **Filter** | Một phần | Chỉ 2 hard rule: screenshot (PHAsset subtype), document (`VNDetectDocumentSegmentationRequest`) — [EventPhotoCurationEngine.swift:116](Nizi/Features/MemoryDiscovery/Domain/EventPhotoCurationEngine.swift#L116) | Không có hard reject cho blur/exposure/face xấu — chỉ soft penalty |
| **Group near duplicates** | Có, nhưng phạm vi hẹp | `VNFeaturePrintObservation` + time gap, streaming O(n)/session — [VisionEventPhotoAnalyzer.swift:93-122](Nizi/Features/MemoryDiscovery/Infrastructure/VisionEventPhotoAnalyzer.swift#L93-L122) | Chỉ trong 1 session + ≤60s; representative cố định không cập nhật; threshold chưa tune |
| **Select best per group** | Có | `selectWithinGroup`, top-score + optional runner-up cho burst lớn — [EventPhotoCurationEngine.swift:107-143](Nizi/Features/MemoryDiscovery/Domain/EventPhotoCurationEngine.swift#L107-L143) | Không có absolute quality floor tách biệt, chỉ 1 ngưỡng thấp áp sau khi rank |
| **Global ranking** | Có, giới hạn | `balanceAcrossEvent`, chỉ kích hoạt khi vượt ceiling — [EventPhotoCurationEngine.swift:159-188](Nizi/Features/MemoryDiscovery/Domain/EventPhotoCurationEngine.swift#L159-L188) | Trim thuần theo score, không quota theo group/ngày |
| **Temporal diversity** | Không | — | Không có bucket đầu/giữa/cuối Event; rủi ro dồn về ngày điểm cao khi trim |
| **Visual diversity** | Không (ngoài near-dup 1-per-cluster cục bộ) | — | Feature print chưa dùng cho diversity toàn Event; không MMR/similarity-penalty giữa các cluster khác nhau |
| **Favorite priority** | Có, yếu | +0.15 flat trong `compositeScore` — [PhotoQualityMetrics.swift:24-25](Nizi/Features/MemoryDiscovery/Domain/PhotoQualityMetrics.swift#L24-L25) | Không override exclusion, không bảo vệ khi trim, dễ bị đè bởi 3 signal còn lại |

---

## Ghi chú thêm ngoài phạm vi 4 tầng (đáng lưu ý trước khi sửa)

- **Bump `algorithmVersion` sẽ xoá mọi chỉnh sửa tay của user** trên mọi Event đã curate trước đó (mục 23/25) — cần có kế hoạch migrate/preserve `userAdded`/`userRemoved` trước khi tối ưu thuật toán duplicate/selection.
- Cache-validity chỉ so `sourceAssetCount`, không so tập asset ID (mục 2) — thay 1 đổi 1 sẽ không invalidate.
- Không có diagnostics UI/debug cho curation (mục 29) — nên cân nhắc thêm trước khi tinh chỉnh threshold, để có cách quan sát trực quan hiệu quả thay đổi.
