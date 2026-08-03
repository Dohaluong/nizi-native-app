import Foundation

enum NiziMoveAssetStatus: String, Codable, CaseIterable {
    case pending, downloading, downloaded, verified, savingToPhotos, savedToPhotos, indexed, serverAcknowledged, failed, skipped
}

enum NiziMoveSessionStatus: String, Codable, CaseIterable {
    case claimed, ready, importing, paused, partiallyCompleted, processingLibrary, completed, failed, expired, cancelled
}

struct NiziMoveQR: Sendable, Equatable {
    let sessionID: String
    let pairingToken: String
}

enum NiziMoveError: LocalizedError, Equatable {
    case invalidCode, pairingTokenInvalid, invalidManifest, unsupportedProtocol, insufficientStorage, photosPermission, expired, incompatibleServer, server(String)

    var errorDescription: String? {
        switch self {
        case .invalidCode: "Đây không phải mã chuyển ảnh Nizi Move hợp lệ."
        case .pairingTokenInvalid: "Mã đã hết hạn hoặc đã được sử dụng. Hãy tạo mã mới trên máy tính."
        case .invalidManifest: "Dữ liệu chuyển ảnh không hợp lệ."
        case .unsupportedProtocol: "Phiên bản chuyển ảnh này chưa được Nizi hỗ trợ."
        case .insufficientStorage: "Thiết bị không còn đủ dung lượng trống để nhập ảnh."
        case .photosPermission: "Nizi cần quyền truy cập đầy đủ vào Photos để lưu và sắp xếp ảnh."
        case .expired: "Phiên chuyển ảnh đã hết hạn."
        case .incompatibleServer: "Nizi Move trên máy chủ chưa trả access token cho iPhone. Hãy cập nhật Nizi Move rồi tạo mã QR mới."
        case .server(let code): "Không thể chuyển ảnh lúc này (\(code))."
        }
    }
}

func parseNiziMoveQR(_ rawValue: String) throws -> NiziMoveQR {
    let pathParts: [Substring]
    if let components = URLComponents(string: rawValue) {
        pathParts = components.path.split(separator: "/", omittingEmptySubsequences: true)
    } else {
        pathParts = []
    }
    guard let components = URLComponents(string: rawValue),
          components.scheme?.lowercased() == "https",
          components.host?.lowercased() == "move.nizi.vn",
          components.port == nil,
          pathParts.count == 2,
          pathParts[0] == "import",
          pathParts[1].hasPrefix("imp_"),
          let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
          !token.isEmpty
    else { throw NiziMoveError.invalidCode }
    return NiziMoveQR(sessionID: String(pathParts[1]), pairingToken: token)
}

struct NiziMoveManifest: Sendable, Equatable {
    let protocolVersion: Int
    let sessionID: String
    let status: String
    let expiresAt: Date
    let assets: [NiziMoveManifestAsset]
}

struct NiziMoveManifestAsset: Sendable, Equatable {
    let assetID: String
    let filename: String
    let mimeType: String
    let byteSize: Int64
    let sha256: String
    let downloadURL: URL
    let capturedAt: Date?
    let latitude: Double?
    let longitude: Double?
    let relativePath: String?
}
