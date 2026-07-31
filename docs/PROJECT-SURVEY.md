# Khảo sát dự án Nizi — Tính năng đã hoàn thành & Diagnostics

> Tài liệu này khảo sát toàn bộ những gì đã được xây dựng trong app iOS "Nizi" tính đến 2026-07-31: từng Feature, các màn hình người dùng thật sự dùng, và toàn bộ hệ thống Diagnostics (công cụ dev/debug). Đây là bản chụp nhanh dựa trên code hiện tại — khi code thay đổi, tài liệu này cần cập nhật lại.

## 1. Kiến trúc tổng thể

- **Entry point:** [NiziApp.swift](Nizi/NiziApp.swift) — `@main`, một `WindowGroup` duy nhất bọc `ContentView()`, dùng chung một SwiftData `.modelContainer` cho toàn bộ model đã persist của mọi Feature (asset đã scan, checkpoint, session, event, curation, album draft, edit recipe, style theo collection, preset...).
- **Không có TabView** — điều hướng là một luồng tuyến tính duy nhất. [ContentView.swift](Nizi/ContentView.swift) quản lý một `OnboardingStage` enum (`checking → helloNizi → scopeSelection → permission → scanning → home`), mỗi bước đẩy màn hình MemoryDiscovery tương ứng, cuối cùng vào `HomeView`. Nếu đã từng scan xong (kiểm tra qua `SwiftDataMemoryDiscoveryStore`), app bỏ qua onboarding và vào thẳng `home`.
- **`HomeView`** (MemoryDiscovery) là màn hình "nhà" thật sự sau onboarding — dòng thời gian Album (placeholder khi rỗng + hàng preview Album gần đây cuộn ngang) cộng một "quick action card" dẫn sang `EventListView` (luồng Event Discovery — cố tình là luồng phụ, không phải màn hình chính).
- Debug-only: khi build DEBUG, app inject `DebugLocaleOverride` vào environment để có thể ép ngôn ngữ hiển thị en/vi mà không cần đổi system locale.

Kiến trúc theo Feature, mỗi Feature chia lớp kiểu Clean Architecture: `Domain/` (model + business rule thuần), `Application/` (use case/coordinator, thường là protocol), `Infrastructure/` (cài đặt thật — PhotoKit, SwiftData, CoreLocation...), `Presentation/` (SwiftUI views).

7 Feature hiện có: `AlbumCreation`, `AlbumLayout`, `AlbumPhotos`, `AlbumViewer`, `MemoryDiscovery`, `PhotoEditor`, `PhotoLocation`. Cộng `Nizi/Core/` cho hạ tầng dùng chung.

---

## 2. Khảo sát từng Feature

### 2.1 MemoryDiscovery — lớn nhất, là "xương sống" của app

**Mục đích:** Scan thư viện Photos của người dùng vào một index cục bộ ("Local Memory Index"), gom cụm ảnh thành session/event bằng luật metadata xác định (deterministic, không random), rồi chọn lọc ảnh đẹp nhất theo từng event. Đây cũng là nơi phát sinh phần lớn công cụ Diagnostics của app.

**Domain nổi bật:**
- `LibraryScanScope` — phạm vi quét người dùng chọn ở Scope Selection.
- `ScanCheckpoint` / `ScanType` / `ScanPauseFlag` — scan theo batch, có thể resume.
- `IndexedAsset` — một dòng trong Local Memory Index (không phải raw PhotoKit object).
- `PhotoSession` — cụm ảnh sát nhau về thời gian/vị trí.
- `PhotoEvent`, `EventType`, `DiscoveryReasonKind` — sự kiện được gom từ session.
- `EventDiscoveryEngine` — logic gom cụm thuần (không đụng PhotoKit, không persist, không random).
- `EventDiscoveryConfig` — tập trung mọi ngưỡng (threshold) của thuật toán.
- `PhotoCurationGroup` / `PhotoCurationItem` / `CurationStatus` — chọn lọc ảnh đẹp; lựa chọn thủ công của user luôn thắng thuật toán.
- `EventPhotoCurationEngine` — logic chọn ảnh thuần, nhận input đã phân tích sẵn.
- `PhotoAccessStatus`, `PhotoLibraryAuthorizationService` — bọc `PHAuthorizationStatus` để Presentation không phải import PhotoKit trực tiếp.

**Application:** `ScanPhotoLibraryUseCase` (quét cả thư viện theo batch, resume từ checkpoint cuối), `DiscoverEventsUseCase` (rebuild toàn bộ session/event từ index), `EventPhotoCurationService`.

**Màn hình người dùng chính:**
| Màn hình | Vai trò |
|---|---|
| [HelloNiziView.swift](Nizi/Features/MemoryDiscovery/Presentation/HelloNiziView.swift) | Welcome màn đầu (chỉ hiện nếu chưa từng scan xong) |
| [ScopeSelectionView.swift](Nizi/Features/MemoryDiscovery/Presentation/ScopeSelectionView.swift) | Chọn phạm vi thư viện cần quét (cố tình không có date picker) |
| [OnboardingPermissionView.swift](Nizi/Features/MemoryDiscovery/Presentation/OnboardingPermissionView.swift) | Xin quyền Photos, hiển thị kết quả |
| [UserScanProgressView.swift](Nizi/Features/MemoryDiscovery/Presentation/UserScanProgressView.swift) | Chạy scan theo scope rồi discover event, xong thì vào Home |
| [HomeView.swift](Nizi/Features/MemoryDiscovery/Presentation/HomeView.swift) | Home thật của app — dòng Album + quick action vào Event |
| [EventListView.swift](Nizi/Features/MemoryDiscovery/Presentation/EventListView.swift) | Danh sách Event (chỉ vào được qua Quick Action ở Home) |
| [EventDetailView.swift](Nizi/Features/MemoryDiscovery/Presentation/EventDetailView.swift) | Cover → info → tóm tắt lựa chọn → nhóm đã chọn lọc → thanh chọn ảnh dưới cùng; tự chạy curation khi mở lần đầu |
| [EventCardView.swift](Nizi/Features/MemoryDiscovery/Presentation/EventCardView.swift) | Thẻ 1 event trong list (chia 30/70 khối ngày/ảnh cover) |

Các màn debug-only của Feature này: `PhotoLibraryDiagnosticsView`, `LibraryIndexScanView`, `EventDiscoveryDebugListView`, `PhotoLibraryScanSampleView` — xem mục 3.

### 2.2 AlbumCreation — bộ lập kế hoạch Album (thuần thuật toán)

**Mục đích:** Nhận vào một tập ảnh/Event đã được người dùng chọn, lên kế hoạch dàn vào Album: gom Spread/Page, chọn layout, gán ảnh vào slot, chọn ảnh cover. Thuật toán thật **không bao giờ dùng random** — random chỉ tồn tại trong dữ liệu giả lập cho Preview/Diagnostics.

**Domain nổi bật:** `AlbumDraft`/`AlbumDraftPage` (hình dạng Album đã persist), `AlbumPlanningPhoto`/`AlbumPhotoEXIF`, `PhotoImportance`/`PhotoImportanceReason` (tiêu chí chấm điểm ảnh), `PhotoOrientation` (phân loại từ kích thước pixel, không dùng cờ EXIF orientation), `AlbumPlanningError`, `AlbumPrimaryPlaceResolver` (chọn 1 "địa điểm chính" — liên kết với PhotoLocation), `AlbumPlanningResult`/`AlbumPlanningLog`/`AlbumPlanningStage` (log có cấu trúc từng bước lập kế hoạch, phục vụ audit/diagnostics).

**Pipeline Application** (mỗi bước một protocol riêng biệt): `PhotoImportanceEvaluating` → `AlbumPhotoGrouping` (gom theo Event) → `AlbumSpreadBuilding` (dựng Spread theo luật cứng) → `AlbumLayoutPairSelecting` (chọn layout, tránh lặp lại nhờ lịch sử) → `AlbumPhotoSlotAssigner` → `AlbumCoverSelecting` → `AlbumPlanningValidator` (validate cả input lẫn draft cuối).

**Presentation:** Không có màn hình cho người dùng cuối — toàn bộ là công cụ Preview/Diagnostics: `AlbumDraftPlanningPreview` (dev harness với các kịch bản "Varied Album"/"Edge Cases"/"Layout Library"), `AlbumDraftPreviewFactory` (sinh input giả lập đa dạng), `DistinguishableMockPhotoProvider`, `SeededRandomNumberGenerator` (PRNG splitmix64 xác định, để tái lập kết quả mock).

### 2.3 AlbumLayout — engine layout (JSON-driven)

**Mục đích:** Thư viện layout trang (vị trí slot ảnh/text theo từng khổ trang) dạng JSON, cộng renderer và validator. Thuần hình học/hiển thị — không chứa business logic của Album (gom nhóm, chấm điểm, persist).

**Domain nổi bật:** `AlbumLayoutFrame` (vị trí/kích thước slot theo đơn vị canvas tham chiếu, không phải pixel thật), `AlbumPageLayout`, `AlbumPageFormat`, `AlbumLayoutBackgroundType` (hiện chỉ có `.solid`), `AlbumPhotoAssignment`, `AlbumTextAssignment`/`AlbumTextBlock`, `AlbumLayoutValidator`, `AlbumLayoutSelecting` (chọn layout xác định, không random), `AlbumLayoutRepository` (cài đặt `BundleAlbumLayoutRepository` đọc JSON từ bundle).

**Presentation:** [AlbumPageRenderer.swift](Nizi/Features/AlbumLayout/Presentation/AlbumPageRenderer.swift) — engine render dùng chung cho mọi màn Album thật (render slot ảnh/text từ layout, có hook kéo-thả đổi ảnh `onSwapPhotos` — ngoại lệ duy nhất của "chỉ render thuần"). `AlbumPhotoSlotView`, `AlbumTextBlockView` render nội dung từng slot. `AlbumSlotPhotoProviding` với `PlaceholderAlbumPhotoProvider`/`LayoutSwatchPhotoProvider` cấp ảnh giả để chạy màn Diagnostics `AlbumLayoutGalleryPreview` (toàn bộ layout trong thư viện, nhóm theo số ảnh) và `AlbumPagesPreview` (cover + layout thật lật ngang, màn kiểm thử engine layout).

### 2.4 AlbumPhotos — cầu nối Photos Library

**Mục đích:** Lớp mỏng nối Album Layout/Viewer với thư viện Photos thật (PhotoKit) — load, cache, cấp pixel ảnh cho slot.

**Domain nổi bật:** `AlbumPhotoLoadState` (`.loading`/`.degraded`/`.success`/`.missing`/`.failure`; `.degraded` là preview nhanh của PHImageManager trước khi có ảnh cuối), `AlbumPhotoReference`/`AlbumPhotoSource` (hiện chỉ `.applePhotos`), `AlbumPhotoRequest`/`AlbumPhotoContentMode`, `AlbumPhotoCrop` (crop trong slot — đã chuẩn bị, chưa edit đầy đủ), `AlbumPhotoProviderError`.

**Application:** `AlbumPhotoProviding` — trả về `AsyncStream` (thay vì 1 lần `async throws`) để nơi gọi quan sát được tiến trình loading→degraded→success.

**Infrastructure:** `ApplePhotosAlbumPhotoProvider` (cài đặt thật qua PhotoKit), `PHAssetRepository`, `AlbumImageCache` (cache in-memory — chính là thứ màn Diagnostics dò cache hit).

**Presentation:** [AlbumPhotoView.swift](Nizi/Features/AlbumPhotos/Presentation/AlbumPhotoView.swift) (render 1 ảnh qua mọi load state), `MockAlbumPhotoProvider` (chỉ dùng Preview/test), `ProductionAlbumSlotPhotoProvider` (nối slot sizing của renderer với load ảnh thật), và `RealAlbumPhotoDiagnosticsView` (mục 3).

### 2.5 AlbumViewer — trải nghiệm xem/sửa Album thật (người dùng cuối)

**Mục đích:** Đây là các màn hình Album mà người dùng thật sự thấy — nối với ảnh thật và dữ liệu đã persist thật (khác với AlbumLayout/AlbumCreation chỉ là engine/lập kế hoạch).

**Domain nổi bật:** `AlbumEditingSession` (mọi chỉnh sửa chạm vào `workingDraft`, không đụng `AlbumDraft` đã persist — nên Cancel luôn miễn phí), `AlbumViewerSelection` (chọn theo identity chứ không theo index, tránh lệch khi số Page thay đổi), `AlbumViewerItem`/`AlbumSpreadPagePosition`, `AlbumCoverConfiguration`, `AlbumDraftValidating`.

**Application:** `AlbumViewerItemBuilding` (làm phẳng các Spread-2-trang của draft đã persist thành list trang đơn cho Viewer), `AlbumEditActionApplying` (nơi logic sửa/mutate thật sự nằm), `AlbumCoverPageBuilder`.

**Màn hình người dùng chính:**
| Màn hình | Vai trò |
|---|---|
| [AlbumsListView.swift](Nizi/Features/AlbumViewer/Presentation/AlbumsListView.swift) | Danh sách mọi Album, lọc theo năm; vào từ link "Xem tất cả" ở Home |
| [AlbumDetailView.swift](Nizi/Features/AlbumViewer/Presentation/AlbumDetailView.swift) | Màn chi tiết Album production — cover thật + mọi Page cuộn dọc liên tục (không phải carousel ngang); mỗi Page có bút chì mở editor riêng |
| [AlbumPageViewer.swift](Nizi/Features/AlbumViewer/Presentation/AlbumPageViewer.swift) | Viewer/editor từng trang một (cover trước, rồi từng Page, vuốt qua lại `TabView`) |
| [AlbumInfoEditSheet.swift](Nizi/Features/AlbumViewer/Presentation/AlbumInfoEditSheet.swift) | Sửa metadata Album (tên/phụ đề/địa điểm/khoảng ngày/cover) |
| [AlbumPhotoPickerSheet.swift](Nizi/Features/AlbumViewer/Presentation/AlbumPhotoPickerSheet.swift) | Chọn "Đổi ảnh cover", giới hạn trong ảnh đã có sẵn trong Album |
| [AlbumPhotoCropSheet.swift](Nizi/Features/AlbumViewer/Presentation/AlbumPhotoCropSheet.swift) | Crop 1 ảnh trong Album |
| [AlbumTextBlockEditSheet.swift](Nizi/Features/AlbumViewer/Presentation/AlbumTextBlockEditSheet.swift) | Sửa nội dung/kiểu 1 khối text |
| [AlbumPhotoPreviewView.swift](Nizi/Features/AlbumViewer/Presentation/AlbumPhotoPreviewView.swift) | Xem ảnh full-screen, zoom/pan tuỳ chỉnh |
| [AlbumPageCardView.swift](Nizi/Features/AlbumViewer/Presentation/AlbumPageCardView.swift) | Card render trang sách dùng chung cho cả AlbumDetailView lẫn AlbumPageViewer |
| [AlbumPagingLockView.swift](Nizi/Features/AlbumViewer/Presentation/AlbumPagingLockView.swift) | `UIViewRepresentable` khoá/mở vuốt trang UIKit khi đang kéo dở |

### 2.6 PhotoEditor — chỉnh sửa ảnh không phá huỷ (non-destructive)

**Mục đích:** Chỉnh sáng/tương phản..., áp preset/LUT (`.cube`), auto-enhance, và kế thừa style theo collection (Album/Event). Chỉ persist một "công thức chỉnh sửa" (recipe), không bao giờ persist pixel cho tới khi export.

**Domain nổi bật:** `PhotoEditRecipe` (thứ duy nhất Photo Editor persist cho 1 ảnh), `PhotoAdjustments` (6 slider Adjust theo đơn vị engine chuẩn hoá), `PhotoEditSession`, `PhotoEditorResult`, `EditorSourceType` (mở từ Album/Event/standalone), `PresetDefinition`/`PresetHSLAdjustments`/`HSLColorBand` (chỉnh màu HSL chọn lọc), `PresetValidator`, `CollectionEditStyle`/`CollectionType` + `CollectionStyleResolver` (Album và Event dùng chung 1 hình dạng style kế thừa), `AutoEnhanceRules`, `PhotoHistogramStatistics`, `PhotoRendering` (trừu tượng hoá render Core Image), `PhotoAssetExporting` (biến recipe thành pixel export thật).

**Infrastructure:** `PhotoRenderEngine`, `PresetRenderer`, `CubeFileParser`/`CubeLUTLoader`, `AutoEnhanceService`, `ImageAnalyzer`, `BundlePresetRepository`/`CustomizablePresetRepository`, `SwiftDataPhotoEditRepository`/`SwiftDataCollectionStyleRepository`.

**Màn hình người dùng chính:**
| Màn hình | Vai trò |
|---|---|
| [PhotoEditorView.swift](Nizi/Features/PhotoEditor/Presentation/PhotoEditorView.swift) | Editor thật — preview render Core Image, Cancel/Save, giữ để xem ảnh gốc, phát hiện thay đổi chưa lưu, dải preset, 6 slider Adjust, Auto Enhance on-device, chọn phạm vi lưu (ảnh này/cả collection) khi mở từ Album/Event |
| [AdjustPanelView.swift](Nizi/Features/PhotoEditor/Presentation/AdjustPanelView.swift) | Khay công cụ Adjust (hàng icon + slider) |
| [PresetStripView.swift](Nizi/Features/PhotoEditor/Presentation/PresetStripView.swift) | Dải thumbnail preset cuộn ngang + slider cường độ |
| [SaveScopeSheet.swift](Nizi/Features/PhotoEditor/Presentation/SaveScopeSheet.swift) | Xác nhận lưu (hiện luôn lưu thành 1 ảnh mới) |
| [PhotoPickerView.swift](Nizi/Features/PhotoEditor/Presentation/PhotoPickerView.swift) | Wrapper `PHPickerViewController` (dùng cho Preset Tuning Panel debug) |

Debug-only trong Feature này: `PresetManagerView`, `PresetTuningPanelView`, `PhotoEditorStandalonePreview` (mục 3), cộng các Mock (`MockAutoEnhancing`, `MockPhotoAssetExporter`, `MockPhotoRendering`) chỉ dùng cho preview/QA.

### 2.7 PhotoLocation — gom cụm địa điểm & reverse-geocode

**Mục đích:** Feature nhỏ, tập trung: gom ảnh theo toạ độ GPS và reverse-geocode cụm thành tên địa điểm dễ đọc, phục vụ AlbumCreation (`AlbumPrimaryPlaceResolver`) và hiển thị Event. Chủ đích không bao giờ hiện bản đồ hay EXIF thô cho người dùng.

**Domain nổi bật:** `PhotoCoordinate` (tách khỏi `CLLocationCoordinate2D` — Domain không import CoreLocation), `PhotoLocationCluster`, `PhotoPlace` (mirror các thành phần của `CLPlacemark`), `PhotoLocationError`.

**Application:** `PhotoLocationClustering` (dùng `CLLocation.distance(from:)`), `PhotoPlaceResolving` (trừu tượng hoá `CLGeocoder`), `PhotoLocationEnricher`/`PhotoLocationEnrichmentResult`, `PhotoPlaceDisplayNameBuilder`.

**Infrastructure:** `ApplePhotoPlaceResolver` (dùng `CLGeocoder` thật), `InMemoryPhotoPlaceCache`.

**Presentation:** Không có màn hình cho người dùng cuối — chỉ có `PhotoLocationDiagnosticsView` (mục 3).

---

## 3. Diagnostics — khảo sát chi tiết

### 3.1 Không có màn Settings/Debug menu trung tâm

Toàn app **không có màn Settings hay Debug menu** riêng (đã grep xác nhận — mọi tham chiếu "Settings" ngoài diagnostics chỉ là gọi `UIApplication.openSettingsURLString` để mở app Settings hệ thống).

Toàn bộ cây Diagnostics chỉ vào được qua **một** nút toolbar gắn cờ `#if DEBUG` duy nhất trên `HomeView`:

```swift
// HomeView.swift:48-55
#if DEBUG
ToolbarItem(placement: .primaryAction) {
    NavigationLink("Diagnostics") {
        PhotoLibraryDiagnosticsView()
    }
    .font(.caption)
}
#endif
```

Vì cả `NavigationLink` này nằm trong `#if DEBUG`, **toàn bộ cây Diagnostics không thể vào được ở bản Release/production** — dù các type view vẫn được compile vào binary, chỉ là không có đường điều hướng tới chúng.

### 3.2 `PhotoLibraryDiagnosticsView` — màn hub

[PhotoLibraryDiagnosticsView.swift](Nizi/Features/MemoryDiscovery/Presentation/PhotoLibraryDiagnosticsView.swift) là màn trung tâm, gồm các mục:

- **Localization** (chỉ DEBUG): Picker đổi ngôn ngữ hiển thị en/vi qua `DebugLocaleOverride` (`@AppStorage`), để so sánh bản dịch trực quan mà không cần đổi ngôn ngữ hệ thống.
- **Authorization**: hiện `PhotoAccessStatus` hiện tại (Not Determined/Limited/Full/Denied/Restricted), nút "Request Access", nút "Manage Selected Photos" (chỉ hiện khi `.limited`), nút "Open Settings".
- **Library** (mỗi link chỉ bật khi đã có quyền Photos `.full`/`.limited`):
  - "Scan Sample" → `PhotoLibraryScanSampleView`
  - "Local Memory Index" → `LibraryIndexScanView`
  - "Event Discovery Debug" → `EventDiscoveryDebugListView`
  - "Photo Location Diagnostics" → `PhotoLocationDiagnosticsView`
  - "Real Album Photo Diagnostics" → `RealAlbumPhotoDiagnosticsView`
- **Album Layout** (không cần quyền Photos — chỉ dùng ảnh placeholder): "Layout Gallery" → `AlbumLayoutGalleryPreview`; "Pages Preview" → `AlbumPagesPreview`; "Draft Planner" → `AlbumDraftPlanningPreview`.
- **Photo Editor** (cũng không cần quyền Photos — dùng mock/pixel giả): "Standalone Preview" → `PhotoEditorStandalonePreview`; "LUT Manager" → `PresetManagerView`; "Preset Tuning" → `PresetTuningPanelView`.

Đây là điểm vào duy nhất cho mọi công cụ debug của mọi Feature: MemoryDiscovery, PhotoLocation, AlbumPhotos, AlbumLayout, PhotoEditor.

### 3.3 Ba màn Diagnostics chính, khảo sát chi tiết

**a) `PhotoLibraryDiagnosticsView`** — chính nó vừa là hub vừa hiện trạng thái quyền Photos (`.task` gọi `authorizationService.currentStatus()`); action "Request Access" log qua `NiziLogger.discovery.info("permission_requested result=...")`. Chỉ được khởi tạo ở [HomeView.swift:51](Nizi/Features/MemoryDiscovery/Presentation/HomeView.swift#L51).

**b) `PhotoLocationDiagnosticsView`** ([PhotoLocationDiagnosticsView.swift](Nizi/Features/PhotoLocation/Presentation/PhotoLocationDiagnosticsView.swift)) — kiểm tra pipeline gom cụm vị trí/reverse-geocode trên ảnh thật gần đây; cố tình tự chạy lại từng bước (cluster → cache → resolve) thay vì gọi API end-to-end, để phân biệt được "cache hit" vs "vừa geocode" vs "lỗi" cho từng ảnh — điều mà API black-box không cho thấy được.
- Hiện: mỗi dòng gồm Photo ID (rút gọn), toạ độ, cluster ID, nguồn kết quả ("cache hit"/"geocoded"/"failed"/"no coordinate"/"unresolved"), tên địa điểm nếu có, dòng lỗi màu đỏ nếu resolve fail.
- Action: nút "Run Location Diagnostics" — kiểm tra quyền Photos, fetch tối đa 20 ảnh gần nhất có GPS, cluster qua `DefaultPhotoLocationClusterer`, tra `InMemoryPhotoPlaceCache` trước rồi mới gọi `ApplePhotoPlaceResolver` thật, build danh sách + thông báo tóm tắt "N photo(s), M cluster(s)".
- Chỉ vào được từ `PhotoLibraryDiagnosticsView`, disable nếu chưa có quyền Photos.

**c) `RealAlbumPhotoDiagnosticsView`** ([RealAlbumPhotoDiagnosticsView.swift](Nizi/Features/AlbumPhotos/Presentation/RealAlbumPhotoDiagnosticsView.swift)) — kiểm tra `ApplePhotosAlbumPhotoProvider` trên ảnh thật gần đây, hiện chính xác điều gì đã xảy ra cho từng request: tìm thấy/thiếu, có qua state degraded hay không, thời gian load, và heuristic cache-hit. Ghi rõ "không bao giờ hiện trong UI production".
- Action: nút "Load 10 Recent Photos (twice, to show cache hits)" — load 10 ảnh gần nhất **hai lần** (lần 1 nguội, lần 2 lẽ ra trúng `AlbumImageCache`) qua `AsyncStream` của provider, chỉ hiện kết quả lần 2 kèm heuristic "likely cache hit" (đúng nếu không thấy state `.loading`/`.degraded` trước khi `.success`).
- Chỉ vào được từ `PhotoLibraryDiagnosticsView`, disable nếu chưa có quyền Photos.

### 3.4 `Nizi/Core/Debug/` — chỉ có 1 file

Thư mục này chỉ có [DebugLocaleOverride.swift](Nizi/Core/Debug/DebugLocaleOverride.swift), toàn bộ file nằm trong `#if DEBUG` nên **không compile vào bản Release**. Đây là enum tiện ích cho dev để ép ngôn ngữ hiển thị (`.system`/`.english`/`.vietnamese`) mà không cần đổi locale hệ thống — dùng ở cả `NiziApp.swift` (root) lẫn Picker trong `PhotoLibraryDiagnosticsView`. Không có debug menu, log viewer, hay feature-flag system nào khác trong `Core/Debug/`.

### 3.5 Các trường hợp cần làm rõ (chữ "Diagnostics" xuất hiện nhưng không phải màn hình)

- `SeededRandomNumberGenerator.swift` và `AlbumDraftPreviewFactory.swift` (AlbumCreation) — chữ "Diagnostics" chỉ là tag phân loại trong doc comment ("Preview/Diagnostics only"), không có UI, chỉ là PRNG/factory sinh dữ liệu giả cho mock.
- `PresetManagerView.swift` và `PresetTuningPanelView.swift` (PhotoEditor) — đây **là** màn Diagnostics thật (không phải trùng chữ ngẫu nhiên): quản lý LUT/preset (list, toggle, rename, xoá, import `.cube`) và bảng tinh chỉnh màu kiểu Lightroom/VSCO, cả hai chỉ vào được qua `Home → Diagnostics → Photo Editor`, DEBUG-only.

### 3.6 Bảng tổng hợp toàn bộ màn Diagnostics

| Màn hình | Feature | Vào từ | Nội dung/hành động | Có trong bản production không? |
|---|---|---|---|---|
| `PhotoLibraryDiagnosticsView` | MemoryDiscovery | Toolbar `HomeView` (`#if DEBUG`) | Trạng thái quyền Photos, request/manage/open-settings, các link hub, đổi locale | Không |
| `PhotoLocationDiagnosticsView` | PhotoLocation | `PhotoLibraryDiagnosticsView` | Toạ độ/cluster/nguồn geocode/tên địa điểm/lỗi theo từng ảnh | Không |
| `RealAlbumPhotoDiagnosticsView` | AlbumPhotos | `PhotoLibraryDiagnosticsView` | Load state, cờ degraded, heuristic cache-hit, thời gian load | Không |
| `PhotoLibraryScanSampleView` | MemoryDiscovery | `PhotoLibraryDiagnosticsView` | Tóm tắt scan metadata + mẫu thumbnail | Không |
| `LibraryIndexScanView` | MemoryDiscovery | `PhotoLibraryDiagnosticsView` | Chạy/tạm dừng/tiếp tục scan batch, độ phủ theo năm/tháng, xoá index | Không |
| `EventDiscoveryDebugListView` | MemoryDiscovery | `PhotoLibraryDiagnosticsView` | Chạy event discovery trên Local Memory Index, điểm số/lý do | Không |
| `AlbumLayoutGalleryPreview` / `AlbumPagesPreview` / `AlbumDraftPlanningPreview` | AlbumLayout / AlbumCreation | `PhotoLibraryDiagnosticsView` | Render thư viện layout / các kịch bản lập kế hoạch Album | Không |
| `PhotoEditorStandalonePreview` / `PresetManagerView` / `PresetTuningPanelView` | PhotoEditor | `PhotoLibraryDiagnosticsView` | Test editor độc lập, quản lý LUT, tinh chỉnh màu trực tiếp | Không |

**Kết luận:** Toàn bộ công cụ Diagnostics/debug của app đi qua đúng một `NavigationLink` gắn `#if DEBUG` tại `HomeView.swift:48-55` — khiến cả cây này trở thành dead code vô hại ở bản Release, dù không phải file nào cũng tự bọc `#if DEBUG` riêng.

---

## 4. Ghi chú

- `Nizi/Core/` ngoài `Debug/` còn có `Formatting/EventDateRangeFormatter.swift`, `Localization/LocalizedString.swift`, `Logging/NiziLogger.swift` (định nghĩa các category log `.general`, `.discovery`, `.photoEditor` dùng chung toàn app, kể cả trong Diagnostics).
- Tài liệu này là khảo sát code hiện tại (snapshot), không phải spec — các spec/ADR chi tiết hơn nằm ở `docs/specs/`, `docs/architecture/ADR/`, `docs/modules/`.
