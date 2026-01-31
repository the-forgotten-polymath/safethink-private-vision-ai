import SwiftUI

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject private var inferenceService = InferenceService.shared
    @StateObject private var voiceService = VoiceService.shared
    var onShowSidebar: (() -> Void)?
    var onNavigateToModels: (() -> Void)?
    @State private var showConversationList = false
    @State private var showAttachmentMenu = false
    @State private var editingMessageId: String?
    @State private var editText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubbleView(
                                message: message,
                                onRegenerate: {
                                    Task { await viewModel.regenerateLastResponse() }
                                },
                                onEdit: message.role == .user ? {
                                    editingMessageId = message.id
                                    editText = message.content
                                } : nil
                            )
                            .id(message.id)
                        }

                        // Streaming response
                        if viewModel.isGenerating && !viewModel.streamingText.isEmpty {
                            MessageBubbleView(
                                message: Message(
                                    conversationId: "",
                                    role: .assistant,
                                    content: viewModel.streamingText
                                ),
                                isStreaming: true
                            )
                            .id("streaming")
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    withAnimation {
                        proxy.scrollTo(viewModel.messages.last?.id ?? "streaming", anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.streamingText) { _, _ in
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }

            // Voice recording indicator
            if voiceService.isRecording {
                HStack(spacing: 8) {
                    WaveformView(audioLevel: voiceService.audioLevel, isRecording: true)
                    Text(voiceService.transcribedText.isEmpty ? "Listening..." : voiceService.transcribedText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        voiceService.stopRecording()
                        if !voiceService.transcribedText.isEmpty {
                            viewModel.inputText = voiceService.transcribedText
                        }
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color(.systemGray6))
            }

            // Context indicator
            if viewModel.currentConversation != nil {
                HStack {
                    Text(viewModel.contextUsage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if viewModel.isGenerating {
                        Text("\(viewModel.tokensPerSecond, specifier: "%.1f") tok/s")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }

            Divider()

            // Image preview
            if !viewModel.selectedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(viewModel.selectedImages.enumerated()), id: \.offset) { index, image in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                Button {
                                    viewModel.selectedImages.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.white, Color.black.opacity(0.6))
                                }
                                .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.vertical, 4)
            }

            // Document preview
            if viewModel.attachedDocumentURL != nil {
                HStack(spacing: 8) {
                    Image(systemName: "doc.fill")
                        .foregroundStyle(.blue)
                    Text(viewModel.attachedDocumentURL?.lastPathComponent ?? "Document")
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        viewModel.attachedDocumentURL = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 12)
            }

            // Web search indicator
            if viewModel.isWebSearchEnabled {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .foregroundStyle(.blue)
                    Text("Web search enabled for next message")
                        .font(.caption)
                    Spacer()
                    Button {
                        viewModel.isWebSearchEnabled = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 12)
            }

            // Input bar
            InputBarView(
                text: $viewModel.inputText,
                isGenerating: viewModel.isGenerating,
                hasAttachment: !viewModel.selectedImages.isEmpty || viewModel.attachedDocumentURL != nil || viewModel.isWebSearchEnabled,
                onSend: { Task { await viewModel.sendMessage() } },
                onStop: { viewModel.stopGeneration() },
                onAttachment: { showAttachmentMenu = true },
                onMic: { toggleVoiceInput() }
            )
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    onShowSidebar?()
                } label: {
                    Image(systemName: "line.3.horizontal")
                }
            }
            ToolbarItem(placement: .principal) {
                Button {
                    onNavigateToModels?()
                } label: {
                    HStack(spacing: 2) {
                        Text(activeModelDisplayName)
                            .font(.headline)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.createNewConversation()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .sheet(isPresented: $showConversationList) {
            NavigationStack {
                ConversationListView(viewModel: viewModel) {
                    showConversationList = false
                }
            }
        }
        .sheet(isPresented: $showAttachmentMenu) {
            AttachmentMenuView(viewModel: viewModel)
                .presentationDetents([.medium])
        }
        .alert("Edit Message", isPresented: .init(
            get: { editingMessageId != nil },
            set: { if !$0 { editingMessageId = nil } }
        )) {
            TextField("Edit message", text: $editText)
            Button("Cancel", role: .cancel) { editingMessageId = nil }
            Button("Send") {
                if let id = editingMessageId {
                    Task { await viewModel.editAndResend(messageId: id, newContent: editText) }
                    editingMessageId = nil
                }
            }
        }
        .alert("No Model Loaded", isPresented: $viewModel.showNoModelAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please go to the Models tab in the sidebar to download and load a model before chatting.")
        }
        .onAppear {
            viewModel.loadConversations()
        }
    }

    private var activeModelDisplayName: String {
        guard let loadedId = inferenceService.loadedModelId,
              let model = ModelInfo.registry.first(where: { $0.id == loadedId }) else {
            return "No Model"
        }
        return model.displayName
    }

    private func toggleVoiceInput() {
        if voiceService.isRecording {
            voiceService.stopRecording()
            if !voiceService.transcribedText.isEmpty {
                viewModel.inputText = voiceService.transcribedText
            }
        } else {
            Task {
                let authorized = await voiceService.requestAuthorization()
                if authorized {
                    try? voiceService.startRecording()
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ChatView(viewModel: ChatViewModel(), onShowSidebar: nil)
    }
}
