# DB-MEMORY-DISCOVERY

## 1. Mục đích

Tài liệu này mô tả dữ liệu cục bộ cho module Memory Discovery trong Nizi iOS.

Database chỉ lưu metadata và trạng thái xử lý. Không lưu ảnh gốc.

MVP đề xuất dùng **SwiftData**. Nếu benchmark thư viện lớn không đạt yêu cầu, có thể chuyển repository implementation sang GRDB/SQLite mà không thay đổi Domain.

---

## 2. Nguyên tắc dữ liệu

1. Local-first.
2. Dữ liệu có thể tái tạo.
3. Không coi database là nguồn ảnh.
4. `assetLocalIdentifier` là reference tới Photos.
5. Không lưu `UIImage`, `Data` ảnh hoặc file gốc trong database.
6. Tất cả entity có version để hỗ trợ re-analysis.
7. Không hard delete ngay khi asset biến mất.
8. Dữ liệu server và local index tách biệt.

---

## 3. Schema tổng thể

```text
md_local_asset
md_scan_checkpoint
md_photo_session
md_session_asset
md_event_candidate
md_event_session
md_event_asset
md_similarity_group
md_similarity_asset
md_album_draft
md_album_draft_asset
md_discovery_feedback
md_analysis_job
md_app_setting
```

Prefix `md_` dùng để phân biệt dữ liệu Memory Discovery.

---

## 4. Entity: md_local_asset

Lưu metadata cơ bản của mỗi `PHAsset`.

| Field | Type | Required | Ghi chú |
|---|---|---:|---|
| id | UUID/String | yes | Primary key local |
| asset_local_identifier | String | yes | `PHAsset.localIdentifier`, unique |
| creation_date | DateTime | no | Thời điểm chụp |
| modification_date | DateTime | no | Thay đổi từ Photos |
| media_type | String | yes | image/video/livePhoto/unknown |
| media_subtypes | Int64 | yes | Bitmask |
| pixel_width | Int | yes |  |
| pixel_height | Int | yes |  |
| duration | Double | yes | Video, mặc định 0 |
| latitude | Double | no | Local-only |
| longitude | Double | no | Local-only |
| location_source | String | yes | original/inferred/none |
| geo_cell | String | no | Cell xấp xỉ |
| favorite | Bool | yes |  |
| hidden | Bool | yes |  |
| screenshot | Bool | yes |  |
| burst_identifier | String | no |  |
| source_type | String | no | userLibrary/cloud/shared/unknown |
| availability_status | String | yes | available/unavailable/deleted/accessRevoked |
| discovery_status | String | yes | new/indexed/clustered/ignored/error |
| quality_score | Double | no | 0...1 |
| aesthetic_score | Double | no | 0...1 |
| sharpness_score | Double | no | 0...1 |
| exposure_score | Double | no | 0...1 |
| face_count | Int | no | Không lưu danh tính |
| analysis_version | Int | yes | Mặc định 0 |
| last_seen_at | DateTime | yes |  |
| created_at | DateTime | yes |  |
| updated_at | DateTime | yes |  |

### Index

```text
UNIQUE(asset_local_identifier)
INDEX(creation_date)
INDEX(geo_cell)
INDEX(discovery_status)
INDEX(availability_status)
INDEX(analysis_version)
```

---

## 5. Entity: md_scan_checkpoint

Lưu trạng thái scan.

| Field | Type | Required |
|---|---|---:|
| id | UUID | yes |
| scan_type | String | yes |
| status | String | yes |
| started_at | DateTime | yes |
| completed_at | DateTime | no |
| total_assets_estimated | Int | no |
| processed_count | Int | yes |
| failed_count | Int | yes |
| cursor_value | String | no |
| last_asset_creation_date | DateTime | no |
| app_version | String | yes |
| schema_version | Int | yes |
| error_message | String | no |
| updated_at | DateTime | yes |

### scan_type

```text
initial
incremental
reanalyze
recluster
```

### status

```text
idle
running
paused
completed
partiallyCompleted
failed
cancelled
```

Chỉ cho phép một `initial` scan đang chạy.

---

## 6. Entity: md_photo_session

| Field | Type | Required |
|---|---|---:|
| id | UUID | yes |
| start_date | DateTime | yes |
| end_date | DateTime | yes |
| center_latitude | Double | no |
| center_longitude | Double | no |
| geo_cell | String | no |
| asset_count | Int | yes |
| density_score | Double | yes |
| temporal_score | Double | yes |
| spatial_score | Double | yes |
| session_version | Int | yes |
| created_at | DateTime | yes |
| updated_at | DateTime | yes |

---

## 7. Entity: md_session_asset

Join table giữa session và asset.

| Field | Type | Required |
|---|---|---:|
| session_id | UUID | yes |
| local_asset_id | UUID/String | yes |
| sort_order | Int | yes |
| membership_score | Double | yes |
| created_at | DateTime | yes |

### Constraint

```text
UNIQUE(session_id, local_asset_id)
INDEX(local_asset_id)
```

---

## 8. Entity: md_event_candidate

| Field | Type | Required |
|---|---|---:|
| id | UUID | yes |
| title_suggestion | String | yes |
| start_date | DateTime | yes |
| end_date | DateTime | yes |
| primary_location_label | String | no |
| primary_geo_cell | String | no |
| event_type | String | yes |
| confidence | Double | yes |
| score | Double | yes |
| status | String | yes |
| cover_asset_id | UUID/String | no |
| asset_count | Int | yes |
| session_count | Int | yes |
| discovery_reasons_json | String | yes |
| algorithm_version | Int | yes |
| created_at | DateTime | yes |
| updated_at | DateTime | yes |
| viewed_at | DateTime | no |
| dismissed_at | DateTime | no |
| accepted_at | DateTime | no |

### event_type

```text
trip
celebration
dayEvent
weekend
dailyLife
unknown
```

MVP có thể dùng `unknown`, `trip`, `dayEvent`.

### status

```text
new
viewed
accepted
dismissed
snoozed
merged
convertedToAlbum
invalid
```

---

## 9. Entity: md_event_session

| Field | Type | Required |
|---|---|---:|
| event_candidate_id | UUID | yes |
| session_id | UUID | yes |
| sort_order | Int | yes |

```text
UNIQUE(event_candidate_id, session_id)
```

---

## 10. Entity: md_event_asset

Có thể tính gián tiếp qua session, nhưng nên materialize để review nhanh.

| Field | Type | Required |
|---|---|---:|
| event_candidate_id | UUID | yes |
| local_asset_id | UUID/String | yes |
| sort_order | Int | yes |
| relevance_score | Double | yes |
| selected_by_default | Bool | yes |
| exclusion_reason | String | no |

```text
UNIQUE(event_candidate_id, local_asset_id)
INDEX(local_asset_id)
```

---

## 11. Entity: md_similarity_group

| Field | Type | Required |
|---|---|---:|
| id | UUID | yes |
| event_candidate_id | UUID | no |
| recommended_asset_id | UUID/String | no |
| confidence | Double | yes |
| group_type | String | yes |
| created_at | DateTime | yes |
| updated_at | DateTime | yes |

### group_type

```text
exactDuplicate
nearDuplicate
burst
similarScene
```

---

## 12. Entity: md_similarity_asset

| Field | Type | Required |
|---|---|---:|
| similarity_group_id | UUID | yes |
| local_asset_id | UUID/String | yes |
| similarity_score | Double | yes |
| rank | Int | yes |
| user_choice | String | no |

---

## 13. Entity: md_album_draft

| Field | Type | Required |
|---|---|---:|
| id | UUID | yes |
| source_candidate_id | UUID | no |
| server_album_id | String | no |
| title | String | yes |
| start_date | DateTime | no |
| end_date | DateTime | no |
| location_label | String | no |
| cover_asset_id | UUID/String | no |
| sort_mode | String | yes |
| status | String | yes |
| upload_status | String | yes |
| created_at | DateTime | yes |
| updated_at | DateTime | yes |

### status

```text
editing
ready
submitted
cancelled
```

### upload_status

```text
notStarted
preparing
uploading
paused
failed
completed
```

---

## 14. Entity: md_album_draft_asset

| Field | Type | Required |
|---|---|---:|
| album_draft_id | UUID | yes |
| local_asset_id | UUID/String | yes |
| sort_order | Int | yes |
| selection_status | String | yes |
| upload_status | String | yes |
| server_photo_id | String | no |
| upload_session_id | String | no |
| error_message | String | no |
| created_at | DateTime | yes |
| updated_at | DateTime | yes |

### selection_status

```text
selected
rejected
suggested
```

### upload_status

```text
pending
checkingAvailability
downloadingFromICloud
ready
uploading
uploaded
failed
cancelled
```

---

## 15. Entity: md_discovery_feedback

Lưu hành vi để cải thiện đề xuất cục bộ.

| Field | Type | Required |
|---|---|---:|
| id | UUID | yes |
| event_candidate_id | UUID | no |
| local_asset_id | UUID/String | no |
| feedback_type | String | yes |
| value_json | String | no |
| created_at | DateTime | yes |

### feedback_type

```text
candidateAccepted
candidateDismissed
assetSelected
assetRejected
coverChanged
eventMerged
eventSplit
titleEdited
```

MVP chỉ cần accepted/dismissed/selected/rejected.

---

## 16. Entity: md_analysis_job

| Field | Type | Required |
|---|---|---:|
| id | UUID | yes |
| job_type | String | yes |
| scope_id | String | no |
| status | String | yes |
| priority | Int | yes |
| progress | Double | yes |
| retry_count | Int | yes |
| max_retry | Int | yes |
| error_message | String | no |
| created_at | DateTime | yes |
| updated_at | DateTime | yes |

### job_type

```text
metadataScan
clustering
thumbnailAnalysis
similarityAnalysis
candidateRebuild
uploadPreparation
```

---

## 17. Entity: md_app_setting

| Field | Type | Required |
|---|---|---:|
| key | String | yes |
| value_json | String | yes |
| updated_at | DateTime | yes |

Các key ban đầu:

```text
memoryDiscovery.enabled
scan.allowCellular
scan.allowICloudThumbnail
scan.lastCompletedAt
analysis.version
clustering.version
privacy.lastConsentVersion
```

---

## 18. SwiftData model skeleton

```swift
@Model
final class MDLocalAsset {
    @Attribute(.unique)
    var assetLocalIdentifier: String

    var creationDate: Date?
    var modificationDate: Date?
    var mediaType: String
    var pixelWidth: Int
    var pixelHeight: Int
    var latitude: Double?
    var longitude: Double?
    var favorite: Bool
    var screenshot: Bool
    var availabilityStatus: String
    var discoveryStatus: String
    var qualityScore: Double?
    var analysisVersion: Int
    var lastSeenAt: Date
    var createdAt: Date
    var updatedAt: Date
}
```

Domain không sử dụng trực tiếp class SwiftData. Repository chịu trách nhiệm map.

---

## 19. Migration

### Schema version 1

Bao gồm:

- LocalAsset;
- ScanCheckpoint;
- PhotoSession;
- EventCandidate;
- AlbumDraft.

### Schema version 2

Bổ sung:

- SimilarityGroup;
- quality score;
- analysis job.

### Schema version 3

Bổ sung:

- local personalization;
- feedback mở rộng.

Không xây toàn bộ v2/v3 trong MVP.

---

## 20. Data lifecycle

### Khi app scan

```text
PhotoKit
→ LocalAsset upsert
→ lastSeenAt update
→ discoveryStatus=indexed
```

### Khi clustering

```text
LocalAsset
→ PhotoSession
→ EventCandidate
→ event_asset
```

### Khi quyền bị thu hồi

```text
availabilityStatus=accessRevoked
```

Không hard delete ngay.

### Khi asset bị xóa

```text
availabilityStatus=deleted
```

Xóa vật lý sau maintenance nếu asset không còn được tham chiếu.

### Khi người dùng xóa dữ liệu khám phá

Xóa:

- LocalAsset;
- Session;
- Candidate;
- Similarity;
- Feedback;
- Thumbnail cache;
- Checkpoint.

Giữ lại:

- tài khoản;
- Album server đã tạo;
- ảnh đã upload server.

---

## 21. Database constraints

- Không duplicate `assetLocalIdentifier`.
- Không duplicate asset trong cùng session.
- Không duplicate asset trong cùng candidate.
- Không duplicate asset trong cùng draft.
- Không xóa LocalAsset đang nằm trong AlbumDraft chưa hoàn thành.
- Candidate convertedToAlbum không được convert lần hai nếu chưa reset rõ ràng.

---

## 22. Query quan trọng

### Asset chưa cluster

```text
availability=available
AND discoveryStatus=indexed
ORDER BY creationDate
LIMIT batchSize
```

### Candidate mới

```text
status=new
ORDER BY score DESC, startDate DESC
```

### Asset cần phân tích

```text
analysisVersion < currentAnalysisVersion
AND availability=available
AND asset thuộc candidate đang quan tâm
```

### Upload chưa hoàn thành

```text
albumDraft.uploadStatus IN (preparing, uploading, failed)
```

---

## 23. Definition of Done database

- Lưu được 50.000 LocalAsset mà không lưu binary ảnh.
- Batch upsert không khóa UI.
- Resume scan được từ checkpoint.
- Candidate truy vấn nhanh.
- Asset deleted/accessRevoked không làm crash UI.
- Xóa toàn bộ discovery data hoạt động.
- Migration có version.
- Không có GPS hoặc dữ liệu phân tích bị gửi server ngoài ý muốn.
