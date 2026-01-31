import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @StateObject private var downloadService = ModelDownloadService.shared
    @State private var currentPage = 0
    @State private var selectedModelId: String?
    @State private var isDownloading = false

    var body: some View {
        TabView(selection: $currentPage) {
            // Page 1: Welcome
            welcomePage.tag(0)

            // Page 2: Model Selection
            modelSelectionPage.tag(1)

            // Page 3: Security (optional)
            securityPage.tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }

    // MARK: - Welcome

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "brain.head.profile")
                .font(.system(size: 80))
                .foregroundStyle(Color.accentColor)

            Text("SafeThink")
                .font(.largeTitle)
                .bold()

            Text("The AI assistant that never\nsends your data anywhere")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "lock.shield.fill", color: .green,
                           text: "100% local AI - nothing leaves your device")
                FeatureRow(icon: "bolt.fill", color: .orange,
                           text: "Fast on-device inference with Apple Silicon")
                FeatureRow(icon: "doc.text.fill", color: .blue,
                           text: "Chat, documents, images, voice - all offline")
                FeatureRow(icon: "brain", color: .purple,
                           text: "Persistent memory that learns about you")
            }
            .padding(.horizontal, 32)

            Spacer()

            Button {
                withAnimation { currentPage = 1 }
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 60)
        }
    }

    // MARK: - Model Selection

    private var modelSelectionPage: some View {
        VStack(spacing: 16) {
            Text("Choose a Model")
                .font(.title2)
                .bold()
                .padding(.top, 32)

            Text("Select a model to download. You can add more later.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(ModelInfo.registry) { model in
                        ModelSelectionCard(
                            model: model,
                            isSelected: selectedModelId == model.id,
                            onSelect: { selectedModelId = model.id }
                        )
                    }
                }
                .padding(.horizontal)
            }

            Spacer()

            VStack(spacing: 12) {
                if isDownloading {
                    ProgressView("Downloading model...")
                        .padding()
                } else {
                    Button {
                        if let modelId = selectedModelId,
                           let model = ModelInfo.registry.first(where: { $0.id == modelId }) {
                            isDownloading = true
                            Task {
                                try? await downloadService.downloadModel(model)
                                isDownloading = false
                                withAnimation { currentPage = 2 }
                            }
                        }
                    } label: {
                        Text("Download & Continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(selectedModelId != nil ? Color.accentColor : Color.gray)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(selectedModelId == nil)

                    Button("Skip for Now") {
                        withAnimation { currentPage = 2 }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 60)
        }
    }

    // MARK: - Security Setup

    private var securityPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("Protect Your Data")
                .font(.title2)
                .bold()

            Text("Optionally enable biometric lock to protect your conversations.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(spacing: 12) {
                Button {
                    Task {
                        let success = await SecurityService.shared.authenticateWithBiometrics()
                        if success {
                            SecurityService.shared.isBiometricEnabled = true
                        }
                    }
                } label: {
                    Label("Enable \(SecurityService.shared.biometricType)", systemImage: "faceid")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    hasCompletedOnboarding = true
                } label: {
                    Text("Skip & Start Using SafeThink")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            Button {
                hasCompletedOnboarding = true
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 60)
        }
    }
}

// MARK: - Supporting Views

struct FeatureRow: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
            Text(text)
                .font(.subheadline)
        }
    }
}

struct ModelSelectionCard: View {
    let model: ModelInfo
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(model.parameterCount) | \(model.sizeFormatted)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .padding()
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
    }
}
