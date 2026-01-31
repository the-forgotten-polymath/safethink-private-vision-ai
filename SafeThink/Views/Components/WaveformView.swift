import SwiftUI

struct WaveformView: View {
    let audioLevel: Float
    let isRecording: Bool

    @State private var animationPhase: CGFloat = 0

    private let barCount = 20

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 3, height: barHeight(for: index))
                    .animation(.easeInOut(duration: 0.15), value: audioLevel)
            }
        }
        .frame(height: 32)
        .onChange(of: isRecording) { _, recording in
            if recording {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    animationPhase = .pi * 2
                }
            } else {
                animationPhase = 0
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let base: CGFloat = 4
        let maxHeight: CGFloat = 28
        let normalizedLevel = CGFloat(min(audioLevel * 10, 1.0))
        let wave = sin(CGFloat(index) * 0.5 + animationPhase)
        let height = base + (maxHeight - base) * normalizedLevel * abs(wave)
        return max(base, height)
    }
}

#Preview {
    WaveformView(audioLevel: 0.3, isRecording: true)
        .padding()
}
