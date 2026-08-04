import Foundation

actor GoogleDriveShareAPI {
    private let baseURL = URL(string: "https://move.nizi.vn")!
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            for options: ISO8601DateFormatter.Options in [[.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime]] {
                let formatter = ISO8601DateFormatter(); formatter.formatOptions = options
                if let date = formatter.date(from: value) { return date }
            }
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Invalid ISO-8601 date")
        }
        return decoder
    }()

    func inspect(url: String, includeSubfolders: Bool = false) async throws -> GoogleDriveInspectionPage {
        guard !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GoogleDriveShareImportError.invalidLink }
        var request = URLRequest(url: baseURL.appending(path: "/api/google-drive-share/inspect"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(InspectRequest(url: url, includeSubfolders: includeSubfolders))
        let (data, response) = try await URLSession.shared.data(for: request)
        let payload = try decode(InspectionResponse.self, data: data, response: response)
        guard payload.success, let source = payload.source else { throw mappedError(payload.code) }
        guard !payload.items.isEmpty else { throw GoogleDriveShareImportError.noPhotos }
        guard let inspectionID = payload.inspectionId else { throw GoogleDriveShareImportError.unexpected }
        return GoogleDriveInspectionPage(inspectionID: inspectionID, source: source, items: payload.items.map { $0.resolvingThumbnailURL(against: baseURL) }, nextCursor: payload.nextCursor)
    }

    func nextPage(inspectionID: String, cursor: String, source: GoogleDriveInspectionSource) async throws -> GoogleDriveInspectionPage {
        var components = URLComponents(url: baseURL.appending(path: "/api/google-drive-share/inspections/\(inspectionID)/items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "cursor", value: cursor)]
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: components.url!))
        let payload = try decode(InspectionResponse.self, data: data, response: response)
        guard payload.success else { throw mappedError(payload.code) }
        return GoogleDriveInspectionPage(inspectionID: payload.inspectionId ?? inspectionID, source: payload.source ?? source, items: payload.items.map { $0.resolvingThumbnailURL(against: baseURL) }, nextCursor: payload.nextCursor)
    }

    func createSession(inspectionID: String, selectedItemIDs: [String], mode: GoogleDriveImportMode) async throws -> GoogleDriveCreatedImportSession {
        guard !selectedItemIDs.isEmpty else { throw GoogleDriveShareImportError.noPhotos }
        var request = URLRequest(url: baseURL.appending(path: "/api/google-drive-share/import-sessions"))
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(CreateSessionRequest(inspectionId: inspectionID, selectedItemIds: selectedItemIDs, mode: mode.rawValue, clientType: "nizi_native"))
        let (data, response) = try await URLSession.shared.data(for: request)
        let payload = try decode(CreateSessionResponse.self, data: data, response: response)
        guard payload.success, let sessionID = payload.sessionId, let token = payload.nativeAccessToken, !token.isEmpty else { throw mappedError(payload.code) }
        return GoogleDriveCreatedImportSession(sessionID: sessionID, nativeAccessToken: token, status: payload.status ?? "preparing")
    }

    func sessionStatus(sessionID: String, accessToken: String) async throws -> GoogleDriveImportSessionProgress {
        var request = URLRequest(url: baseURL.appending(path: "/api/import-sessions/\(sessionID)"))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let payload = try decode(StatusResponse.self, data: data, response: response)
        guard payload.success else { throw mappedError(payload.code) }
        let session = payload.session
        return GoogleDriveImportSessionProgress(status: session.status, totalAssets: session.totalAssets, readyAssets: session.readyAssets, failedAssets: session.failedAssets)
    }

    func cancel(sessionID: String, accessToken: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "/api/import-sessions/\(sessionID)"))
        request.httpMethod = "DELETE"; request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw GoogleDriveShareImportError.unexpected }
    }

    private func decode<T: Decodable>(_ type: T.Type, data: Data, response: URLResponse) throws -> T {
        guard let http = response as? HTTPURLResponse else { throw GoogleDriveShareImportError.unexpected }
        guard (200...299).contains(http.statusCode) else { throw mappedError(nil, statusCode: http.statusCode) }
        do { return try decoder.decode(type, from: data) } catch { throw GoogleDriveShareImportError.unexpected }
    }

    private func mappedError(_ code: String?, statusCode: Int? = nil) -> GoogleDriveShareImportError {
        switch code ?? "" {
        case "INVALID_URL", "INVALID_GOOGLE_DRIVE_URL", "GOOGLE_DRIVE_INVALID_LINK", "GOOGLE_DRIVE_UNSUPPORTED_LINK": .invalidLink
        case "ACCESS_DENIED", "GOOGLE_DRIVE_ACCESS_DENIED", "NOT_FOUND", "GOOGLE_DRIVE_PERMISSION_DENIED", "GOOGLE_DRIVE_RESOURCE_NOT_FOUND": .inaccessible
        case "NO_IMAGES_FOUND", "GOOGLE_DRIVE_NO_SUPPORTED_IMAGES": .noPhotos
        case "INSPECTION_EXPIRED", "GOOGLE_DRIVE_INSPECTION_EXPIRED": .expired
        case "SESSION_EXPIRED": .sessionExpired
        case "CANCELLED": .cancelled
        case "SERVER_BUSY", "RATE_LIMITED", "GOOGLE_DRIVE_RATE_LIMITED", "GOOGLE_DRIVE_TOO_MANY_FILES", "GOOGLE_DRIVE_TOO_MANY_SELECTED_FILES": .busy
        default: statusCode == 401 || statusCode == 403 ? .inaccessible : .unexpected
        }
    }
}

private struct InspectRequest: Encodable { let url: String; let includeSubfolders: Bool }
private struct CreateSessionRequest: Encodable { let inspectionId: String; let selectedItemIds: [String]; let mode: String; let clientType: String }
private struct InspectionResponse: Decodable {
    let success: Bool; let inspectionId: String?; let source: GoogleDriveInspectionSource?; let items: [GoogleDriveInspectionItem]; let nextCursor: String?; let code: String?
}
private struct CreateSessionResponse: Decodable { let success: Bool; let sessionId: String?; let nativeAccessToken: String?; let status: String?; let code: String? }
private struct StatusResponse: Decodable {
    let success: Bool; let session: Session; let code: String?
    struct Session: Decodable { let status: String; let totalAssets: Int; let readyAssets: Int; let failedAssets: Int }
}
