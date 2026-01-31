import XCTest
@testable import SafeThink

@MainActor
final class SettingsViewModelTests: XCTestCase {
    private let defaults = UserDefaults.standard
    private let keys = [
        "theme",
        "haptic",
        "contextLimit",
        "temperature",
        "topP",
        "systemPrompt",
        "responseFormat",
        "showTokSec",
        "voiceInputMode",
        "autoStopDuration"
    ]

    override func setUp() {
        super.setUp()
        clearSettings()
    }

    override func tearDown() {
        clearSettings()
        super.tearDown()
    }

    func testVoiceSettingsPersist() {
        let sut = SettingsViewModel()
        sut.voiceInputMode = .toggle
        sut.autoStopDuration = 4.5

        sut.saveSettings()

        let reloaded = SettingsViewModel()
        XCTAssertEqual(reloaded.voiceInputMode, .toggle)
        XCTAssertEqual(reloaded.autoStopDuration, 4.5, accuracy: 0.001)
    }

    private func clearSettings() {
        for key in keys {
            defaults.removeObject(forKey: key)
        }
    }
}
