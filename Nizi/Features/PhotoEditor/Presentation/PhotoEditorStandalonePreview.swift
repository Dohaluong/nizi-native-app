//
//  PhotoEditorStandalonePreview.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import SwiftUI
import SwiftData

/// Design-preview/manual-QA harness for opening Photo Editor with `.standalone` — the same role
/// `AlbumDraftPlanningPreview` plays for the Album Draft Planner. There is no real single-photo
/// caller anywhere in the app yet (Search/Favorites/Photobook are all future work per
/// PHOTO-EDITOR.md § 4.4), so this is what exercises "mở độc lập với một ảnh" until one exists —
/// synthetic pixels only (no Photos Library access), but Bước 7 onward this saves through the
/// *real* `SwiftDataPhotoEditRepository`, so closing and reopening the editor here is an actual
/// test of "mở lại recipe đã lưu" (§ 6.4), not just an in-memory simulation of it.
struct PhotoEditorStandalonePreview: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isPresentingEditor = false
    @State private var lastResult: PhotoEditorResult?

    var body: some View {
        VStack(spacing: 16) {
            Text("Photo Editor — Standalone")
                .font(.headline)
            Button("Open Editor") { isPresentingEditor = true }
                .buttonStyle(.borderedProminent)
            if let lastResult {
                Text(lastResult.didSave ? "Last result: saved" : "Last result: cancelled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .fullScreenCover(isPresented: $isPresentingEditor) {
            PhotoEditorView(
                context: .standalone(photoId: "preview-photo-1"),
                renderEngine: MockPhotoRendering(),
                repository: SwiftDataPhotoEditRepository(modelContainer: modelContext.container),
                autoEnhanceService: MockAutoEnhancing()
            ) { result in
                lastResult = result
                isPresentingEditor = false
            }
        }
    }
}

#Preview {
    PhotoEditorStandalonePreview()
        .modelContainer(for: [MDPhotoEditRecipe.self], inMemory: true)
}
