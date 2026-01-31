import Foundation
import LocalAuthentication

@MainActor
final class SecurityService: ObservableObject {
    static let shared = SecurityService()

    @Published var isAuthenticated = false
    @Published private(set) var isAuthenticating = false
    @Published var isBiometricEnabled = false {
        didSet { persistSettingsIfNeeded() }
    }
    @Published var lockTimeout: LockTimeout = .immediate {
        didSet { persistSettingsIfNeeded() }
    }
    private var lastAuthTime: Date?
    private var isLoadingSettings = false

    enum LockTimeout: Int, CaseIterable {
        case immediate = 0
        case thirtySeconds = 30
        case oneMinute = 60
        case fiveMinutes = 300
        case never = -1

        var displayName: String {
            switch self {
            case .immediate: return "Immediately"
            case .thirtySeconds: return "30 seconds"
            case .oneMinute: return "1 minute"
            case .fiveMinutes: return "5 minutes"
            case .never: return "Never"
            }
        }
    }

    private init() {
        loadSettings()
    }

    // MARK: - Biometric Auth

    func authenticateWithBiometrics() async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Unlock SafeThink"
            )
            if success {
                isAuthenticated = true
                lastAuthTime = Date()
            }
            return success
        } catch {
            return false
        }
    }

    var biometricType: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        @unknown default: return "Biometrics"
        }
    }

    // MARK: - Lock State

    func checkLockState() {
        guard lockTimeout != .never else {
            isAuthenticated = true
            return
        }

        guard isBiometricEnabled else {
            isAuthenticated = true
            return
        }

        if lockTimeout == .immediate {
            isAuthenticated = false
            return
        }

        if let lastAuth = lastAuthTime {
            let elapsed = Date().timeIntervalSince(lastAuth)
            if elapsed > TimeInterval(lockTimeout.rawValue) {
                isAuthenticated = false
            }
        } else {
            isAuthenticated = false
        }
    }

    func lock() {
        isAuthenticated = false
    }

    // MARK: - Settings Persistence

    private func saveSettings() {
        UserDefaults.standard.set(isBiometricEnabled, forKey: "security_biometric")
        UserDefaults.standard.set(lockTimeout.rawValue, forKey: "security_timeout")
    }

    private func persistSettingsIfNeeded() {
        guard !isLoadingSettings else { return }
        saveSettings()
    }

    private func loadSettings() {
        isLoadingSettings = true
        defer { isLoadingSettings = false }

        isBiometricEnabled = UserDefaults.standard.bool(forKey: "security_biometric")
        let timeoutRaw = UserDefaults.standard.integer(forKey: "security_timeout")
        lockTimeout = LockTimeout(rawValue: timeoutRaw) ?? .immediate
    }
}
