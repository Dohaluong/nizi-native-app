import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class GoogleDriveShareImportCoordinator {
    enum Screen { case link, browsing, preparing }

    private let api = GoogleDriveShareAPI()
    private let modelContainer: ModelContainer
    private let onSessionReady: @MainActor (String, String) async -> Void
    private var inspectionID: String?
    private var inspectionSource: GoogleDriveInspectionSource?
    private var nextCursor: String?
    private var createdSession: GoogleDriveCreatedImportSession?

    var screen: Screen = .link
    var link = ""
    var includeSubfolders = false
    var items: [GoogleDriveInspectionItem] = []
    var selectedItemIDs: Set<String> = []
    var mode: GoogleDriveImportMode = .optimized
    var isLoadingPage = false
    var isCreatingSession = false
    var isPollingEnabled = true
    var progress: GoogleDriveImportSessionProgress?
    var errorMessage: String?

    init(modelContainer: ModelContainer, onSessionReady: @escaping @MainActor (String, String) async -> Void) {
        self.modelContainer = modelContainer
        self.onSessionReady = onSessionReady
    }

    var selectedItems: [GoogleDriveInspectionItem] { items.filter { selectedItemIDs.contains($0.itemId) } }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
    var canLoadMore: Bool { nextCursor != nil && !isLoadingPage }

    func inspect() async {
        isLoadingPage = true
        defer { isLoadingPage = false }
        do {
            let page = try await api.inspect(url: link, includeSubfolders: includeSubfolders)
            inspectionID = page.inspectionID; inspectionSource = page.source; nextCursor = page.nextCursor
            items = page.items; selectedItemIDs.removeAll(); screen = .browsing
        } catch { errorMessage = error.localizedDescription }
    }

    func loadMoreIfNeeded(after item: GoogleDriveInspectionItem) async {
        guard item.id == items.last?.id, let inspectionID, let inspectionSource, let nextCursor, !isLoadingPage else { return }
        isLoadingPage = true
        defer { isLoadingPage = false }
        do {
            let page = try await api.nextPage(inspectionID: inspectionID, cursor: nextCursor, source: inspectionSource)
            let existing = Set(items.map(\.itemId))
            items += page.items.filter { !existing.contains($0.itemId) }
            self.nextCursor = page.nextCursor
        } catch { errorMessage = error.localizedDescription }
    }

    func toggle(_ item: GoogleDriveInspectionItem) {
        guard item.canDownload else { return }
        if !selectedItemIDs.insert(item.itemId).inserted { selectedItemIDs.remove(item.itemId) }
    }

    func selectAllLoaded() { selectedItemIDs.formUnion(items.filter(\.canDownload).map(\.itemId)) }
    func clearSelection() { selectedItemIDs.removeAll() }

    func createSessionAndPrepare() async {
        guard let inspectionID else { return }
        isCreatingSession = true
        defer { isCreatingSession = false }
        do {
            let session = try await api.createSession(inspectionID: inspectionID, selectedItemIDs: Array(selectedItemIDs), mode: mode)
            try NiziMoveKeychain.save(accessToken: session.nativeAccessToken, sessionID: session.sessionID)
            try await GoogleDrivePreparationStore(modelContainer: modelContainer).save(sessionID: session.sessionID, totalAssets: selectedItemIDs.count, mode: mode)
            createdSession = session; screen = .preparing
            try await waitUntilReady(session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancel() async {
        guard let createdSession else { screen = .link; return }
        do { try await api.cancel(sessionID: createdSession.sessionID, accessToken: createdSession.nativeAccessToken) }
        catch { errorMessage = error.localizedDescription; return }
        NiziMoveKeychain.delete(sessionID: createdSession.sessionID)
        try? await GoogleDrivePreparationStore(modelContainer: modelContainer).delete(sessionID: createdSession.sessionID)
        self.createdSession = nil; screen = .link
    }

    func restorePreparationIfNeeded() async {
        do {
            let store = GoogleDrivePreparationStore(modelContainer: modelContainer)
            guard let pending = try await store.latest(), let token = try NiziMoveKeychain.accessToken(sessionID: pending.sessionID) else { return }
            let session = GoogleDriveCreatedImportSession(sessionID: pending.sessionID, nativeAccessToken: token, status: "preparing")
            createdSession = session; mode = pending.mode; screen = .preparing
            try await waitUntilReady(session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func waitUntilReady(_ session: GoogleDriveCreatedImportSession) async throws {
        while !Task.isCancelled {
            guard isPollingEnabled else {
                try await Task.sleep(for: .seconds(2))
                continue
            }
            let status = try await api.sessionStatus(sessionID: session.sessionID, accessToken: session.nativeAccessToken)
            progress = status
            switch status.status.lowercased() {
            case "ready":
                await onSessionReady(session.sessionID, session.nativeAccessToken)
                try? await GoogleDrivePreparationStore(modelContainer: modelContainer).delete(sessionID: session.sessionID)
                return
            case "failed", "expired", "cancelled":
                NiziMoveKeychain.delete(sessionID: session.sessionID)
                try? await GoogleDrivePreparationStore(modelContainer: modelContainer).delete(sessionID: session.sessionID)
                throw status.status.lowercased() == "expired" ? GoogleDriveShareImportError.sessionExpired : GoogleDriveShareImportError.unexpected
            default:
                try await Task.sleep(for: .seconds(2))
            }
        }
    }
}
