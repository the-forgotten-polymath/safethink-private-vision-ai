import SwiftUI

struct LoadingIndicator: View {
    let message: String
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
                    .scaleEffect(isAnimating ? 1.0 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: isAnimating
                    )
            }
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { isAnimating = true }
    }
}

struct ThinkingIndicator: View {
    var body: some View {
        LoadingIndicator(message: "Thinking...")
    }
}

struct AnalyzingImageIndicator: View {
    var body: some View {
        LoadingIndicator(message: "Analyzing image...")
    }
}

#Preview {
    VStack(spacing: 20) {
        ThinkingIndicator()
        AnalyzingImageIndicator()
    }
}
