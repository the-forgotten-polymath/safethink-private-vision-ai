import SwiftUI
import PhotosUI

struct AttachmentMenuView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var showDocumentPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Camera", systemImage: "camera")
                    }

                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("Photo Library", systemImage: "photo.on.rectangle")
                    }

                    Button {
                        showDocumentPicker = true
                    } label: {
                        Label("Document", systemImage: "doc")
                    }
                } header: {
                    Text("Attach")
                }

                Section {
                    Button {
                        viewModel.isWebSearchEnabled = true
                        dismiss()
                    } label: {
                        Label("Search Web", systemImage: "globe")
                    }
                } header: {
                    Text("Web")
                } footer: {
                    Text("Search results will be processed locally by your on-device model.")
                }
            }
            .navigationTitle("Attach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    viewModel.selectedImages.append(image)
                    dismiss()
                }
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
            .onChange(of: selectedPhotoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        viewModel.selectedImages.append(image)
                        dismiss()
                    }
                }
            }
            .fileImporter(isPresented: $showDocumentPicker, allowedContentTypes: [.pdf, .plainText, .commaSeparatedText]) { result in
                if case .success(let url) = result {
                    // Copy file to app sandbox immediately while security-scoped access is valid
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(url.lastPathComponent)
                    try? FileManager.default.removeItem(at: tempURL)
                    if (try? FileManager.default.copyItem(at: url, to: tempURL)) != nil {
                        viewModel.attachedDocumentURL = tempURL
                    } else {
                        viewModel.attachedDocumentURL = url
                    }
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Camera Picker

struct CameraPicker: UIViewControllerRepresentable {
    let onImageCaptured: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImageCaptured: onImageCaptured) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImageCaptured: (UIImage) -> Void

        init(onImageCaptured: @escaping (UIImage) -> Void) {
            self.onImageCaptured = onImageCaptured
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImageCaptured(image)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
