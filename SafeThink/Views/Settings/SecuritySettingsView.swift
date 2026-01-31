import SwiftUI

struct SecuritySettingsView: View {
    @StateObject private var security = SecurityService.shared

    var body: some View {
        Form {
            Section("Biometrics") {
                Toggle(security.biometricType, isOn: $security.isBiometricEnabled)
            }

            Section("Lock Timeout") {
                Picker("Lock After", selection: $security.lockTimeout) {
                    ForEach(SecurityService.LockTimeout.allCases, id: \.self) { timeout in
                        Text(timeout.displayName).tag(timeout)
                    }
                }
            }
        }
        .navigationTitle("Security")
    }
}

#Preview {
    NavigationStack {
        SecuritySettingsView()
    }
}
