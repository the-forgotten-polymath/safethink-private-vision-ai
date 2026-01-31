import Foundation
import UIKit

enum ExportFormat: String, CaseIterable {
    case json = "JSON"
    case markdown = "Markdown"
    case text = "Plain Text"
    case pdf = "PDF"

    var fileExtension: String {
        switch self {
        case .json: return "json"
        case .markdown: return "md"
        case .text: return "txt"
        case .pdf: return "pdf"
        }
    }
}

final class ExportService {
    static let shared = ExportService()

    private let databaseService = DatabaseService.shared

    private var exportsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("exports", isDirectory: true)
    }

    private init() {
        try? FileManager.default.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)
    }

    func exportConversation(_ conversation: Conversation, format: ExportFormat) throws -> URL {
        let messages = try databaseService.fetchMessages(conversationId: conversation.id)
        let fileName = sanitizeFileName(conversation.title) + ".\(format.fileExtension)"
        let fileURL = exportsDirectory.appendingPathComponent(fileName)

        switch format {
        case .json:
            let data = try exportAsJSON(conversation: conversation, messages: messages)
            try data.write(to: fileURL)
        case .markdown:
            let text = exportAsMarkdown(conversation: conversation, messages: messages)
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
        case .text:
            let text = exportAsText(conversation: conversation, messages: messages)
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
        case .pdf:
            let data = exportAsPDF(conversation: conversation, messages: messages)
            try data.write(to: fileURL)
        }

        return fileURL
    }

    func exportAllConversations(format: ExportFormat) throws -> URL {
        let conversations = try databaseService.fetchConversations(includeArchived: true)
        let dirName = "SafeThink_Export_\(formattedDate())"
        let exportDir = exportsDirectory.appendingPathComponent(dirName, isDirectory: true)
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)

        for conversation in conversations {
            let messages = try databaseService.fetchMessages(conversationId: conversation.id)
            let fileName = sanitizeFileName(conversation.title) + ".\(format.fileExtension)"
            let fileURL = exportDir.appendingPathComponent(fileName)

            switch format {
            case .json:
                let data = try exportAsJSON(conversation: conversation, messages: messages)
                try data.write(to: fileURL)
            case .markdown:
                let text = exportAsMarkdown(conversation: conversation, messages: messages)
                try text.write(to: fileURL, atomically: true, encoding: .utf8)
            case .text:
                let text = exportAsText(conversation: conversation, messages: messages)
                try text.write(to: fileURL, atomically: true, encoding: .utf8)
            case .pdf:
                let data = exportAsPDF(conversation: conversation, messages: messages)
                try data.write(to: fileURL)
            }
        }

        return exportDir
    }

    // MARK: - Format Implementations

    private func exportAsJSON(conversation: Conversation, messages: [Message]) throws -> Data {
        let export: [String: Any] = [
            "conversation": [
                "id": conversation.id,
                "title": conversation.title,
                "created_at": ISO8601DateFormatter().string(from: conversation.createdAt),
                "model_id": conversation.modelId,
                "message_count": conversation.messageCount
            ],
            "messages": messages.map { msg in
                [
                    "role": msg.role.rawValue,
                    "content": msg.content,
                    "created_at": ISO8601DateFormatter().string(from: msg.createdAt),
                    "token_count": msg.tokenCount as Any,
                    "tokens_per_sec": msg.tokensPerSec as Any
                ] as [String: Any]
            }
        ]
        return try JSONSerialization.data(withJSONObject: export, options: [.prettyPrinted, .sortedKeys])
    }

    private func exportAsMarkdown(conversation: Conversation, messages: [Message]) -> String {
        var md = "# \(conversation.title)\n\n"
        md += "*Exported from SafeThink on \(formattedDate())*\n\n---\n\n"
        for message in messages {
            let role = message.role == .user ? "**You**" : "**SafeThink**"
            md += "\(role):\n\n\(message.content)\n\n---\n\n"
        }
        return md
    }

    private func exportAsText(conversation: Conversation, messages: [Message]) -> String {
        var text = "\(conversation.title)\n"
        text += String(repeating: "=", count: conversation.title.count) + "\n\n"
        for message in messages {
            let role = message.role == .user ? "You" : "SafeThink"
            text += "[\(role)]:\n\(message.content)\n\n"
        }
        return text
    }

    private func exportAsPDF(conversation: Conversation, messages: [Message]) -> Data {
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 50
        let contentWidth = pageWidth - margin * 2

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        return renderer.pdfData { ctx in
            ctx.beginPage()
            var yPos: CGFloat = margin

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 18)
            ]
            let titleRect = CGRect(x: margin, y: yPos, width: contentWidth, height: 30)
            conversation.title.draw(in: titleRect, withAttributes: titleAttrs)
            yPos += 40

            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12)
            ]
            let roleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 12)
            ]

            for message in messages {
                let role = message.role == .user ? "You:" : "SafeThink:"

                if yPos > pageHeight - margin - 50 {
                    ctx.beginPage()
                    yPos = margin
                }

                role.draw(at: CGPoint(x: margin, y: yPos), withAttributes: roleAttrs)
                yPos += 18

                let textRect = CGRect(x: margin, y: yPos, width: contentWidth, height: pageHeight - yPos - margin)
                message.content.draw(in: textRect, withAttributes: bodyAttrs)
                yPos += 30 + CGFloat(message.content.count / 80) * 15
            }
        }
    }

    // MARK: - Helpers

    private func sanitizeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return String(name.components(separatedBy: invalid).joined(separator: "_").prefix(50))
            .trimmingCharacters(in: .whitespaces)
    }

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
