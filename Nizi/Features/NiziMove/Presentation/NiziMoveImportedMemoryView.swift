import SwiftData
import SwiftUI

/// Immediate destination after a Move import, so the user can verify the persisted Event/Memory
/// without having to navigate through Home's asynchronously refreshed rails.
struct NiziMoveImportedMemoryView: View {
    let modelContainer: ModelContainer
    let eventID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var event: PhotoEvent?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let event {
                MemoryDetailView(event: event)
            } else if let errorMessage {
                ContentUnavailableView("Không thể mở Event Memory", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else {
                ProgressView("Đang mở Event Memory…")
            }
        }
        .task {
            do {
                event = try await SwiftDataMemoryDiscoveryStore(modelContainer: modelContainer)
                    .fetchEvents(ids: [eventID])
                    .first
                if event == nil { errorMessage = "Không tìm thấy Event vừa tạo." }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .overlay(alignment: .topTrailing) {
            Button("Đóng") { dismiss() }
                .padding()
        }
    }
}
