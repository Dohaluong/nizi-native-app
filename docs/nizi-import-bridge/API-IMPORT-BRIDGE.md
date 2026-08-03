# API Import Bridge

Mọi lỗi API đều có dạng `{ "success": false, "code": "...", "message": "..." }`.

| Method | Path | Auth | Mục đích |
| --- | --- | --- | --- |
| GET | `/api/health` | — | Health check |
| POST | `/api/import-sessions` | browser | Tạo session và asset metadata |
| POST | `/api/import-assets/:assetId/upload` | `X-Session-Id`, `X-Session-Owner` | Upload/retry từng asset |
| POST | `/api/import-sessions/:sessionId/finalize` | owner | Chỉ khi asset ready; trả QR |
| GET | `/api/import-sessions/:sessionId` | owner | Theo dõi session browser |
| POST | `/api/import-sessions/:sessionId/claim` | QR token/mã ghép nối | Trả access token native một lần |
| GET | `/api/import-sessions/:sessionId/manifest` | `Bearer` native token | Lấy danh sách asset |
| GET | `/api/import-assets/:assetId/download` | `Bearer` native token | Download có Range; khoá khi asset đã hoàn tất |
| POST | `/api/import-assets/:assetId/completed` | `Bearer` native token | Xác nhận đã lưu, xoá file server và khoá asset |
| POST | `/api/import-assets/:assetId/failed` | `Bearer` native token | Báo lỗi từng ảnh, có thể retry |
| POST | `/api/import-sessions/:sessionId/completed` | `Bearer` native token | Hoàn tất session |
| DELETE | `/api/import-sessions/:sessionId` | owner | Xoá ngay session/asset |

Nizi Native quét `https://move.nizi.vn/import/{sessionId}?token={oneTimeToken}`, lấy token từ query và gọi `claim`. Nó phải lưu access token trả về ở Keychain, rồi dùng bearer token cho manifest/download/status. Không dùng URL asset nếu thiếu token. Sau khi native xác minh checksum và lưu ảnh thành công, phải gọi `/completed`: server xoá file asset ngay và URL đó sau đó trả `410 ASSET_LOCKED`. Khi gọi `/api/import-sessions/:sessionId/completed`, native access token cũng bị thu hồi.
