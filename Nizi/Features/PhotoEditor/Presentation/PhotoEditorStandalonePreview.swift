//
//  PhotoEditorStandalonePreview.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import SwiftUI

/// Design-preview/manual-QA harness for opening Photo Editor with `.standalone` — the same role
/// `AlbumDraftPlanningPreview` plays for the Album Draft Planner. There is no real single-photo
/// caller anywhere in the app yet (Search/Favorites/Photobook are all future work per
/// PHOTO-EDITOR.md § 4.4), so this is what exercises "mở độc lập với một ảnh" until one exists —
/// entirely synthetic, no Photos Library access, safe to run in Xcode's canvas or the Simulator
/// without granting photo permissions.
struct PhotoEditorStandalonePreview: View {
    @State private var isPresentingEditor = false
    @State private var lastResult: PhotoEditorResult?
    private let repository = InMemoryPhotoEditRepository()

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
                repository: repository,
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
}
