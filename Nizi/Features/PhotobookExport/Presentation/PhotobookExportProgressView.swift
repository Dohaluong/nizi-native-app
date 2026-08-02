//
//  PhotobookExportProgressView.swift
//  Nizi
//
//  Created by Do Ha Luong on 8/2/26.
//

import SwiftUI

/// The sheet `AlbumDetailView`'s "Download PDF" button presents — progress across both real
/// phases (§ user request: "Đang tạo trang X/Y" then "Đang hoàn thiện PDF"), a clear error if a
/// photo couldn't be fetched, and the Share Sheet once the file is ready.
struct PhotobookExportProgressView: View {
    @Bindable var session: PhotobookExportSession
    let draft: AlbumDraft
    let onDismiss: () -> Void

    /// Distinguishes "sheet just opened, export hasn't started yet" from "the user cancelled and
    /// the session is back to `.idle`" — both read as `.idle` on `session.state`, but only the
    /// second should show a neutral "cancelled" screen instead of silently starting a fresh
    /// export a second time.
    @State private var wasCancelledByUser = false

    var body: some View {
        VStack(spacing: 24) {
            switch session.state {
            case .idle:
                if wasCancelledByUser {
                    cancelledContent()
                } else {
                    ProgressView()
                }
            case .cancelling:
                cancellingContent()
            case let .exporting(progress):
                exportingContent(progress)
            case let .completed(fileURL):
                completedContent(fileURL)
            case let .failed(message):
                failedContent(message)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .interactiveDismissDisabled(isBusy)
        // `.task`, not `.onAppear` inside the `.idle` case's own body — this runs exactly once
        // per sheet presentation (SwiftUI only re-runs `.task` if the view itself is torn down
        // and recreated, i.e. the sheet closes and reopens), instead of re-firing every time
        // `session.state` happens to read `.idle` again — which it does after a completed
        // cancellation, and re-starting the export right then would silently undo the user's own
        // Cancel tap.
        .task {
            session.start(draft: draft)
        }
    }

    private var isBusy: Bool {
        switch session.state {
        case .exporting, .cancelling: return true
        case .idle, .completed, .failed: return false
        }
    }

    private func exportingContent(_ progress: PhotobookExportProgress) -> some View {
        VStack(spacing: 20) {
            // § user report — "khi ẩn dòng thì vị trí các bar/text lại dịch chuyển, rung bần
            // bật": both the linear/circular ProgressView swap and the second text line
            // appearing/disappearing used to add or remove a view from the VStack outright,
            // which changes its measured height and shifts everything below. Every state below
            // now keeps ALL views permanently present (fixed layout, fixed position) and only
            // toggles `.opacity` to show/hide — nothing is ever inserted or removed.
            ZStack {
                ProgressView(value: progress.fraction ?? 0)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 240)
                    .opacity(progress.fraction != nil ? 1 : 0)
                ProgressView()
                    .opacity(progress.fraction != nil ? 0 : 1)
            }
            Text(phaseText(progress.phase))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("common.action.cancel", role: .cancel) {
                wasCancelledByUser = true
                session.cancel()
            }
            .buttonStyle(.bordered)
        }
    }

    private func cancellingContent() -> some View {
        VStack(spacing: 20) {
            ProgressView()
            Text("photobook.export.progress.cancelling")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func cancelledContent() -> some View {
        VStack(spacing: 20) {
            Text("photobook.export.cancelled.title")
                .font(.headline)
            Button("common.action.done") { onDismiss() }
                .buttonStyle(.bordered)
        }
    }

    private func phaseText(_ phase: PhotobookExportPhase) -> String {
        switch phase {
        case let .renderingPage(page, totalPages):
            guard page > 0, totalPages > 0 else {
                return localizedString("photobook.export.progress.preparing", defaultValue: "Preparing…")
            }
            return localizedString(
                "photobook.export.progress.page",
                defaultValue: "Đang tạo trang \(Self.paddedPageNumber(page, totalPages: totalPages))/\(totalPages)"
            )
        case .finalizingPDF:
            return localizedString("photobook.export.progress.finalizing", defaultValue: "Đang hoàn thiện PDF")
        }
    }

    /// § user report — "chỉ nên thay đổi phần số, còn cả dòng text nên fix": zero-pads the
    /// current page to the same digit width as `totalPages` (e.g. "03/12", not "3/12") so the
    /// string's length — and with `.monospacedDigit()` on the `Text` above, its exact rendered
    /// width — never changes as the count increments. Only the digits themselves visibly change;
    /// the rest of the centered line stays pinned in place instead of re-centering on every tick.
    private static func paddedPageNumber(_ page: Int, totalPages: Int) -> String {
        let digits = String(totalPages).count
        return String(format: "%0\(digits)d", page)
    }

    private func completedContent(_ fileURL: URL) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("photobook.export.completed.title")
                .font(.headline)
            ShareLink(item: fileURL) {
                Label("photobook.export.action.share", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Button("common.action.done") { onDismiss() }
                .buttonStyle(.bordered)
        }
    }

    private func failedContent(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("common.action.retry") {
                wasCancelledByUser = false
                session.start(draft: draft)
            }
            .buttonStyle(.borderedProminent)
            Button("common.action.cancel", role: .cancel) { onDismiss() }
                .buttonStyle(.bordered)
        }
    }
}
