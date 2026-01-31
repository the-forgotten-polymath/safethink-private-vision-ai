import SwiftUI

struct LockScreenView: View {
    @StateObject private var security = SecurityService.shared
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            Text("SafeThink is Locked")
                .font(.title2)
                .bold()

            if security.isBiometricEnabled {
                Button {
                    Task {
                        let success = await security.authenticateWithBiometrics()
                        if !success {
                            showError = true
                            errorMessage = "Authentication failed"
                        }
                    }
                } label: {
                    Label("Unlock with \(security.biometricType)", systemImage: "faceid")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: 280)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }

            if showError {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }

            Spacer()
        }
        .padding()
        .onAppear {
            if security.isBiometricEnabled && !security.isAuthenticating {
                Task {
                    _ = await security.authenticateWithBiometrics()
                }
            }
        }
    }
}

#Preview {
    LockScreenView()
}
