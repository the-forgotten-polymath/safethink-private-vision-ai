import SwiftUI

struct PrivacyDashboardView: View {
    @StateObject private var viewModel = PrivacyDashboardViewModel()

    var body: some View {
        List {
            // MARK: - Privacy Shield
            Section {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)

                    Text("Your data stays on this device")
                        .font(.headline)

                    Text("No analytics, no tracking, no cloud sync")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }

            // MARK: - On-Device Storage
            Section("On-Device Storage") {
                storageRow(icon: "bubble.left.and.text.bubble",
                           label: "\(viewModel.conversationCount) conversations",
                           detail: "\(viewModel.messageCount) messages")

                storageRow(icon: "cpu",
                           label: "\(viewModel.modelCount) model\(viewModel.modelCount == 1 ? "" : "s") downloaded",
                           detail: viewModel.modelStorageSize)
            }

            // MARK: - Network Activity
            Section {
                if viewModel.hasNoNetworkActivity {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No network activity")
                                .font(.subheadline.weight(.medium))
                            Text("Nothing has been sent or received")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    // Summary row
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(viewModel.totalRequests) request\(viewModel.totalRequests == 1 ? "" : "s")")
                                .font(.subheadline.weight(.medium))
                            Text("\(viewModel.totalDataTransferred) transferred")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Clear Log") {
                            viewModel.showClearLogsConfirmation = true
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    // Individual log entries
                    ForEach(viewModel.networkLogs.prefix(50)) { log in
                        networkLogRow(log)
                    }
                }
            } header: {
                Text("Network Activity")
            } footer: {
                if !viewModel.hasNoNetworkActivity {
                    Text("All network requests are user-initiated. SafeThink never contacts any server in the background.")
                }
            }

            // MARK: - Permissions
            Section {
                ForEach(viewModel.permissions) { perm in
                    HStack(spacing: 12) {
                        Image(systemName: perm.icon)
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        Text(perm.name)
                        Spacer()
                        if perm.isGranted {
                            Text("Granted")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else {
                            Text("Not Granted")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Permissions are only used for on-device features. No data is sent externally.")
            }

            // MARK: - Data Controls
            Section("Data Controls") {
                Button(role: .destructive) {
                    viewModel.deleteMode = .data
                    viewModel.showDeleteConfirmation = true
                } label: {
                    Label("Delete All My Data", systemImage: "trash")
                }

                Button(role: .destructive) {
                    viewModel.deleteMode = .everything
                    viewModel.showDeleteConfirmation = true
                } label: {
                    Label("Delete Everything Including Models", systemImage: "trash.fill")
                }
            }
        }
        .navigationTitle("Privacy")
        .onAppear { viewModel.refresh() }
        .alert("Confirm Deletion", isPresented: $viewModel.showDeleteConfirmation) {
            TextField("Type DELETE to confirm", text: $viewModel.deleteConfirmationText)
            Button("Cancel", role: .cancel) {
                viewModel.deleteConfirmationText = ""
            }
            Button("Delete", role: .destructive) {
                switch viewModel.deleteMode {
                case .data:
                    viewModel.deleteAllData()
                case .everything:
                    viewModel.deleteEverything()
                }
            }
            .disabled(viewModel.deleteConfirmationText != "DELETE")
        } message: {
            Text("This action cannot be undone. Type DELETE to confirm.")
        }
        .alert("Clear Network Log?", isPresented: $viewModel.showClearLogsConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                viewModel.clearNetworkLogs()
            }
        } message: {
            Text("This will remove all recorded network activity. This cannot be undone.")
        }
    }

    // MARK: - Components

    private func storageRow(icon: String, label: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            Text(label)
            Spacer()
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func networkLogRow(_ log: NetworkLog) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: logIcon(for: log.purpose))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(log.purpose)
                    .font(.subheadline)
                HStack(spacing: 8) {
                    Text(log.destination)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                    Text(viewModel.formattedSize(for: log))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(viewModel.formattedDate(for: log))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 2)
    }

    private func logIcon(for purpose: String) -> String {
        if purpose.localizedCaseInsensitiveContains("download") {
            return "arrow.down.circle"
        } else if purpose.localizedCaseInsensitiveContains("search") {
            return "magnifyingglass"
        } else if purpose.localizedCaseInsensitiveContains("embed") {
            return "cpu"
        } else {
            return "network"
        }
    }
}

#Preview {
    NavigationStack {
        PrivacyDashboardView()
    }
}
