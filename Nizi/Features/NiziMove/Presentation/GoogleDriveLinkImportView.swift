import SwiftUI
import SwiftData

struct GoogleDriveLinkImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var coordinator: GoogleDriveShareImportCoordinator

    init(modelContainer: ModelContainer, onSessionReady: @escaping @MainActor (String, String) async -> Void) {
        _coordinator = State(initialValue: GoogleDriveShareImportCoordinator(modelContainer: modelContainer, onSessionReady: onSessionReady))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch coordinator.screen {
                case .link: linkEntry
                case .browsing: gallery
                case .preparing: preparing
                }
            }
            .navigationTitle(title)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
            .alert("Không thể tiếp tục", isPresented: Binding(get: { coordinator.errorMessage != nil }, set: { if !$0 { coordinator.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(coordinator.errorMessage ?? "") }
            .task { await coordinator.restorePreparationIfNeeded() }
            .onChange(of: scenePhase) { _, phase in coordinator.isPollingEnabled = phase == .active }
        }
    }

    private var title: String {
        switch coordinator.screen { case .link: "Nhập từ Google Drive"; case .browsing: "Chọn ảnh"; case .preparing: "Đang chuẩn bị ảnh" }
    }

    private var linkEntry: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "link")
                .font(.system(size: 46)).foregroundStyle(.tint).padding(.top, 18)
            Text("Dán đường dẫn thư mục hoặc ảnh được chia sẻ.")
                .font(.title3.weight(.semibold))
            TextField("https://drive.google.com/...", text: $coordinator.link, axis: .vertical)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .textContentType(.URL).keyboardType(.URL)
                .padding(14).background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            Toggle("Bao gồm thư mục con", isOn: $coordinator.includeSubfolders)
            Text("Link cần có quyền xem phù hợp. Nizi không lưu tài khoản hoặc mật khẩu Google của bạn.")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
            Button("Kiểm tra liên kết") { Task { await coordinator.inspect() } }
                .buttonStyle(.borderedProminent).frame(maxWidth: .infinity).disabled(coordinator.link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || coordinator.isLoadingPage)
        }
        .padding(24)
    }

    private var gallery: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("\(coordinator.selectedItemIDs.count) ảnh đã chọn").font(.headline)
                    Text(ByteCountFormatter.string(fromByteCount: coordinator.selectedBytes, countStyle: .file)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Menu("Chọn") {
                    Button("Chọn tất cả đã tải") { coordinator.selectAllLoaded() }
                    Button("Bỏ chọn tất cả", role: .destructive) { coordinator.clearSelection() }
                }
            }.padding([.horizontal, .top], 16)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                    ForEach(coordinator.items) { item in
                        thumbnail(item)
                            .onAppear { Task { await coordinator.loadMoreIfNeeded(after: item) } }
                    }
                }.padding(16)
                if coordinator.isLoadingPage { ProgressView().padding(.bottom, 12) }
            }
            VStack(spacing: 12) {
                Picker("Chế độ nhập", selection: $coordinator.mode) {
                    ForEach(GoogleDriveImportMode.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Text(coordinator.mode.detail).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                Button("Chuẩn bị \(coordinator.selectedItemIDs.count) ảnh") { Task { await coordinator.createSessionAndPrepare() } }
                    .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                    .disabled(coordinator.selectedItemIDs.isEmpty || coordinator.isCreatingSession)
            }.padding(16).background(.bar)
        }
    }

    private func thumbnail(_ item: GoogleDriveInspectionItem) -> some View {
        Button { coordinator.toggle(item) } label: {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: item.thumbnailUrl) { image in image.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.16).overlay { Image(systemName: "photo").foregroundStyle(.secondary) } }
                    .frame(height: 104).clipShape(RoundedRectangle(cornerRadius: 10))
                Image(systemName: coordinator.selectedItemIDs.contains(item.itemId) ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(coordinator.selectedItemIDs.contains(item.itemId) ? Color.accentColor : .white).padding(6).shadow(radius: 2)
                if !item.canDownload { Color.black.opacity(0.5).clipShape(RoundedRectangle(cornerRadius: 10)).overlay { Image(systemName: "exclamationmark.triangle").foregroundStyle(.white) } }
            }
            Text(item.name).font(.caption).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain).disabled(!item.canDownload).opacity(item.canDownload ? 1 : 0.6)
    }

    private var preparing: some View {
        VStack(spacing: 18) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("Đang chuẩn bị ảnh trên Nizi Move").font(.title3.weight(.semibold))
            if let progress = coordinator.progress {
                Text("\(progress.readyAssets) / \(progress.totalAssets) ảnh đã sẵn sàng")
                    .foregroundStyle(.secondary)
                if let currentFileName = progress.currentFileName {
                    Text("Đang chuẩn bị \(currentFileName)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                ProgressView(value: Double(progress.readyAssets + progress.failedAssets), total: Double(max(progress.totalAssets, 1))).padding(.horizontal, 28)
                if progress.failedAssets > 0 { Text("\(progress.failedAssets) ảnh không thể chuẩn bị.").font(.footnote).foregroundStyle(.secondary) }
            } else { Text("Đang kết nối với Nizi Move…").foregroundStyle(.secondary) }
            Spacer()
            Button("Hủy phiên", role: .destructive) { Task { await coordinator.cancel() } }
        }.padding(24)
    }
}
