import Foundation

struct SearchResult: Identifiable {
    let id = UUID()
    let title: String
    let snippet: String
    let url: String
}

@MainActor
final class SearchService: ObservableObject {
    static let shared = SearchService()

    @Published var isSearching = false
    @Published var results: [SearchResult] = []

    private let networkLogService = NetworkLogService.shared

    private init() {}

    func search(query: String) async throws -> [SearchResult] {
        isSearching = true
        defer { isSearching = false }

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { throw SearchError.invalidQuery }

        // Use DuckDuckGo HTML search for real web results
        let searchResults = try await htmlSearch(query: normalizedQuery)

        // Fall back to Instant Answer API if HTML search returned nothing
        if searchResults.isEmpty {
            let fallback = try await instantAnswerSearch(query: normalizedQuery)
            results = fallback
            return fallback
        }

        results = searchResults
        return searchResults
    }

    // MARK: - DuckDuckGo HTML Search (actual web results)

    private func htmlSearch(query: String) async throws -> [SearchResult] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)") else {
            throw SearchError.invalidQuery
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) Safari/604.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw SearchError.networkError
        }

        networkLogService.log(
            destination: "html.duckduckgo.com",
            purpose: "Web search: \(query)",
            dataSize: Int64(data.count)
        )

        guard let html = String(data: data, encoding: .utf8) else { return [] }
        return Self.parseHTMLResults(html)
    }

    static func parseHTMLResults(_ html: String) -> [SearchResult] {
        var searchResults: [SearchResult] = []

        // Extract result blocks: <a class="result__a" href="URL">Title</a>
        // and <a class="result__snippet">Snippet</a>
        let titlePattern = #"<a[^>]*class="result__a"[^>]*href="([^"]*)"[^>]*>(.*?)</a>"#
        let snippetPattern = #"<a[^>]*class="result__snippet"[^>]*>(.*?)</a>"#

        guard let titleRegex = try? NSRegularExpression(pattern: titlePattern, options: .dotMatchesLineSeparators),
              let snippetRegex = try? NSRegularExpression(pattern: snippetPattern, options: .dotMatchesLineSeparators) else {
            return []
        }

        let titleMatches = titleRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        let snippetMatches = snippetRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))

        for (i, titleMatch) in titleMatches.prefix(6).enumerated() {
            guard let urlRange = Range(titleMatch.range(at: 1), in: html),
                  let titleRange = Range(titleMatch.range(at: 2), in: html) else { continue }

            let resultURL = String(html[urlRange])
            let rawTitle = String(html[titleRange])
            let title = Self.stripHTML(rawTitle)

            // Skip DuckDuckGo internal links
            if resultURL.contains("duckduckgo.com") { continue }

            var snippet = ""
            if i < snippetMatches.count {
                if let snippetRange = Range(snippetMatches[i].range(at: 1), in: html) {
                    snippet = Self.stripHTML(String(html[snippetRange]))
                }
            }

            guard !title.isEmpty else { continue }
            searchResults.append(SearchResult(title: title, snippet: snippet, url: resultURL))
        }

        return searchResults
    }

    // MARK: - DuckDuckGo Instant Answer API (fallback for fact-based queries)

    private func instantAnswerSearch(query: String) async throws -> [SearchResult] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_html=1&skip_disambig=1") else {
            throw SearchError.invalidQuery
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw SearchError.networkError
        }

        networkLogService.log(
            destination: "api.duckduckgo.com",
            purpose: "Web search (instant): \(query)",
            dataSize: Int64(data.count)
        )

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        var searchResults: [SearchResult] = []

        if let abstract = json["Abstract"] as? String, !abstract.isEmpty {
            searchResults.append(SearchResult(
                title: json["Heading"] as? String ?? "Result",
                snippet: abstract,
                url: json["AbstractURL"] as? String ?? ""
            ))
        }

        if let topics = json["RelatedTopics"] as? [[String: Any]] {
            for topic in topics.prefix(5) {
                if let text = topic["Text"] as? String,
                   let firstURL = topic["FirstURL"] as? String {
                    searchResults.append(SearchResult(
                        title: String(text.prefix(80)),
                        snippet: text,
                        url: firstURL
                    ))
                }
            }
        }

        return searchResults
    }

    // MARK: - Static Helpers (used by tests)

    static func makeSearchURL(query: String) throws -> URL {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { throw SearchError.invalidQuery }
        let encoded = normalizedQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? normalizedQuery
        guard let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)") else {
            throw SearchError.invalidQuery
        }
        return url
    }

    static func parseResults(from data: Data) throws -> [SearchResult] {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        var searchResults: [SearchResult] = []
        if let abstract = json["Abstract"] as? String, !abstract.isEmpty {
            searchResults.append(SearchResult(
                title: json["Heading"] as? String ?? "Result",
                snippet: abstract,
                url: json["AbstractURL"] as? String ?? ""
            ))
        }
        if let topics = json["RelatedTopics"] as? [[String: Any]] {
            searchResults.append(contentsOf: Self.flattenRelatedTopics(topics).prefix(5))
        }
        return searchResults
    }

    private static func flattenRelatedTopics(_ topics: [[String: Any]]) -> [SearchResult] {
        var flattened: [SearchResult] = []
        for topic in topics {
            if let nestedTopics = topic["Topics"] as? [[String: Any]] {
                flattened.append(contentsOf: flattenRelatedTopics(nestedTopics))
                continue
            }
            if let text = topic["Text"] as? String,
               let firstURL = topic["FirstURL"] as? String {
                flattened.append(SearchResult(title: String(text.prefix(80)), snippet: text, url: firstURL))
            }
        }
        return flattened
    }

    // MARK: - HTML Helpers

    private static func stripHTML(_ string: String) -> String {
        string.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SearchError: Error, LocalizedError, Equatable {
    case invalidQuery
    case networkError

    var errorDescription: String? {
        switch self {
        case .invalidQuery: return "Invalid search query"
        case .networkError: return "Network error during search"
        }
    }
}
