//
//  PhotoPicker.swift
//  RemoteDev
//
//  写真ライブラリから画像を選択して Data で返す (PHPicker、権限不要)。
//

import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct PhotoPicker: UIViewControllerRepresentable {
    var limit = 4
    let onPick: ([Data]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = limit
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker

        init(_ parent: PhotoPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else { return }
            Task {
                var images: [Data] = []
                for result in results {
                    guard let provider = result.itemProvider,
                          provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else { continue }
                    let data = await withCheckedContinuation { continuation in
                        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                            continuation.resume(returning: data)
                        }
                    }
                    if let data {
                        images.append(data)
                    }
                }
                await MainActor.run {
                    parent.onPick(images)
                }
            }
        }
    }
}
