import Foundation

actor NiziMoveAPI {
    private let baseURL = URL(string: "https://move.nizi.vn")!
    private let allowedDownloadHosts: Set<String> = ["move.nizi.vn"]
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        // The bridge uses ISO-8601 timestamps with milliseconds (for example
        // `2026-08-04T06:57:35.018Z`); JSONDecoder.iso8601 does not accept that form.
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractionalFormatter.date(from: value) {
                return date
            }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO-8601 date, received \(value)"
            )
        }
        return decoder
    }()

    func claim(_ qr: NiziMoveQR) async throws -> String {
        var request = URLRequest(url: baseURL.appending(path: "/api/import-sessions/\(qr.sessionID)/claim"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["token": qr.pairingToken])
        let (data, response) = try await URLSession.shared.data(for: request)
        let envelope = try decodeResponse(Envelope<ClaimData>.self, from: data, endpoint: "POST /claim", response: response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), envelope.success else {
            if (response as? HTTPURLResponse)?.statusCode == 401, envelope.code == "INVALID_PAIRING_TOKEN" { throw NiziMoveError.pairingTokenInvalid }
            throw NiziMoveError.server(envelope.code ?? "CLAIM_FAILED")
        }
        guard let token = envelope.data?.accessToken, !token.isEmpty else { throw NiziMoveError.incompatibleServer }
        return token
    }

    func manifest(sessionID: String, accessToken: String) async throws -> NiziMoveManifest {
        let data = try await request(path: "/api/import-sessions/\(sessionID)/manifest", token: accessToken)
        // Production returns the manifest itself at the response root. Keep accepting the
        // envelope variant as well so native remains compatible with either v1 deployment.
        let payload: ManifestPayload
        if let envelope = try? decoder.decode(Envelope<ManifestPayload>.self, from: data),
           envelope.success,
           let envelopedPayload = envelope.data {
            payload = envelopedPayload
        } else {
            payload = try decodeResponse(ManifestPayload.self, from: data, endpoint: "GET /manifest")
        }
        let manifest = try payload.domain()
        try validate(manifest, expectedSessionID: sessionID)
        return manifest
    }

    func download(_ asset: NiziMoveManifestAsset, accessToken: String) async throws -> URL {
        guard asset.downloadURL.scheme?.lowercased() == "https", let host = asset.downloadURL.host?.lowercased(), allowedDownloadHosts.contains(host) else { throw NiziMoveError.invalidManifest }
        var request = URLRequest(url: asset.downloadURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (url, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw NiziMoveError.server("DOWNLOAD_FAILED") }
        return url
    }

    func acknowledge(assetID: String, accessToken: String, failedReason: String? = nil) async throws {
        let path = "/api/import-assets/\(assetID)/\(failedReason == nil ? "completed" : "failed")"
        var request = URLRequest(url: baseURL.appending(path: path)); request.httpMethod = "POST"; request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let failedReason { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONEncoder().encode(["reason": failedReason]) }
        let (data, response) = try await URLSession.shared.data(for: request)
        let result = try? decoder.decode(Envelope<EmptyPayload>.self, from: data)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), result?.success != false else { throw NiziMoveError.server(result?.code ?? "ACKNOWLEDGEMENT_FAILED") }
    }

    func complete(sessionID: String, accessToken: String) async throws {
        _ = try await request(path: "/api/import-sessions/\(sessionID)/completed", method: "POST", token: accessToken)
    }

    private func request(path: String, method: String = "GET", token: String) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path)); request.httpMethod = method; request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw NiziMoveError.server("HTTP_\((response as? HTTPURLResponse)?.statusCode ?? 0)") }
        return data
    }

    private func validate(_ manifest: NiziMoveManifest, expectedSessionID: String) throws {
        guard manifest.protocolVersion == 1 else { throw NiziMoveError.unsupportedProtocol }
        guard manifest.sessionID == expectedSessionID, manifest.expiresAt > Date(), Set(manifest.assets.map(\.assetID)).count == manifest.assets.count else { throw NiziMoveError.invalidManifest }
        for asset in manifest.assets {
            guard !asset.assetID.isEmpty, asset.byteSize >= 0, asset.sha256.range(of: "^[A-Fa-f0-9]{64}$", options: .regularExpression) != nil else { throw NiziMoveError.invalidManifest }
        }
    }

    private func decodeResponse<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        endpoint: String,
        response: URLResponse? = nil
    ) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw NiziMoveResponseDecodingError(
                endpoint: endpoint,
                statusCode: (response as? HTTPURLResponse)?.statusCode,
                body: String(data: data, encoding: .utf8) ?? "<Phản hồi không phải văn bản UTF-8>",
                underlyingError: error
            )
        }
    }
}

private struct NiziMoveResponseDecodingError: LocalizedError {
    let endpoint: String
    let statusCode: Int?
    let body: String
    let underlyingError: Error

    var errorDescription: String? {
        """
        Không đọc được phản hồi từ \(endpoint)\(statusCode.map { " (HTTP \($0))" } ?? "").

        Server trả về:
        \(body)

        Chi tiết: \(underlyingError.localizedDescription)
        """
    }
}

private struct Envelope<T: Decodable>: Decodable { let success: Bool; let data: T?; let code: String?; let message: String? }
private struct ClaimData: Decodable { let accessToken: String? }
private struct EmptyPayload: Decodable {}
private struct ManifestPayload: Decodable {
    let protocolVersion: Int; let sessionId: String; let status: String; let expiresAt: Date; let assets: [Asset]
    struct Asset: Decodable {
        let assetId: String; let filename: String; let mimeType: String; let byteSize: Int64; let sha256: String; let downloadUrl: URL
        let capturedAt: Date?; let creationDate: Date?; let latitude: Double?; let longitude: Double?; let relativePath: String?
    }
    func domain() throws -> NiziMoveManifest {
        NiziMoveManifest(protocolVersion: protocolVersion, sessionID: sessionId, status: status, expiresAt: expiresAt, assets: assets.map {
            NiziMoveManifestAsset(assetID: $0.assetId, filename: $0.filename, mimeType: $0.mimeType, byteSize: $0.byteSize, sha256: $0.sha256, downloadURL: $0.downloadUrl, capturedAt: $0.capturedAt ?? $0.creationDate, latitude: $0.latitude, longitude: $0.longitude, relativePath: $0.relativePath)
        })
    }
}
