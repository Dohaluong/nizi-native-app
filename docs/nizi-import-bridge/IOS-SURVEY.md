# Khảo sát Nizi Native cho Import Bridge

Khảo sát ngày 03/08/2026, trước khi triển khai Import Bridge.

| Hạng mục | Kết quả |
| --- | --- |
| `PHAsset.localIdentifier` | `MDLocalAsset.assetLocalIdentifier` (unique) là khóa của Local Memory Index; album cũng dùng identifier này. |
| Metadata/index | `PhotoKitAssetProvider` đọc PhotoKit; `ScanPhotoLibraryUseCase` upsert qua `SwiftDataMemoryDiscoveryStore`. |
| Event/Memory/Trip | `DiscoverEventsUseCase` dùng `EventDiscoveryEngine`, rồi persist Event/Trip/Location Intelligence qua cùng store. |
| Incremental | Schema có `ScanType.incremental`, nhưng scan hiện tại chỉ điều khiển checkpoint `.initial`; `DiscoverEventsUseCase` hiện rebuild từ Local Memory Index. Import Bridge vì vậy index trực tiếp các identifier mới và không tự chạy discovery toàn thư viện. |
| Database/tác vụ dài | SwiftData, với `@ModelActor` store và checkpoint có thể resume cho library scan. Không có background URLSession/BGTask dùng chung. |
| PhotoKit/quyền | `PhotoKitAssetProvider` và `PhotoKitAuthorizationService` dùng quyền `.readWrite`; Limited được map rõ ràng. |
| Token/API | Chưa có Keychain wrapper, API client hay error model dùng chung. Import Bridge có wrapper/API riêng để tránh phát tán credential. |

Kết luận: Import Bridge bổ sung một nguồn asset và ghi metadata vào `MDLocalAsset`; không tạo Event/Memory/Trip algorithm mới. Discovery batch tự động chưa được bật vì implementation hiện tại không có adapter incremental an toàn (nó rebuild dữ liệu hiện hữu), nên đây là hạng mục cần thiết kế tiếp theo thay vì âm thầm full scan.

## Kiểm tra service thực tế

`GET https://move.nizi.vn/api/health` ngày 03/08/2026 trả HTTP 200 với `status: ok`, service `nizi-import-bridge`, version `1.0.0`. Các endpoint claim/manifest/download cần credential một lần nên không thể khảo sát response thực tế an toàn từ repository này; implementation bám đúng contract v1 trong các tài liệu được cung cấp.

### Sai khác phát hiện sau kiểm tra end-to-end

`POST /api/import-sessions/:sessionId/finalize` trên production hiện trả `importUrl` dạng `http://127.0.0.1:4318/import/imp_...?token=...`. Điều này trái với contract QR (`https://move.nizi.vn/import/...`) và tài liệu deploy. Nizi Native cố ý từ chối URL này vì không phải HTTPS và host không phải `move.nizi.vn`.

Việc cần làm ở webapp/xCloud: đặt `PUBLIC_BASE_URL=https://move.nizi.vn`, redeploy server, rồi tạo QR mới. Không sửa native để chấp nhận `127.0.0.1` hay HTTP.

`POST /api/import-sessions/:sessionId/claim` trên production cũng khác contract: sau claim thành công response có `data.session` nhưng thiếu `data.accessToken`. Contract v1 yêu cầu `accessToken` để native gọi manifest/download/completed. Đây là nguyên nhân của thông báo `data couldn't be read because it is missing`; native nay hiển thị lỗi tương thích rõ ràng thay cho lỗi decoder.

Việc cần làm ở webapp: claim phải trả lại `{ "success": true, "data": { "accessToken": "…", "session": { … } } }`, đúng `NATIVE-IOS-QR-INTEGRATION.md` §3. Không có token này thì Import Bridge không thể tiếp tục an toàn.
