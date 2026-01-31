import SwiftUI

struct ModelCardView: View {
    let model: ModelInfo
    let status: ModelDownloadStatus
    let progress: Double
    let isActive: Bool
    let compatibility: ModelCompatibility
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onActivate: () -> Void
    let onCancel: () -> Void

    @State private var isDownloadInitiating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .font(.headline)
                        if isActive {
                            Text("Active")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        }
                    }
                    Text("\(model.parameterCount) · \(model.quantization) · \(model.sizeFormatted)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                compatibilityBadge
            }

            // Incompatible warning
            if compatibility == .incompatible {
                Label("Requires \(model.minRAMGB) GB RAM — not supported on this device", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                // Action area
                statusView
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .notDownloaded:
            Button {
                isDownloadInitiating = true
                onDownload()
            } label: {
                HStack(spacing: 8) {
                    if isDownloadInitiating {
                        ProgressView()
                            .controlSize(.small)
                        Text("Starting...")
                    } else {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isDownloadInitiating)
            .onChange(of: status) { _, _ in
                isDownloadInitiating = false
            }

        case .downloading(let downloadProgress):
            VStack(spacing: 4) {
                ProgressView(value: downloadProgress)
                HStack {
                    Text("\(Int(downloadProgress * 100))%")
                        .font(.caption)
                        .monospacedDigit()
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

        case .verifying:
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Verifying...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .ready:
            HStack(spacing: 12) {
                if !isActive {
                    Button(action: onActivate) {
                        Label("Load", systemImage: "play.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
            }

        case .error(let message):
            VStack(alignment: .leading, spacing: 4) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                Button("Retry", action: onDownload)
                    .font(.caption)
                    .buttonStyle(.bordered)
            }

        case .updateAvailable:
            Button(action: onDownload) {
                Label("Update Available", systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
        }
    }

    @ViewBuilder
    private var compatibilityBadge: some View {
        switch compatibility {
        case .compatible:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .limited:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.yellow)
                .font(.caption)
        case .incompatible:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        }
    }
}
