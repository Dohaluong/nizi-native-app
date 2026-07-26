//
//  PhotoPickerView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import PhotosUI
import SwiftUI

/// A single-image `PHPickerViewController` wrapper — used by the DEBUG-only Preset Tuning Panel's
/// "Choose Photo" so a developer can tune against a specific photo instead of only the "Next
/// Sample" random cycling. `PHPickerConfiguration(photoLibrary: .shared())` is required for
/// `PHPickerResult.assetIdentifier` to come back non-nil (the default, library-less configuration
/// never returns one) — this app already has Photos access elsewhere, so no extra permission
/// prompt beyond what the picker itself triggers.
struct PhotoPickerView: UIViewControllerRepresentable {
    var onPick: (String) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPickerView
        init(_ parent: PhotoPickerView) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let identifier = results.first?.assetIdentifier else {
                parent.onCancel()
                return
            }
            parent.onPick(identifier)
        }
    }
}
