import SwiftUI

@main
struct SafeThinkApp: App {
    @StateObject private var securityService = SecurityService.shared
    @StateObject private var inferenceService = InferenceService.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("theme") private var themeRaw: String = AppTheme.system.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @State private var showInsufficientRAMAlert = false

    private static let minimumRAMGB: Double = 6
    private static let deviceRAMGB: Double = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824

    init() {
        try? DatabaseService.shared.setup()
    }

    private func loadLastActiveModel() async {
        guard !inferenceService.isModelLoaded else { return }

        let downloadService = ModelDownloadService.shared

        // Try last active model first, then fall back to any downloaded model
        let model: ModelInfo? = {
            if let lastModelId = UserDefaults.standard.string(forKey: "lastActiveModelId"),
               let m = ModelInfo.registry.first(where: { $0.id == lastModelId }),
               downloadService.isModelDownloaded(m.id) {
                return m
            }
            return ModelInfo.registry.first { downloadService.isModelDownloaded($0.id) }
        }()

        guard let model else { return }

        let fileURL = downloadService.modelFileURL(for: model)
        try? await inferenceService.loadModel(from: fileURL)
        UserDefaults.standard.set(model.id, forKey: "lastActiveModelId")
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !hasCompletedOnboarding {
                    OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                } else if securityService.isBiometricEnabled && !securityService.isAuthenticated {
                    LockScreenView()
                } else {
                    ContentView()
                }
            }
            .task {
                if Self.deviceRAMGB < Self.minimumRAMGB {
                    showInsufficientRAMAlert = true
                }
                await loadLastActiveModel()
            }
            .preferredColorScheme(AppTheme(rawValue: themeRaw)?.colorScheme)
            .alert("Device Not Supported", isPresented: $showInsufficientRAMAlert) {
                Button("Continue Anyway") {}
            } message: {
                Text("SafeThink requires at least 6 GB of RAM to run the Qwen 3.5 4B model. Your device has \(String(format: "%.0f", Self.deviceRAMGB)) GB. The app may crash or perform poorly.")
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    securityService.checkLockState()
                }
            }
        }
    }
}
