import Foundation
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var currentConversation: Conversation?
    @Published var messages: [Message] = []
    @Published var inputText = ""
    @Published var isGenerating = false
    @Published var streamingText = ""
    @Published var tokensPerSecond: Double = 0
    private static let charsPerToken = 4
    private static let maxGenerationTokens = 2048
    @Published var searchQuery = ""
    @Published var searchResults: [Message] = []
    @Published var selectedImages: [UIImage] = []
    @Published var attachedDocumentURL: URL?
    @Published var isWebSearchEnabled = false
    @Published var errorMessage: String?
    @Published var showNoModelAlert = false

    private let inferenceService = InferenceService.shared
    private let databaseService = DatabaseService.shared
    private let memoryService = MemoryService.shared
    private let searchService = SearchService.shared
    private let documentService = DocumentService.shared
    private let imageService = ImageService.shared

    static let aiDisclaimer = "AI-generated responses may be inaccurate. Verify important information independently."

    private var promptBudgetChars: Int {
        (inferenceService.contextSize - Self.maxGenerationTokens) * Self.charsPerToken
    }

    var contextUsage: String {
        let used = messages.reduce(0) { $0 + $1.content.count } / Self.charsPerToken
        return "\(used) / \(inferenceService.contextSize) tokens"
    }

    // MARK: - Conversation Management

    func loadConversations() {
        conversations = (try? databaseService.fetchConversations(includeArchived: true)) ?? []
    }

    func createNewConversation() {
        let modelId = inferenceService.loadedModelId ?? "unknown"
        let conversation = Conversation(modelId: modelId)
        // Don't persist to DB yet — wait until the first message is sent
        currentConversation = conversation
        messages = []
        streamingText = ""
    }

    func selectConversation(_ conversation: Conversation) {
        currentConversation = conversation
        messages = (try? databaseService.fetchMessages(conversationId: conversation.id)) ?? []
        streamingText = ""
    }

    func deleteConversation(_ conversation: Conversation) {
        try? databaseService.deleteConversation(id: conversation.id)
        if currentConversation?.id == conversation.id {
            currentConversation = nil
            messages = []
        }
        loadConversations()
    }

    func togglePin(_ conversation: Conversation) {
        var updated = conversation
        updated.isPinned.toggle()
        updated.updatedAt = Date()
        try? databaseService.updateConversation(updated)
        syncCurrentConversation(with: updated)
        loadConversations()
    }

    func toggleArchive(_ conversation: Conversation) {
        var updated = conversation
        updated.isArchived.toggle()
        updated.updatedAt = Date()
        try? databaseService.updateConversation(updated)
        syncCurrentConversation(with: updated)
        loadConversations()
    }

    func renameConversation(_ conversation: Conversation, to title: String) {
        var updated = conversation
        updated.title = title
        updated.updatedAt = Date()
        try? databaseService.updateConversation(updated)
        syncCurrentConversation(with: updated)
        loadConversations()
    }

    // MARK: - Message Sending

    func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !selectedImages.isEmpty || attachedDocumentURL != nil else { return }

        guard inferenceService.isModelLoaded else {
            showNoModelAlert = true
            return
        }

        // Create conversation if needed
        if currentConversation == nil {
            createNewConversation()
        }

        guard let conversation = currentConversation else { return }

        // Auto-title from first message
        if messages.isEmpty && !text.isEmpty {
            let title = String(text.prefix(50))
            renameConversation(conversation, to: title)
        }

        // Check for web search command
        if text.hasPrefix("/search ") {
            let query = String(text.dropFirst(8))
            inputText = ""
            await performWebSearch(query: query, in: conversation)
            return
        }

        // Handle image attachment
        let attachedImage = selectedImages.first
        var userContent = text
        var editedImagePath: String?
        var imageAnalysis: String?

        if let image = attachedImage {
            let uuid = UUID().uuidString
            let preprocessed = imageService.preprocessForLLM(image)
            if let path = saveImage(preprocessed, name: "original_\(uuid)") {
                userContent = text.isEmpty ? "[IMAGE:\(path)]" : "\(text)\n[IMAGE:\(path)]"
            }

            // Parse editing intent from text
            var hasEditOps = false
            if !text.isEmpty {
                let ops = Self.parseImageEditOperations(text)
                if !ops.isEmpty {
                    hasEditOps = true
                    let edited = await applyImageEdits(image, operations: ops)
                    editedImagePath = saveImage(edited, name: "edited_\(uuid)")
                }
            }

            // Analyze image using Vision framework (OCR, classification, etc.)
            if !hasEditOps {
                imageAnalysis = await imageService.analyzeImage(preprocessed)
            }

            selectedImages.removeAll()
        }

        // Handle document attachment (file already copied to app sandbox by AttachmentMenuView)
        var documentText: String?
        var documentName: String?
        if let docURL = attachedDocumentURL {
            documentName = docURL.lastPathComponent
            documentText = try? documentService.extractText(from: docURL)
            if text.isEmpty {
                userContent = "[Document: \(documentName ?? "document")]"
            }
            try? FileManager.default.removeItem(at: docURL)
            attachedDocumentURL = nil
        }

        // Persist conversation to DB on first message (deferred from createNewConversation)
        if messages.isEmpty {
            try? databaseService.createConversation(conversation)
        }

        // Save user message
        let userMessage = Message(conversationId: conversation.id, role: .user, content: userContent)
        try? databaseService.createMessage(userMessage)
        messages.append(userMessage)
        inputText = ""

        // Compute injected context sizes to reserve budget for them
        let docMaxChars = min(documentText?.count ?? 0, promptBudgetChars / 3)
        let imageAnalysisChars = min((imageAnalysis?.count ?? 0) + 200, 2000)
        let webSearchReserve = isWebSearchEnabled ? 3000 : 0
        let editContextChars = (attachedImage != nil && editedImagePath != nil) ? 300 : 0
        let reservedChars = docMaxChars + imageAnalysisChars + webSearchReserve + editContextChars + 200

        // Build messages for LLM (history trimmed to fit budget minus reserved)
        var llmMessages = await buildLLMMessages(userQuery: text, reservedChars: reservedChars)

        // Add document context
        if let docText = documentText, let docName = documentName {
            let truncated = String(docText.prefix(docMaxChars))
            var contextMsg = "The user has attached a document named \"\(docName)\". Here is the document content:\n\n\(truncated)"
            if docText.count > docMaxChars {
                contextMsg += "\n\n[Document truncated — showing first \(docMaxChars) characters of \(docText.count) total]"
            }
            llmMessages.insert(["role": "system", "content": contextMsg], at: 1)
        }

        // Add image analysis context
        if let analysis = imageAnalysis, !analysis.isEmpty {
            let capped = String(analysis.prefix(1800))
            let contextMsg = "The user has attached an image. Since you are a text-only model, the image was analyzed using on-device Vision AI. Here is what was detected:\n\n\(capped)\n\nUse this analysis to answer the user's question about the image."
            llmMessages.insert(["role": "system", "content": contextMsg], at: 1)
        }

        // Add image edit context to system prompt
        if attachedImage != nil, editedImagePath != nil {
            let desc = Self.describeImageEdits(text)
            llmMessages[0]["content"] = (llmMessages[0]["content"] ?? "") +
                "\n\nThe user attached an image and asked: \"\(text)\". These edits were applied to their image: \(desc). Briefly confirm what was done."
        }

        // Handle web search if enabled
        if isWebSearchEnabled {
            if let searchResults = try? await searchService.search(query: text), !searchResults.isEmpty {
                let searchText = String(searchResults.map { "- \($0.title): \($0.snippet)" }.joined(separator: "\n").prefix(2800))
                llmMessages.insert(
                    ["role": "system", "content": "Web search results for context:\n\(searchText)"],
                    at: min(1, llmMessages.count)
                )
            }
            isWebSearchEnabled = false
        }

        // Generate response
        isGenerating = true

        // Prepend edited image so it shows immediately during streaming
        if let editPath = editedImagePath {
            streamingText = "[IMAGE:\(editPath)]\n"
        } else {
            streamingText = ""
        }

        let stream = inferenceService.generate(messages: llmMessages)

        for await token in stream {
            streamingText += token
        }

        // Save assistant message
        let assistantMessage = Message(
            conversationId: conversation.id,
            role: .assistant,
            content: streamingText
        )
        try? databaseService.createMessage(assistantMessage)
        messages.append(assistantMessage)

        isGenerating = false
        tokensPerSecond = inferenceService.tokensPerSecond
        streamingText = ""
        loadConversations()
    }

    func stopGeneration() {
        inferenceService.cancelGeneration()
        if !streamingText.isEmpty, let conversation = currentConversation {
            let partialMessage = Message(
                conversationId: conversation.id,
                role: .assistant,
                content: streamingText
            )
            try? databaseService.createMessage(partialMessage)
            messages.append(partialMessage)
        }
        isGenerating = false
        streamingText = ""
    }

    func regenerateLastResponse() async {
        guard let lastAssistant = messages.last(where: { $0.role == .assistant }) else { return }
        try? databaseService.deleteMessage(id: lastAssistant.id)
        messages.removeAll { $0.id == lastAssistant.id }

        if let lastUserText = messages.last(where: { $0.role == .user })?.content {
            let llmMessages = await buildLLMMessages(userQuery: lastUserText)

            isGenerating = true
            streamingText = ""

            let stream = inferenceService.generate(messages: llmMessages)
            for await token in stream {
                streamingText += token
            }

            if let conversation = currentConversation {
                let msg = Message(conversationId: conversation.id, role: .assistant, content: streamingText)
                try? databaseService.createMessage(msg)
                messages.append(msg)
            }

            isGenerating = false
            streamingText = ""
        }
    }

    // MARK: - Edit & Resend

    func editAndResend(messageId: String, newContent: String) async {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }

        // Remove the edited message and all subsequent messages
        let toRemove = Array(messages[index...])
        for msg in toRemove {
            try? databaseService.deleteMessage(id: msg.id)
        }
        messages.removeSubrange(index...)

        // Send as new message
        inputText = newContent
        await sendMessage()
    }

    // MARK: - Search

    func searchMessages() {
        guard !searchQuery.isEmpty else {
            searchResults = []
            return
        }
        searchResults = (try? databaseService.searchMessages(query: searchQuery)) ?? []
    }

    // MARK: - Web Search

    private func performWebSearch(query: String, in conversation: Conversation) async {
        // Persist conversation to DB on first message if needed
        if messages.isEmpty {
            try? databaseService.createConversation(conversation)
        }

        let userMessage = Message(conversationId: conversation.id, role: .user, content: "/search \(query)")
        try? databaseService.createMessage(userMessage)
        messages.append(userMessage)

        isGenerating = true

        if let results = try? await searchService.search(query: query) {
            let searchContext = String(
                results.map { "- \($0.title): \($0.snippet) (\($0.url))" }
                    .joined(separator: "\n")
                    .prefix(promptBudgetChars - 500)
            )

            let llmMessages: [[String: String]] = [
                ["role": "system", "content": "You are SafeThink, a private AI assistant. Answer the user's question using these web search results:\n\(searchContext)"],
                ["role": "user", "content": query]
            ]

            streamingText = ""
            let stream = inferenceService.generate(messages: llmMessages)
            for await token in stream {
                streamingText += token
            }

            let msg = Message(conversationId: conversation.id, role: .assistant, content: "[Web-enhanced]\n\n\(streamingText)")
            try? databaseService.createMessage(msg)
            messages.append(msg)
        }

        isGenerating = false
        streamingText = ""
    }

    // MARK: - Image Editing

    private var chatImagesDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("chat_images", isDirectory: true)
    }

    private func saveImage(_ image: UIImage, name: String) -> String? {
        let dir = chatImagesDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let filename = "\(name).jpg"
        let fullURL = dir.appendingPathComponent(filename)
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        try? data.write(to: fullURL)
        return "chat_images/\(filename)"
    }

    static func loadChatImage(relativePath: String) -> UIImage? {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(relativePath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private enum ImageEditOp {
        case brightness(Double)
        case contrast(Double)
        case sepia
        case monochrome
        case vivid
        case blur(Double)
        case autoEnhance
        case rotate(CGFloat)
        case removeBackground
    }

    private static func parseImageEditOperations(_ text: String) -> [(description: String, op: ImageEditOp)] {
        let lowered = text.lowercased()
        var ops: [(description: String, op: ImageEditOp)] = []

        if lowered.contains("bright") || lowered.contains("lighten") || lowered.contains("lighter") {
            ops.append(("Increased brightness", .brightness(0.2)))
        }
        if lowered.contains("dark") || lowered.contains("dim") || lowered.contains("darker") {
            ops.append(("Decreased brightness", .brightness(-0.2)))
        }
        if lowered.contains("contrast") || lowered.contains("sharpen") || lowered.contains("sharp") {
            ops.append(("Increased contrast", .contrast(1.5)))
        }
        if lowered.contains("sepia") || lowered.contains("vintage") || lowered.contains("retro") {
            ops.append(("Applied sepia tone", .sepia))
        }
        if lowered.contains("warm") || lowered.contains("warmer") {
            ops.append(("Applied warm tone", .sepia))
        }
        if lowered.contains("b&w") || lowered.contains("black and white") || lowered.contains("monochrome") ||
            lowered.contains("grayscale") || lowered.contains("greyscale") {
            ops.append(("Converted to black & white", .monochrome))
        }
        if lowered.contains("vivid") || lowered.contains("vibrant") || lowered.contains("saturate") || lowered.contains("colorful") {
            ops.append(("Enhanced colors", .vivid))
        }
        if lowered.contains("blur") || lowered.contains("smooth") || lowered.contains("soften") {
            ops.append(("Applied blur", .blur(10)))
        }
        if lowered.contains("enhance") || lowered.contains("improve") || lowered.contains("fix") {
            ops.append(("Auto-enhanced", .autoEnhance))
        }
        if lowered.contains("rotate") || lowered.contains("turn") || lowered.contains("sideways") {
            ops.append(("Rotated 90°", .rotate(90)))
        }
        if lowered.contains("background") || lowered.contains("cut out") || lowered.contains("isolate") {
            ops.append(("Removed background", .removeBackground))
        }

        return ops
    }

    private static func describeImageEdits(_ text: String) -> String {
        parseImageEditOperations(text).map(\.description).joined(separator: ", ")
    }

    private func applyImageEdits(_ image: UIImage, operations: [(description: String, op: ImageEditOp)]) async -> UIImage {
        var result = image
        for (_, op) in operations {
            switch op {
            case .brightness(let val):
                result = imageService.adjustBrightnessContrast(result, brightness: val) ?? result
            case .contrast(let val):
                result = imageService.adjustBrightnessContrast(result, contrast: val) ?? result
            case .sepia:
                result = imageService.applySepia(result) ?? result
            case .monochrome:
                result = imageService.applyMonochrome(result) ?? result
            case .vivid:
                result = imageService.applyVivid(result) ?? result
            case .blur(let radius):
                result = imageService.applyBlur(result, radius: radius) ?? result
            case .autoEnhance:
                result = imageService.autoEnhance(result) ?? result
            case .rotate(let degrees):
                result = imageService.rotate(result, degrees: degrees)
            case .removeBackground:
                result = (try? await imageService.removeBackground(result)) ?? result
            }
        }
        return result
    }

    // MARK: - Helpers

    private func buildLLMMessages(userQuery: String, reservedChars: Int = 0) async -> [[String: String]] {
        let chatMLOverhead = 30 // <|im_start|>role\n...<|im_end|>\n per message
        let budget = promptBudgetChars - reservedChars

        // 1. System prompt (always included)
        let memoryContext = await memoryService.buildMemoryContext(for: userQuery)
        let defaults = UserDefaults.standard
        let basePrompt = defaults.string(forKey: "systemPrompt") ?? SettingsViewModel.defaultSystemPrompt
        let thinkingEnabled = defaults.object(forKey: "thinkingMode") as? Bool ?? false
        var systemPrompt = basePrompt + (thinkingEnabled ? " /think" : " /no_think")
        if !memoryContext.isEmpty {
            systemPrompt += "\n\n\(memoryContext)"
        }

        var usedChars = systemPrompt.count + chatMLOverhead

        // 2. Current user query (always included)
        let userQueryChars = userQuery.count + chatMLOverhead
        usedChars += userQueryChars

        // 3. Fill remaining budget with conversation history (newest first)
        var historyMessages: [[String: String]] = []
        let historyBudget = budget - usedChars

        var historyChars = 0
        for msg in messages.reversed() {
            let msgChars = msg.content.count + chatMLOverhead
            if historyChars + msgChars > historyBudget { break }
            historyMessages.insert(["role": msg.role.rawValue, "content": msg.content], at: 0)
            historyChars += msgChars
        }

        // Assemble final messages
        var llmMessages: [[String: String]] = []
        llmMessages.append(["role": "system", "content": systemPrompt])
        llmMessages.append(contentsOf: historyMessages)

        // Current user message (if not already in history from messages array)
        if messages.last?.content != userQuery {
            llmMessages.append(["role": "user", "content": userQuery])
        }

        return llmMessages
    }

    private func syncCurrentConversation(with updated: Conversation) {
        guard currentConversation?.id == updated.id else { return }
        currentConversation = updated
    }

    // MARK: - Grouped Conversations

    var pinnedConversations: [Conversation] {
        conversations.filter { $0.isPinned && !$0.isArchived }
    }

    var todayConversations: [Conversation] {
        conversations.filter { !$0.isPinned && !$0.isArchived && Calendar.current.isDateInToday($0.updatedAt) }
    }

    var yesterdayConversations: [Conversation] {
        conversations.filter { !$0.isPinned && !$0.isArchived && Calendar.current.isDateInYesterday($0.updatedAt) }
    }

    var thisWeekConversations: [Conversation] {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!
        return conversations.filter {
            !$0.isPinned && !$0.isArchived &&
            !calendar.isDateInToday($0.updatedAt) &&
            !calendar.isDateInYesterday($0.updatedAt) &&
            $0.updatedAt > weekAgo
        }
    }

    var olderConversations: [Conversation] {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        return conversations.filter {
            !$0.isPinned && !$0.isArchived && $0.updatedAt <= weekAgo
        }
    }
}
