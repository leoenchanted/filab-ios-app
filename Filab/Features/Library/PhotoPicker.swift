import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Photo Picker

struct PhotoPicker: UIViewControllerRepresentable {
    @ObservedObject var viewModel: FilmEditorViewModel
    var onImageSelected: () -> Void
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 1
        config.filter = .images
        config.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        private var selectionToken = UUID()

        init(_ parent: PhotoPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // Dismiss the picker first
            picker.dismiss(animated: true)

            guard let result = results.first else { return }
            let token = UUID()
            selectionToken = token

            loadSelectedImage(from: result.itemProvider, token: token)
        }

        func pickerDidCancel(_ picker: PHPickerViewController) {
            picker.dismiss(animated: true)
        }

        private func loadSelectedImage(from provider: NSItemProvider, token: UUID) {
            guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
                loadUIImageFallback(from: provider, token: token)
                return
            }

            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, error in
                if let error = error {
                    print("Error loading image data: \(error)")
                }

                DispatchQueue.main.async {
                    guard let self, self.selectionToken == token else { return }

                    if let data, let image = UIImage(data: data) {
                        self.deliver(image, token: token)
                    } else {
                        self.loadUIImageFallback(from: provider, token: token)
                    }
                }
            }
        }

        private func loadUIImageFallback(from provider: NSItemProvider, token: UUID) {
            guard provider.canLoadObject(ofClass: UIImage.self) else { return }

            provider.loadObject(ofClass: UIImage.self) { [weak self] image, error in
                if let error = error {
                    print("Error loading image: \(error)")
                    return
                }

                DispatchQueue.main.async {
                    guard let self,
                          self.selectionToken == token,
                          let image = image as? UIImage else {
                        return
                    }

                    self.deliver(image, token: token)
                }
            }
        }

        private func deliver(_ image: UIImage, token: UUID) {
            guard selectionToken == token else { return }
            parent.viewModel.loadImage(image)
            parent.onImageSelected()
        }
    }
}
