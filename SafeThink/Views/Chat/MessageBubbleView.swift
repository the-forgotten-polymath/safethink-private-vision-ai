import SwiftUI
import MarkdownUI

struct MessageBubbleView: View {
    let message: Message
    var isStreaming: Bool = false
    var onRegenerate: (() -> Void)?
    var onEdit: (() -> Void)?

    @State private var showActions = false
    @State private var isThoughtsExpanded = false

    private var imagePaths: [String] {
        let pattern = #"\[IMAGE:([^\]]+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsContent = message.content as NSString
        let matches = regex.matches(in: message.content, range: NSRange(location: 0, length: nsContent.length))
        return matches.compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            return nsContent.substring(with: match.range(at: 1))
        }
    }

    private var displayContent: String {
        message.content.replacingOccurrences(of: #"\[IMAGE:[^\]]+\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsed: ParsedContent {
        Self.parseThinkTags(displayContent)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .assistant {
                Image(systemName: "brain.head.profile")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                if message.role == .assistant {
                    assistantContent
                } else {
                    ForEach(imagePaths, id: \.self) { path in
                        if let img = ChatViewModel.loadChatImage(relativePath: path) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    if !displayContent.isEmpty {
                        Text(displayContent)
                            .textSelection(.enabled)
                    }
                }

                // Streaming cursor
                if isStreaming {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                            .opacity(isStreaming ? 1 : 0)
                            .animation(.easeInOut(duration: 0.5).repeatForever(), value: isStreaming)
                    }
                }

                // Web-enhanced badge
                if parsed.response.hasPrefix("[Web-enhanced]") {
                    Label("Web-enhanced", systemImage: "globe")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }

                // Token stats
                if let tokSec = message.tokensPerSec, tokSec > 0 {
                    Text("\(tokSec, specifier: "%.1f") tok/s")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(12)
            .background(message.role == .user ? Color.accentColor.opacity(0.1) : Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contextMenu {
                Button {
                    UIPasteboard.general.string = parsed.response.isEmpty ? message.content : parsed.response
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }

                if parsed.thoughts != nil {
                    Button {
                        UIPasteboard.general.string = parsed.thoughts
                    } label: {
                        Label("Copy Thoughts", systemImage: "doc.on.doc")
                    }
                }

                if message.role == .assistant, let onRegenerate {
                    Button {
                        onRegenerate()
                    } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                    }
                }

                if message.role == .user, let onEdit {
                    Button {
                        onEdit()
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                }
            }

            if message.role == .user {
                Image(systemName: "person.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    // MARK: - Assistant Content

    @ViewBuilder
    private var assistantContent: some View {
        // Inline images (e.g. edited image results)
        ForEach(imagePaths, id: \.self) { path in
            if let img = ChatViewModel.loadChatImage(relativePath: path) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }

        if let thoughts = parsed.thoughts {
            thoughtsSection(thoughts)
        } else if isStreaming && parsed.isThinking {
            thinkingIndicator
        }

        if !parsed.response.isEmpty {
            Markdown(parsed.response)
                .markdownTheme(.gitHub)
                .textSelection(.enabled)
        }
    }

    // MARK: - Thinking Indicator

    private var thinkingIndicator: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text("Thinking...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }

    // MARK: - Thoughts Section

    @ViewBuilder
    private func thoughtsSection(_ thoughts: String) -> some View {
        let expanded = (isStreaming && parsed.isThinking) || isThoughtsExpanded

        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isThoughtsExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("Thoughts")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 0 : -90))
                }
            }
            .buttonStyle(.plain)

            if expanded {
                Text(thoughts)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }

    // MARK: - Think Tag Parsing

    private struct ParsedContent {
        let thoughts: String?
        let response: String
        let isThinking: Bool
    }

    private static func parseThinkTags(_ content: String) -> ParsedContent {
        guard let startRange = content.range(of: "<think>") else {
            return ParsedContent(thoughts: nil, response: content, isThinking: false)
        }

        let beforeThink = String(content[..<startRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let afterOpen = content[startRange.upperBound...]

        if let endRange = afterOpen.range(of: "</think>") {
            let thoughts = String(afterOpen[..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let afterClose = String(afterOpen[endRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let response = [beforeThink, afterClose]
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            return ParsedContent(
                thoughts: thoughts.isEmpty ? nil : thoughts,
                response: response,
                isThinking: false
            )
        } else {
            let thoughts = String(afterOpen)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return ParsedContent(
                thoughts: thoughts.isEmpty ? nil : thoughts,
                response: beforeThink,
                isThinking: true
            )
        }
    }
}

#Preview {
    VStack {
        MessageBubbleView(message: Message(conversationId: "1", role: .user, content: "Hello!"))
        MessageBubbleView(message: Message(conversationId: "1", role: .assistant, content: "Hi! How can I help you?"))
    }
    .padding()
}
