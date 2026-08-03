import SwiftData
import SwiftUI
import UIKit

struct NiziMoveImportView: View {
    @Environment(\.dismiss) private var dismiss
    private let modelContainer: ModelContainer
    @State private var coordinator: NiziMoveImportCoordinator
    @State private var manualCode = ""
    @State private var showManual = false
    @State private var showImportedMemory = false

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        _coordinator = State(initialValue: NiziMoveImportCoordinator(modelContainer: modelContainer))
    }

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
            .alert("Không thể tiếp tục", isPresented: Binding(get: { coordinator.errorMessage != nil }, set: { if !$0 { coordinator.errorMessage = nil } })) {
                Button("Sao chép nội dung") {
                    UIPasteboard.general.string = coordinator.errorMessage ?? ""
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text(coordinator.errorMessage ?? "")
            }
            .task { await coordinator.restoreMostRecentIfNeeded() }
        }
        .fullScreenCover(isPresented: $showImportedMemory) {
            if let eventID = coordinator.importedEventID {
                NiziMoveImportedMemoryView(modelContainer: modelContainer, eventID: eventID)
            }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .padding(.top, 12)
            Text("Chuyển ảnh từ máy tính")
                .font(.title.bold())
            Text("Làm theo các bước sau để đưa ảnh vào Nizi trên iPhone.")
                .foregroundStyle(.secondary)

            instructionCard(
                number: 1,
                icon: "laptopcomputer",
                title: "Mở Nizi Move trên máy tính",
                detail: "Trên máy tính, mở website: move.nizi.vn"
            )
            instructionCard(
                number: 2,
                icon: "photo.on.rectangle.angled",
                title: "Chọn ảnh cần chuyển",
                detail: "Chọn những ảnh bạn muốn chuyển sang Nizi trên iPhone."
            )
            instructionCard(
                number: 3,
                icon: "qrcode",
                title: "Quét mã QR",
                detail: "Khi chuyển xong, máy tính sẽ hiển thị mã QR. Hãy ấn nút bên dưới để quét và bắt đầu nhập ảnh."
            )

            Spacer(minLength: 4)
            Button("Quét mã QR") { coordinator.screen = .scanner }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            Button("Nhập mã thủ công") { showManual = true }
                .frame(maxWidth: .infinity)
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

    private func instructionCard(number: Int, icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Label(title, systemImage: icon)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    private var scanner: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 8)
            Text("Quét mã QR")
                .font(.title.bold())
            NiziMoveQRScannerView { result in
                if case .success(let qr) = result {
                    Task { await coordinator.receive(qr: qr) }
                } else if case .failure(let error) = result {
                    coordinator.errorMessage = error.localizedDescription
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(0.28), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            Text("Quét mã QR trên máy tính tại trang move.nizi.vn để chuyển ảnh về iPhone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
    private var confirmation: some View { VStack(alignment: .leading, spacing: 18) { Spacer(); Text("Sẵn sàng chuyển ảnh").font(.title.bold()); Text("\(coordinator.totalCount) ảnh\n\(ByteCountFormatter.string(fromByteCount: coordinator.totalBytes, countStyle: .file))\nDữ liệu sẽ được lưu vào Photos và sắp xếp trong Nizi.").font(.title3).foregroundStyle(.secondary); Spacer(); Button("Bắt đầu nhập ảnh") { Task { await coordinator.start() } }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity); Button("Hủy") { dismiss() }.frame(maxWidth: .infinity) } }
    private var progress: some View { VStack(alignment: .leading, spacing: 18) { Spacer(); Text("Đang chuyển ảnh từ máy tính").font(.title2.bold()); Text("\(coordinator.completedCount)/\(coordinator.totalCount) ảnh").font(.title); Text("Đã lưu vào Photos: \(coordinator.completedCount) ảnh").foregroundStyle(.secondary); ProgressView(value: Double(coordinator.completedCount + coordinator.failedCount), total: Double(max(coordinator.totalCount, 1))); Spacer(); Button("Tạm dừng") { coordinator.pause() }.buttonStyle(.bordered); Button("Hủy phiên", role: .destructive) { coordinator.cancel() } } }
    private var result: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 54)).foregroundStyle(.green)
            Text("Đã chuyển ảnh vào Nizi").font(.title.bold())
            Text("\(coordinator.completedCount) ảnh đã được lưu\n\(coordinator.failedCount) ảnh không thể chuyển").foregroundStyle(.secondary)
            if coordinator.importedEventID != nil {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Memory mới", systemImage: "sparkles")
                        .font(.headline)
                    Text("Các ảnh bạn vừa nhập đã được tự động tạo thành một Memory.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Xem") { showImportedMemory = true }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 12) {
                    Label(coordinator.didCreateTrip ? "Đã tạo Trip" : "Tạo Trip", systemImage: "suitcase.rolling")
                        .font(.headline)
                    Text(coordinator.didCreateTrip ? "Trip từ Memory này đã được lưu." : "Đây có phải là một chuyến đi không? Hãy lưu lại nhé.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if !coordinator.didCreateTrip {
                        Button("Tạo Trip") { Task { await coordinator.createTripFromImportedEvent() } }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            Spacer()
            Button("Xong") { dismiss() }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
        }
    }
    private func receive(raw: String) async { do { try await coordinator.receive(qr: parseNiziMoveQR(raw)) } catch { coordinator.errorMessage = error.localizedDescription } }
}
