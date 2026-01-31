import SwiftUI

enum NavigationDestination: Hashable {
    case conversations
    case models
    case privacy
    case settings
}

struct ContentView: View {
    @StateObject private var chatViewModel = ChatViewModel()
    @State private var showSidebar = false
    @State private var navigationPath = NavigationPath()

    var body: some View {
        ZStack(alignment: .leading) {
            // Main content with NavigationStack for proper push/pop navigation
            NavigationStack(path: $navigationPath) {
                ChatView(
                    viewModel: chatViewModel,
                    onShowSidebar: { withAnimation(.easeOut(duration: 0.25)) { showSidebar = true } },
                    onNavigateToModels: { navigationPath.append(NavigationDestination.models) }
                )
                .navigationDestination(for: NavigationDestination.self) { destination in
                    switch destination {
                    case .conversations:
                        ConversationListView(viewModel: chatViewModel) {
                            navigationPath = NavigationPath()
                        }
                    case .models:
                        ModelManagerView()
                    case .privacy:
                        PrivacyDashboardView()
                    case .settings:
                        SettingsView()
                    }
                }
            }
            .disabled(showSidebar)

            // Dim overlay
            if showSidebar {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.25)) { showSidebar = false }
                    }
            }

            // Sidebar drawer
            if showSidebar {
                sidebarPanel
                    .transition(.move(edge: .leading))
            }
        }
    }

    // MARK: - Sidebar

    private var sidebarPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("SafeThink")
                    .font(.title2.bold())
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.25)) { showSidebar = false }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(spacing: 2) {
                    sidebarRow("Chat", icon: "bubble.left.and.bubble.right", destination: nil)
                    sidebarRow("Conversations", icon: "text.bubble", destination: .conversations)
                    sidebarRow("Models", icon: "cpu", destination: .models)
                    sidebarRow("Privacy", icon: "lock.shield", destination: .privacy)
                    sidebarRow("Settings", icon: "gearshape", destination: .settings)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
            }

            Spacer()
        }
        .frame(width: 300)
        .background(.regularMaterial)
        .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 16, topTrailingRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 8)
        .ignoresSafeArea(edges: .vertical)
    }

    private func sidebarRow(_ title: String, icon: String, destination: NavigationDestination?) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.25)) { showSidebar = false }
            navigateTo(destination)
        } label: {
            Label(title, systemImage: icon)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(destination == nil && navigationPath.isEmpty
                      ? Color.accentColor.opacity(0.12)
                      : Color.clear)
        )
    }

    private func navigateTo(_ destination: NavigationDestination?) {
        guard let destination else {
            // Chat = pop to root
            navigationPath = NavigationPath()
            return
        }
        if navigationPath.isEmpty {
            navigationPath.append(destination)
        } else {
            // Pop to root, then push after a brief delay so the stack settles
            navigationPath = NavigationPath()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                navigationPath.append(destination)
            }
        }
    }
}

#Preview {
    ContentView()
}
