import SwiftUI

struct ConversationListView: View {
    @ObservedObject var viewModel: ChatViewModel
    var onDismiss: () -> Void
    @State private var filter: ConversationFilter = .all

    enum ConversationFilter: String, CaseIterable {
        case all = "All"
        case pinned = "Pinned"
        case archived = "Archived"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search conversations...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .onChange(of: viewModel.searchQuery) { _, _ in
                        viewModel.searchMessages()
                    }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)

            // Filter
            Picker("Filter", selection: $filter) {
                ForEach(ConversationFilter.allCases, id: \.self) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            // Conversations list
            List {
                if !viewModel.searchQuery.isEmpty {
                    Section("Search Results") {
                        ForEach(viewModel.searchResults) { message in
                            Button {
                                if let conversation = viewModel.conversations.first(where: { $0.id == message.conversationId }) {
                                    viewModel.selectConversation(conversation)
                                    onDismiss()
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(strippingThinkTags(message.content))
                                        .lineLimit(2)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    Text(message.createdAt, format: .dateTime.month().day().hour().minute())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else {
                    conversationSections
                }
            }
            .listStyle(.insetGrouped)
        }
        .navigationTitle("Conversations")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var conversationSections: some View {
        let filtered = filteredConversations

        if !viewModel.pinnedConversations.isEmpty && filter != .archived {
            Section("Pinned") {
                ForEach(viewModel.pinnedConversations) { conv in
                    conversationRow(conv)
                }
            }
        }

        if filter == .all {
            if !viewModel.todayConversations.isEmpty {
                Section("Today") {
                    ForEach(viewModel.todayConversations) { conv in
                        conversationRow(conv)
                    }
                }
            }
            if !viewModel.yesterdayConversations.isEmpty {
                Section("Yesterday") {
                    ForEach(viewModel.yesterdayConversations) { conv in
                        conversationRow(conv)
                    }
                }
            }
            if !viewModel.thisWeekConversations.isEmpty {
                Section("This Week") {
                    ForEach(viewModel.thisWeekConversations) { conv in
                        conversationRow(conv)
                    }
                }
            }
            if !viewModel.olderConversations.isEmpty {
                Section("Older") {
                    ForEach(viewModel.olderConversations) { conv in
                        conversationRow(conv)
                    }
                }
            }
        }

        if filter == .archived {
            let archived = viewModel.conversations.filter { $0.isArchived }
            if archived.isEmpty {
                ContentUnavailableView("No Archived Chats", systemImage: "archivebox")
            } else {
                ForEach(archived) { conv in
                    conversationRow(conv)
                }
            }
        }

        if filtered.isEmpty && filter == .all {
            ContentUnavailableView("No Conversations", systemImage: "bubble.left.and.bubble.right",
                description: Text("Start a new conversation to get going"))
        }
    }

    private func strippingThinkTags(_ content: String) -> String {
        var text = content
        while let start = text.range(of: "<think>") {
            if let end = text.range(of: "</think>", range: start.upperBound..<text.endIndex) {
                text.removeSubrange(start.lowerBound..<end.upperBound)
            } else {
                text.removeSubrange(start.lowerBound...)
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredConversations: [Conversation] {
        switch filter {
        case .all: return viewModel.conversations.filter { !$0.isArchived }
        case .pinned: return viewModel.pinnedConversations
        case .archived: return viewModel.conversations.filter { $0.isArchived }
        }
    }

    private func conversationRow(_ conversation: Conversation) -> some View {
        Button {
            viewModel.selectConversation(conversation)
            onDismiss()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if conversation.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(conversation.title)
                        .lineLimit(1)
                        .font(.body)
                        .foregroundStyle(.primary)
                }
                Text("\(conversation.messageCount) messages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                viewModel.deleteConversation(conversation)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                viewModel.togglePin(conversation)
            } label: {
                Label(conversation.isPinned ? "Unpin" : "Pin",
                      systemImage: conversation.isPinned ? "pin.slash" : "pin")
            }
            .tint(.orange)

            Button {
                viewModel.toggleArchive(conversation)
            } label: {
                Label(conversation.isArchived ? "Unarchive" : "Archive",
                      systemImage: conversation.isArchived ? "tray.and.arrow.up" : "archivebox")
            }
            .tint(.purple)
        }
    }
}
