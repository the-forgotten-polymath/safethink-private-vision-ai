import Foundation
import LlamaSwift

enum InferenceError: Error, LocalizedError {
    case modelNotLoaded
    case generationFailed(String)
    case outOfMemory
    case cancelled

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "No model is currently loaded"
        case .generationFailed(let msg): return "Generation failed: \(msg)"
        case .outOfMemory: return "Insufficient memory for this operation"
        case .cancelled: return "Generation was cancelled"
        }
    }
}

// Thread-safe flag shared between the main actor and the inference queue.
private final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false

    var isCancelled: Bool { lock.withLock { _cancelled } }
    func cancel() { lock.withLock { _cancelled = true } }
    func reset()  { lock.withLock { _cancelled = false } }
}

/// Wraps an OpaquePointer so it can be safely captured across sendability boundaries.
/// The caller is responsible for ensuring the pointer remains valid for the lifetime of any closure.
private struct SendablePointer: @unchecked Sendable {
    let pointer: OpaquePointer
}

@MainActor
final class InferenceService: ObservableObject {
    static let shared = InferenceService()

    @Published private(set) var isModelLoaded = false
    @Published private(set) var isGenerating = false
    @Published private(set) var loadedModelId: String?
    @Published private(set) var tokensPerSecond: Double = 0
    @Published private(set) var modelLoadProgress: Double = 0
    private(set) var contextSize: Int = 8192

    // Raw llama.cpp handles – only written on main actor via DispatchQueue.main callbacks.
    private var llamaModel: OpaquePointer?
    private var llamaContext: OpaquePointer?

    // Serial queue that serialises all llama.cpp calls.
    // Free is always enqueued after any in-progress generation block, so use-after-free is impossible.
    private let llamaQueue = DispatchQueue(label: "com.safethink.inference", qos: .userInitiated)

    private let cancelFlag = CancelFlag()

    private init() {
        llamaQueue.sync { llama_backend_init() }
        setupThermalMonitoring()
    }

    // MARK: - Model Loading

    func loadModel(from fileURL: URL) async throws {
        enqueueUnload()
        modelLoadProgress = 0

        let path = fileURL.path

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            llamaQueue.async {
                var mparams = llama_model_default_params()
                mparams.n_gpu_layers = 99

                guard let model = llama_model_load_from_file(path, mparams) else {
                    DispatchQueue.main.async {
                        cont.resume(throwing: InferenceError.generationFailed(
                            "Failed to load \(fileURL.lastPathComponent)"))
                    }
                    return
                }

                var cparams = llama_context_default_params()
                cparams.n_ctx = 8192
                cparams.n_batch = 512

                guard let ctx = llama_init_from_model(model, cparams) else {
                    llama_model_free(model)
                    DispatchQueue.main.async {
                        cont.resume(throwing: InferenceError.generationFailed("Failed to create inference context"))
                    }
                    return
                }

                DispatchQueue.main.async {
                    self.llamaModel = model
                    self.llamaContext = ctx
                    self.isModelLoaded = true
                    self.loadedModelId = fileURL.deletingLastPathComponent().lastPathComponent
                    self.modelLoadProgress = 1.0
                    cont.resume()
                }
            }
        }
    }

    func unloadModel() {
        cancelFlag.cancel()
        enqueueUnload()
        isModelLoaded = false
        loadedModelId = nil
        tokensPerSecond = 0
        modelLoadProgress = 0
    }

    // Enqueues a free of current handles on the serial queue.
    // Because the queue is serial, this always executes after any in-progress generation block.
    private func enqueueUnload() {
        let oldCtx   = llamaContext
        let oldModel = llamaModel
        llamaContext = nil
        llamaModel   = nil
        isModelLoaded = false

        llamaQueue.async {
            if let c = oldCtx   { llama_free(c) }
            if let m = oldModel { llama_model_free(m) }
        }
    }

    // MARK: - Background Management

    func scheduleBackgroundUnload() {
        llamaQueue.asyncAfter(deadline: .now() + 30) { [weak self] in
            DispatchQueue.main.async { self?.unloadModel() }
        }
    }

    func cancelBackgroundUnload() {}

    // MARK: - Thermal Monitoring

    private func setupThermalMonitoring() {
        let flag = cancelFlag
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if ProcessInfo.processInfo.thermalState == .critical {
                flag.cancel()
                self?.isGenerating = false
            }
        }
    }

    var thermalWarning: String? {
        switch ProcessInfo.processInfo.thermalState {
        case .serious:  return "Device is warm. Performance may be reduced."
        case .critical: return "Device is overheating. Generation paused."
        default:        return nil
        }
    }

    // MARK: - Text Generation

    func generate(
        messages: [[String: String]],
        maxTokens: Int = 2048,
        temperature: Float = 0.7,
        topP: Float = 0.9
    ) -> AsyncStream<String> {
        guard let model = llamaModel, let ctx = llamaContext else {
            return AsyncStream { $0.finish() }
        }

        cancelFlag.reset()
        isGenerating = true

        let flag    = cancelFlag
        let queue   = llamaQueue
        let maxT    = maxTokens
        let temp    = temperature
        let topPVal = topP
        let sModel  = SendablePointer(pointer: model)
        let sCtx    = SendablePointer(pointer: ctx)

        return AsyncStream { [weak self] continuation in
            queue.async {
                let model = sModel.pointer
                let ctx   = sCtx.pointer

                defer {
                    let mem = llama_get_memory(ctx)
                    llama_memory_clear(mem, true)
                    DispatchQueue.main.async { self?.isGenerating = false }
                    continuation.finish()
                }

                let vocab = llama_model_get_vocab(model)
                let prompt = Self.buildChatMLPrompt(from: messages)
                var tokens = Self.tokenize(vocab: vocab!, text: prompt)
                guard !tokens.isEmpty else { return }

                // Truncate prompt if it exceeds context budget (n_ctx - maxTokens for generation)
                let nCtx = Int(llama_n_ctx(ctx))
                let maxPromptTokens = nCtx - min(maxT, nCtx / 2)
                if tokens.count > maxPromptTokens {
                    tokens = Array(tokens.suffix(maxPromptTokens))
                }

                // Prefill: decode the prompt in n_batch-sized chunks to avoid exceeding batch buffer.
                let batchSize = Int(llama_n_batch(ctx))
                var prefillOK = true
                var offset = 0
                while offset < tokens.count {
                    let chunkSize = min(batchSize, tokens.count - offset)
                    let ok = tokens.withUnsafeMutableBufferPointer { buf in
                        let batch = llama_batch_get_one(buf.baseAddress! + offset, Int32(chunkSize))
                        return llama_decode(ctx, batch) == 0
                    }
                    if !ok { prefillOK = false; break }
                    offset += chunkSize
                }
                guard prefillOK else { return }

                // Sampler chain.
                guard let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params()) else { return }
                defer { llama_sampler_free(sampler) }
                llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40))
                llama_sampler_chain_add(sampler, llama_sampler_init_top_p(topPVal, 1))
                llama_sampler_chain_add(sampler, llama_sampler_init_temp(temp))
                llama_sampler_chain_add(sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED))

                let startTime = Date()
                var totalTokens = 0

                while totalTokens < maxT && !flag.isCancelled {
                    if ProcessInfo.processInfo.thermalState == .critical { break }

                    let newToken = llama_sampler_sample(sampler, ctx, -1)
                    if llama_vocab_is_eog(vocab, newToken) { break }

                    var buf = [CChar](repeating: 0, count: 256)
                    let nPiece = llama_token_to_piece(vocab, newToken, &buf, 256, 0, false)
                    if nPiece > 0 {
                        let bytes = buf.prefix(Int(nPiece)).map { UInt8(bitPattern: $0) }
                        if let piece = String(bytes: bytes, encoding: .utf8), !piece.isEmpty {
                            continuation.yield(piece)
                        }
                    }

                    totalTokens += 1

                    if totalTokens % 10 == 0 {
                        let tps = Double(totalTokens) / max(Date().timeIntervalSince(startTime), 0.001)
                        DispatchQueue.main.async { self?.tokensPerSecond = tps }
                    }

                    // Advance KV cache with the new token.
                    var nextToken = newToken
                    let decodeOK = withUnsafeMutablePointer(to: &nextToken) { ptr in
                        let batch = llama_batch_get_one(ptr, 1)
                        return llama_decode(ctx, batch) == 0
                    }
                    if !decodeOK { break }
                }
            }
        }
    }

    func cancelGeneration() {
        cancelFlag.cancel()
        isGenerating = false
    }

    // MARK: - Helpers

    nonisolated private static func tokenize(vocab: OpaquePointer, text: String) -> [Int32] {
        return text.withCString { cStr in
            let textLen = Int32(strlen(cStr))
            let nRequired = llama_tokenize(vocab, cStr, textLen, nil, 0, true, true)
            let count = Int(-nRequired)
            guard count > 0 else { return [] }
            var tokens = [Int32](repeating: 0, count: count)
            let n = llama_tokenize(vocab, cStr, textLen, &tokens, Int32(count), true, true)
            guard n > 0 else { return [] }
            return Array(tokens.prefix(Int(n)))
        }
    }

    nonisolated private static func buildChatMLPrompt(from messages: [[String: String]]) -> String {
        var prompt = ""
        for message in messages {
            let role    = message["role"]    ?? "user"
            let content = message["content"] ?? ""
            prompt += "<|im_start|>\(role)\n\(content)<|im_end|>\n"
        }
        prompt += "<|im_start|>assistant\n"
        return prompt
    }
}
