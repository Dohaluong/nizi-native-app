import Foundation

enum GoogleDriveImportMode: String, CaseIterable, Identifiable, Sendable {
    case keepOriginal = "keep_original"
    case optimized

    var id: String { rawValue }
    var title: String { self == .keepOriginal ? "Giữ nguyên ảnh gốc" : "Tối ưu dung lượng" }
    var detail: String { self == .keepOriginal ? "Giữ định dạng và kích thước gốc." : "Nizi Move tối ưu ảnh trên máy chủ trước khi nhập." }
}

struct GoogleDriveInspectionSource: Decodable, Sendable, Equatable {
    let type: String
    let name: String
}

struct GoogleDriveInspectionItem: Decodable, Identifiable, Sendable, Equatable {
    let itemId: String
    let name: String
    let mimeType: String
    let size: Int64
    let width: Int?
    let height: Int?
    let modifiedTime: Date?
    let thumbnailUrl: URL?
    let canDownload: Bool

    var id: String { itemId }

    func resolvingThumbnailURL(against baseURL: URL) -> GoogleDriveInspectionItem {
        guard let thumbnailUrl, thumbnailUrl.host == nil else { return self }
        return GoogleDriveInspectionItem(
            itemId: itemId, name: name, mimeType: mimeType, size: size, width: width, height: height,
            modifiedTime: modifiedTime, thumbnailUrl: URL(string: thumbnailUrl.relativeString, relativeTo: baseURL)?.absoluteURL,
            canDownload: canDownload
        )
    }
}

struct GoogleDriveInspectionPage: Sendable, Equatable {
    let inspectionID: String
    let source: GoogleDriveInspectionSource
    let items: [GoogleDriveInspectionItem]
    let nextCursor: String?
}

struct GoogleDriveCreatedImportSession: Sendable, Equatable {
    let sessionID: String
    let nativeAccessToken: String
    let status: String
}

struct GoogleDriveImportSessionProgress: Sendable, Equatable {
    let status: String
    let totalAssets: Int
    let readyAssets: Int
    let failedAssets: Int
    let currentFileName: String?
}

enum GoogleDriveShareImportError: LocalizedError {
    case disabled, invalidLink, inaccessible, noPhotos, expired, busy, sessionExpired, unauthorized, cancelled, unexpected

    var errorDescription: String? {
        switch self {
        case .disabled: "Máy chủ chưa bật tính năng nhập từ Google Drive."
        case .invalidLink: "Liên kết Google Drive không hợp lệ. Hãy dán lại liên kết được chia sẻ."
        case .inaccessible: "Không thể truy cập liên kết này. Hãy kiểm tra quyền chia sẻ trên Google Drive."
        case .noPhotos: "Không tìm thấy ảnh có thể nhập trong liên kết này."
        case .expired: "Kết quả kiểm tra liên kết đã hết hạn. Hãy kiểm tra lại liên kết."
        case .busy: "Nizi Move đang bận chuẩn bị ảnh. Hãy thử lại sau ít phút."
        case .sessionExpired: "Phiên nhập ảnh đã hết hạn. Hãy tạo lại từ liên kết Google Drive."
        case .unauthorized: "Phiên nhập ảnh không còn được xác thực. Hãy tạo lại từ liên kết Google Drive."
        case .cancelled: "Phiên nhập đã được hủy."
        case .unexpected: "Không thể tiếp tục nhập ảnh lúc này. Hãy thử lại."
        }
    }
}
