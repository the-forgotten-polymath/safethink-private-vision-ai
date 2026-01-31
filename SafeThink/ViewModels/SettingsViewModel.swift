import Foundation
import SwiftUI

enum AppTheme: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum ResponseFormat: String, CaseIterable {
    case normal = "Normal"
    case concise = "Concise"
    case detailed = "Detailed"
}

@MainActor
final class SettingsViewModel: ObservableObject {
    // General
    @Published var theme: AppTheme = .system
    @Published var hapticFeedback = true

    // AI Model
    @Published var thinkingMode = false
    @Published var customizationEnabled = false
    @Published var temperature: Double = 0.7
    @Published var topP: Double = 0.9
    @Published var systemPrompt = SettingsViewModel.defaultSystemPrompt
    @Published var responseFormat: ResponseFormat = .normal
    @Published var showTokensPerSec = true

    // Voice
    @Published var voiceInputMode: VoiceInputMode = .autoStop
    @Published var autoStopDuration: Double = 2.0

    // Data
    @Published var showClearConfirmation = false
    @Published var clearTarget: ClearTarget = .chats

    enum ClearTarget {
        case chats, documents, memories, allData
    }

    private let defaults = UserDefaults.standard

    init() {
        loadSettings()
    }

    static let defaultSystemPrompt: String = {
        if let url = Bundle.main.url(forResource: "DefaultSystemPrompt", withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "You are SafeThink, a private AI assistant that runs entirely on the user's iPhone. No data ever leaves this device. Be concise and helpful."
    }()

    func loadSettings() {
        theme = AppTheme(rawValue: defaults.string(forKey: "theme") ?? "System") ?? .system
        hapticFeedback = defaults.object(forKey: "haptic") as? Bool ?? true
        thinkingMode = defaults.object(forKey: "thinkingMode") as? Bool ?? false
        customizationEnabled = defaults.object(forKey: "customizationEnabled") as? Bool ?? false
        temperature = defaults.object(forKey: "temperature") as? Double ?? 0.7
        topP = defaults.object(forKey: "topP") as? Double ?? 0.9
        systemPrompt = defaults.string(forKey: "systemPrompt") ?? Self.defaultSystemPrompt
        responseFormat = ResponseFormat(rawValue: defaults.string(forKey: "responseFormat") ?? "Normal") ?? .normal
        showTokensPerSec = defaults.object(forKey: "showTokSec") as? Bool ?? true
        voiceInputMode = VoiceInputMode(rawValue: defaults.string(forKey: "voiceInputMode") ?? VoiceInputMode.autoStop.rawValue) ?? .autoStop
        autoStopDuration = defaults.object(forKey: "autoStopDuration") as? Double ?? 2.0
    }

    func saveSettings() {
        defaults.set(theme.rawValue, forKey: "theme")
        defaults.set(hapticFeedback, forKey: "haptic")
        defaults.set(thinkingMode, forKey: "thinkingMode")
        defaults.set(customizationEnabled, forKey: "customizationEnabled")
        defaults.set(temperature, forKey: "temperature")
        defaults.set(topP, forKey: "topP")
        defaults.set(systemPrompt, forKey: "systemPrompt")
        defaults.set(responseFormat.rawValue, forKey: "responseFormat")
        defaults.set(showTokensPerSec, forKey: "showTokSec")
        defaults.set(voiceInputMode.rawValue, forKey: "voiceInputMode")
        defaults.set(autoStopDuration, forKey: "autoStopDuration")
    }

    func clearData(target: ClearTarget) {
        let db = DatabaseService.shared
        switch target {
        case .chats:
            try? db.deleteAllChats()
        case .documents:
            try? db.deleteAllDocuments()
        case .memories:
            try? db.deleteAllMemories()
        case .allData:
            try? db.deleteAllData()
        }
    }

    // Storage info
    var storageBreakdown: [(String, String)] {
        let fm = FileManager.default
        let docDir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]

        func dirSize(_ path: String) -> Int64 {
            let url = docDir.appendingPathComponent(path)
            var size: Int64 = 0
            if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let fileURL as URL in enumerator {
                    if let s = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        size += Int64(s)
                    }
                }
            }
            return size
        }

        return [
            ("Models", ByteCountFormatter.string(fromByteCount: dirSize("models"), countStyle: .file)),
            ("Chats", ByteCountFormatter.string(fromByteCount: dirSize("database"), countStyle: .file)),
            ("Documents", ByteCountFormatter.string(fromByteCount: dirSize("documents"), countStyle: .file)),
            ("Embeddings", ByteCountFormatter.string(fromByteCount: dirSize("embeddings"), countStyle: .file)),
            ("Exports", ByteCountFormatter.string(fromByteCount: dirSize("exports"), countStyle: .file)),
        ]
    }
}
