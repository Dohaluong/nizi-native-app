# Nizi Move — iOS QR integration (protocol v1)

Tài liệu này là hợp đồng tích hợp giữa **Nizi iOS** và Nizi Move đang chạy tại `https://move.nizi.vn`.

Mục tiêu: sau khi người dùng quét QR, app chỉ tải từng asset, kiểm SHA-256, lưu ngay vào Photos, báo kết quả rồi xoá file tạm. Không tải ZIP và không giữ toàn bộ ảnh trong bộ nhớ.

## 1. Nội dung QR

Web tạo QR dưới dạng URL đầy đủ:

```text
https://move.nizi.vn/import/imp_<session-id>?token=<one-time-token>
```

Ví dụ minh hoạ (không phải token thật):

```text
https://move.nizi.vn/import/imp_8ad4...?token=abc...
```

Quy tắc phía native:

- Chỉ chấp nhận HTTPS, host đúng `move.nizi.vn`, path đúng `/import/{sessionId}` và có query `token`.
- Không ghi URL QR, pairing token hoặc access token vào log/analytics.
- QR token dùng một lần và hết hạn theo cấu hình server (mặc định 30 phút).
- Sau khi claim thành công, QR token bị vô hiệu hoá. Không thử claim lại khi app đã có `accessToken` cho session đó.

## 2. Luồng native

```text
Quét QR
  -> kiểm URL
  -> POST /api/import-sessions/{sessionId}/claim  (body: { token })
  -> lưu accessToken vào Keychain
  -> GET /api/import-sessions/{sessionId}/manifest (Bearer accessToken)
  -> với từng asset:
       downloadUrl + Bearer accessToken
       -> SHA-256 phải khớp manifest
       -> lưu Photos
       -> POST /api/import-assets/{assetId}/completed
       -> xoá file tạm
  -> POST /api/import-sessions/{sessionId}/completed
```

Tải tuần tự là mặc định an toàn nhất. Nếu cần tăng tốc, tối đa 2 asset song song; không đánh dấu `completed` trước khi Photos xác nhận lưu thành công. Lời gọi này xoá asset khỏi server ngay, nên download URL sẽ trả `410 ASSET_LOCKED` và không thể resume/tải lại nữa.

## 3. Claim session

```http
POST https://move.nizi.vn/api/import-sessions/{sessionId}/claim
Content-Type: application/json

{ "token": "<token đọc từ QR>" }
```

Phản hồi thành công:

```json
{
  "success": true,
  "data": {
    "accessToken": "<native-session-token>",
    "session": { "protocolVersion": 1, "sessionId": "imp_...", "status": "claimed" }
  }
}
```

Lưu `accessToken` theo `sessionId` trong Keychain. Nó là credential của phiên: không lưu trong `UserDefaults`, không đưa vào crash report. Khi claim trả `401 INVALID_PAIRING_TOKEN`, hiển thị “Mã đã hết hạn hoặc đã được dùng; hãy tạo mã mới trên máy tính.”

## 4. Mã Swift: đọc và kiểm QR

Thêm `NSCameraUsageDescription` vào `Info.plist`, ví dụ: `Nizi cần camera để quét mã chuyển ảnh.`

```swift
import Foundation

struct NiziMoveQR: Sendable {
    let sessionId: String
    let pairingToken: String
}

enum NiziMoveQRError: LocalizedError {
    case invalidCode

    var errorDescription: String? {
        "Đây không phải mã chuyển ảnh Nizi Move hợp lệ."
    }
}

func parseNiziMoveQR(_ rawValue: String) throws -> NiziMoveQR {
    guard let components = URLComponents(string: rawValue),
          components.scheme?.lowercased() == "https",
          components.host?.lowercased() == "move.nizi.vn",
          components.port == nil,
          components.pathComponents.count == 3,
          components.pathComponents[1] == "import",
          components.pathComponents[2].hasPrefix("imp_"),
          let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
          !token.isEmpty
    else { throw NiziMoveQRError.invalidCode }

    return NiziMoveQR(sessionId: components.pathComponents[2], pairingToken: token)
}
```

Scanner QR tối giản dùng `AVFoundation`:

```swift
import AVFoundation
import UIKit

final class NiziMoveQRScannerViewController: UIViewController,
                                             AVCaptureMetadataOutputObjectsDelegate {
    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    var onResult: ((Result<NiziMoveQR, Error>) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        Task { @MainActor in await configureCamera() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func configureCamera() async {
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: granted = true
        case .notDetermined:
            granted = await AVCaptureDevice.requestAccess(for: .video)
        default: granted = false
        }
        guard granted,
              let camera = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: camera),
              captureSession.canAddInput(input)
        else { return }

        captureSession.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard captureSession.canAddOutput(output) else { return }
        captureSession.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: captureSession)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.insertSublayer(preview, at: 0)
        previewLayer = preview
        DispatchQueue.global(qos: .userInitiated).async { [captureSession] in
            captureSession.startRunning()
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let value = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        captureSession.stopRunning() // tránh quét/claim hai lần
        onResult?(Result { try parseNiziMoveQR(value) })
    }
}
```

Khi parse lỗi, gọi lại `captureSession.startRunning()` trên background queue để tiếp tục quét. Khi người dùng đóng màn hình scanner, gọi `stopRunning()`.

## 5. Mã Swift: claim, manifest, download

Mọi request native dùng `URLSession` mặc định và HTTPS. `accessToken` trong ví dụ dưới đây phải được thay bằng token đọc từ Keychain.

```swift
import CryptoKit
import Foundation

struct ClaimEnvelope: Decodable {
    let success: Bool
    let data: ClaimData?
    let code: String?
    let message: String?
}

struct ClaimData: Decodable {
    let accessToken: String
}

struct ImportManifest: Decodable {
    let protocolVersion: Int
    let sessionId: String
    let status: String
    let expiresAt: Date
    let assets: [ImportAsset]
}

struct ImportAsset: Decodable, Sendable {
    let assetId: String
    let filename: String
    let mimeType: String
    let byteSize: Int
    let sha256: String
    let downloadUrl: URL
}

enum MoveAPIError: Error { case invalidResponse, server(String), checksumMismatch }

actor NiziMoveAPI {
    private let baseURL = URL(string: "https://move.nizi.vn")!
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func claim(_ qr: NiziMoveQR) async throws -> String {
        var request = URLRequest(url: baseURL.appending(path: "/api/import-sessions/\(qr.sessionId)/claim"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["token": qr.pairingToken])
        let (data, response) = try await URLSession.shared.data(for: request)
        let envelope = try decoder.decode(ClaimEnvelope.self, from: data)
        guard let http = response as? HTTPURLResponse else { throw MoveAPIError.invalidResponse }
        guard (200...299).contains(http.statusCode), envelope.success,
              let token = envelope.data?.accessToken
        else { throw MoveAPIError.server(envelope.code ?? envelope.message ?? "CLAIM_FAILED") }
        return token
    }

    func manifest(sessionId: String, accessToken: String) async throws -> ImportManifest {
        var request = URLRequest(url: baseURL.appending(path: "/api/import-sessions/\(sessionId)/manifest"))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw MoveAPIError.invalidResponse
        }
        return try decoder.decode(ImportManifest.self, from: data)
    }

    func download(_ asset: ImportAsset, accessToken: String) async throws -> URL {
        var request = URLRequest(url: asset.downloadUrl)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw MoveAPIError.invalidResponse
        }
        let actual = try SHA256.hash(data: Data(contentsOf: temporaryURL))
            .map { String(format: "%02x", $0) }.joined()
        guard actual.caseInsensitiveCompare(asset.sha256) == .orderedSame else {
            throw MoveAPIError.checksumMismatch
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(asset.assetId)
            .appendingPathExtension(asset.filename.split(separator: ".").last.map(String.init) ?? "img")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }
}
```

`URLSessionDownloadTask`/`URLSession.shared.download` tiếp tục hỗ trợ request `Range` ở server. Với transfer lớn cần dùng background `URLSessionConfiguration.background(...)`, lưu byte offset/checkpoint theo asset và gửi `Range: bytes=<offset>-` khi retry. Không dùng `Data(contentsOf:)` trong production cho ảnh rất lớn: tính SHA-256 theo stream/file handle để không đưa cả asset vào RAM.

## 6. Hoàn tất từng asset

Sau khi Photos lưu thành công, gọi:

```http
POST /api/import-assets/{assetId}/completed
Authorization: Bearer <accessToken>
Content-Type: application/json
```

Lời gọi `/completed` có tính idempotent, nhưng đồng thời là điểm thu hồi không thể đảo ngược: server xoá file asset và khoá URL tải của chính asset đó. Chỉ gọi sau khi Photos trả thành công. Nếu không thể tải, kiểm checksum, hoặc lưu Photos, gọi `/failed` với body `{"reason":"PHOTO_SAVE_FAILED"}`. Sau đó tiếp tục các ảnh khác. Khi toàn bộ asset đã completed/skipped, gọi:

```http
POST /api/import-sessions/{sessionId}/completed
Authorization: Bearer <accessToken>
```

Lời gọi cuối cùng cũng thu hồi `accessToken` của native. Khi cần retry, người dùng phải tạo một Import Session mới từ web.

Xem danh sách API, mã lỗi và payload đầy đủ tại [API-IMPORT-BRIDGE.md](API-IMPORT-BRIDGE.md) và schema asset tại [IMPORT-MANIFEST.md](IMPORT-MANIFEST.md).
