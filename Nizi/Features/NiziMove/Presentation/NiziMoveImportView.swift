import SwiftData
import SwiftUI

struct NiziMoveImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var coordinator: NiziMoveImportCoordinator
    @State private var manualCode = ""
    @State private var showManual = false

    init(modelContainer: ModelContainer) { _coordinator = State(initialValue: NiziMoveImportCoordinator(modelContainer: modelContainer)) }

    var body: some View {
        NavigationStack {
            Group {
                switch coordinator.screen {
                case .introduction: introduction
                case .scanner: scanner
                case .confirmation: confirmation
                case .progress: progress
                case .result: result
                }
            }
            .padding(24)
            .navigationTitle("Nhập ảnh từ máy tính")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
            .alert("Không thể tiếp tục", isPresented: Binding(get: { coordinator.errorMessage != nil }, set: { if !$0 { coordinator.errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(coordinator.errorMessage ?? "") }
            .task { await coordinator.restoreMostRecentIfNeeded() }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer(); Image(systemName: "rectangle.on.rectangle.angled").font(.system(size: 54)).foregroundStyle(.tint)
            Text("Chuyển ảnh từ máy tính").font(.title.bold())
            Text("1. Mở move.nizi.vn trên máy tính.\n2. Chọn và chuẩn bị ảnh.\n3. Quét mã QR để chuyển vào Nizi.").foregroundStyle(.secondary)
            Spacer()
            Button("Quét mã QR") { coordinator.screen = .scanner }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
            Button("Nhập mã thủ công") { showManual = true }.frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showManual) {
            NavigationStack {
                Form {
                    TextField("Mã hoặc URL Nizi Move", text: $manualCode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .navigationTitle("Nhập mã")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Tiếp tục") {
                            showManual = false
                            Task { await receive(raw: manualCode) }
                        }
                    }
                }
            }
        }
    }
    private var scanner: some View { NiziMoveQRScannerView { result in if case .success(let qr) = result { Task { await coordinator.receive(qr: qr) } } else if case .failure(let error) = result { coordinator.errorMessage = error.localizedDescription } }.ignoresSafeArea() }
    private var confirmation: some View { VStack(alignment: .leading, spacing: 18) { Spacer(); Text("Sẵn sàng chuyển ảnh").font(.title.bold()); Text("\(coordinator.totalCount) ảnh\n\(ByteCountFormatter.string(fromByteCount: coordinator.totalBytes, countStyle: .file))\nDữ liệu sẽ được lưu vào Photos và sắp xếp trong Nizi.").font(.title3).foregroundStyle(.secondary); Spacer(); Button("Bắt đầu nhập ảnh") { Task { await coordinator.start() } }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity); Button("Hủy") { dismiss() }.frame(maxWidth: .infinity) } }
    private var progress: some View { VStack(alignment: .leading, spacing: 18) { Spacer(); Text("Đang chuyển ảnh từ máy tính").font(.title2.bold()); Text("\(coordinator.completedCount)/\(coordinator.totalCount) ảnh").font(.title); Text("Đã lưu vào Photos: \(coordinator.completedCount) ảnh").foregroundStyle(.secondary); ProgressView(value: Double(coordinator.completedCount + coordinator.failedCount), total: Double(max(coordinator.totalCount, 1))); Spacer(); Button("Tạm dừng") { coordinator.pause() }.buttonStyle(.bordered); Button("Hủy phiên", role: .destructive) { coordinator.cancel() } } }
    private var result: some View { VStack(alignment: .leading, spacing: 18) { Spacer(); Image(systemName: "checkmark.circle.fill").font(.system(size: 54)).foregroundStyle(.green); Text("Đã chuyển ảnh vào Nizi").font(.title.bold()); Text("\(coordinator.completedCount) ảnh đã được lưu\n\(coordinator.failedCount) ảnh không thể chuyển").foregroundStyle(.secondary); Spacer(); Button("Xong") { dismiss() }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity) } }
    private func receive(raw: String) async { do { try await coordinator.receive(qr: parseNiziMoveQR(raw)) } catch { coordinator.errorMessage = error.localizedDescription } }
}
