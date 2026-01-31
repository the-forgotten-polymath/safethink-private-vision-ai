import Foundation
import Speech
import AVFoundation

enum VoiceInputMode: String, CaseIterable {
    case holdToTalk = "Hold to Talk"
    case toggle = "Toggle"
    case autoStop = "Auto-Stop"
}

@MainActor
final class VoiceService: ObservableObject {
    static let shared = VoiceService()

    @Published var isRecording = false
    @Published var transcribedText = ""
    @Published var audioLevel: Float = 0
    @Published var isAuthorized = false
    @Published var inputMode: VoiceInputMode = .autoStop
    @Published var autoStopDuration: TimeInterval = 2.0

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var silenceTimer: Timer?

    private init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    }

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    self.isAuthorized = (status == .authorized)
                    continuation.resume(returning: status == .authorized)
                }
            }
        }
    }

    func startRecording() throws {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw VoiceError.recognizerUnavailable
        }

        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true

        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcribedText = result.bestTranscription.formattedString
                    self.resetSilenceTimer()
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.stopRecording()
                }
            }
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)

            // Calculate audio level for waveform
            let channelData = buffer.floatChannelData?[0]
            let frameLength = Int(buffer.frameLength)
            if let data = channelData {
                var sum: Float = 0
                for i in 0..<frameLength {
                    sum += abs(data[i])
                }
                let avg = sum / Float(frameLength)
                Task { @MainActor in
                    self?.audioLevel = avg
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()

        isRecording = true
        transcribedText = ""
    }

    func stopRecording() {
        silenceTimer?.invalidate()
        silenceTimer = nil

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        isRecording = false
        audioLevel = 0
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        guard inputMode == .autoStop else { return }
        silenceTimer = Timer.scheduledTimer(withTimeInterval: autoStopDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.stopRecording()
            }
        }
    }
}

enum VoiceError: Error, LocalizedError {
    case recognizerUnavailable
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable: return "Speech recognizer is not available"
        case .notAuthorized: return "Speech recognition not authorized"
        }
    }
}
