import SwiftUI

struct InputBarView: View {
    @Binding var text: String
    let isGenerating: Bool
    var hasAttachment: Bool = false
    let onSend: () -> Void
    let onStop: () -> Void
    let onAttachment: () -> Void
    let onMic: () -> Void

    @FocusState private var isFocused: Bool

    private var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasAttachment
    }

    var body: some View {
        HStack(spacing: 10) {
            // Plus button
            Button(action: onAttachment) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color(.systemGray2))
                    .clipShape(Circle())
            }

            // Text field pill
            TextField("Ask anything", text: $text, axis: .vertical)
                .font(.system(size: 14))
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color(.systemGray5))
                .clipShape(Capsule())

            // Right action button
            if isGenerating {
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color(.systemGray2))
                        .clipShape(Circle())
                }
            } else if hasContent {
                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                }
            } else {
                Button(action: onMic) {
                    Image(systemName: "waveform")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color(.systemGray2))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.bar)
    }
}

#Preview {
    VStack {
        InputBarView(
            text: .constant(""),
            isGenerating: false,
            onSend: {},
            onStop: {},
            onAttachment: {},
            onMic: {}
        )
        InputBarView(
            text: .constant("Hello"),
            isGenerating: false,
            onSend: {},
            onStop: {},
            onAttachment: {},
            onMic: {}
        )
    }
}
