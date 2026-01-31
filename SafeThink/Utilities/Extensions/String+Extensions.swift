import Foundation

extension String {
    var estimatedTokenCount: Int {
        // Rough estimate: 1 token per 4 characters for English
        max(1, count / 4)
    }

    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func truncated(to maxLength: Int, trailing: String = "...") -> String {
        if count <= maxLength { return self }
        return String(prefix(maxLength - trailing.count)) + trailing
    }
}
