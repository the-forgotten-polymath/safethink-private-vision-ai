import SwiftUI

struct ModelManagerView: View {
    @StateObject private var viewModel = ModelManagerViewModel()

    var body: some View {
        List {
            // Storage header
            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Models: \(viewModel.totalModelsSize)")
                            .font(.subheadline)
                        Text("Free: \(viewModel.deviceFreeSpace)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            // Model cards
            Section("Available Models") {
                ForEach(viewModel.models) { model in
                    ModelCardView(
                        model: model,
                        status: viewModel.downloadStatus[model.id] ?? .notDownloaded,
                        progress: viewModel.downloadProgress[model.id] ?? 0,
                        isActive: viewModel.activeModelId == model.id,
                        compatibility: viewModel.compatibility(for: model),
                        onDownload: { Task { await viewModel.downloadModel(model) } },
                        onDelete: {
                            viewModel.modelToDelete = model
                            viewModel.showDeleteConfirmation = true
                        },
                        onActivate: { Task { await viewModel.activateModel(model) } },
                        onCancel: { viewModel.cancelDownload(model.id) }
                    )
                }
            }
        }
        .navigationTitle("Models")
        .onAppear { viewModel.refresh() }
        .alert("Delete Model?", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let model = viewModel.modelToDelete {
                    viewModel.deleteModel(model)
                }
            }
        } message: {
            if let model = viewModel.modelToDelete {
                Text("Delete \(model.displayName)? This will free \(model.sizeFormatted) of storage.")
            }
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

#Preview {
    NavigationStack {
        ModelManagerView()
    }
}
