import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appServices) private var appServices
    @State private var selectedSession: ChatSession?
    @State private var isSidebarOpen: Bool = false
    @State private var showSettings: Bool = false
    
    var body: some View {
        ZStack {
#if os(iOS)
            InteractiveDrawer(isOpen: $isSidebarOpen) {
                NavigationStack {
                    ChatSidebarView(selectedSession: $selectedSession) {
                        // 移除显式的 withAnimation，全权交给底层容器的隐式动画处理
                        isSidebarOpen = false
                    }
                }
            } mainContent: {
                MainStageView(
                    selectedSession: selectedSession,
                    // 移除显式的 withAnimation，全权交给底层容器的隐式动画处理
                    onToggleSidebar: { isSidebarOpen.toggle() },
                    onOpenSettings: { showSettings = true }
                )
            }
#else
            NavigationSplitView {
                ChatSidebarView(selectedSession: $selectedSession)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 250)
            } detail: {
                MainStageView(
                    selectedSession: selectedSession,
                    onToggleSidebar: nil,
                    onOpenSettings: { showSettings = true }
                )
            }
#endif
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
#if os(macOS)
                .frame(minWidth: 560, idealWidth: 640, minHeight: 520, idealHeight: 620)
#endif
        }
        .task {
            await appServices.toolServiceFactory.releaseServicesNotInModelContext(modelContext)
        }
    }
}

struct MainStageView: View {
    var selectedSession: ChatSession?
    var onToggleSidebar: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    @Environment(\.avatarManager) private var avatarManager
    
    var body: some View {
        NavigationStack {
            Group {
                if let session = selectedSession {
                    ChatDetailView(
                        session: session,
                        onToggleSidebar: onToggleSidebar,
                        onOpenSettings: onOpenSettings
                    )
                    .id(session.id)
                } else {
                    EmptyChatSelectionView()
                    .toolbar {
#if os(iOS)
                        ToolbarItem(placement: .topBarLeading) {
                            Button(action: { onToggleSidebar?() }) {
                                Image(systemName: "line.3.horizontal")
                                    .foregroundStyle(.primary)
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(action: { onOpenSettings?() }) {
                                AvatarImageView(image: avatarManager.cachedImage)
                                .frame(width: 28, height: 28)
                                .clipShape(Circle())
                            }
                        }
#else
                        ToolbarItem(placement: .primaryAction) {
                            Button(action: { onOpenSettings?() }) {
                                AvatarImageView(image: avatarManager.cachedImage)
                                    .frame(width: 28, height: 28)
                                    .clipShape(Circle())
                            }
                        }
#endif
                    }
                }
            }
#if os(macOS)
            .frame(minWidth: 520, minHeight: 420)
#endif
        }
        .task {
            _ = avatarManager.loadAsync()
        }
    }
}

private struct EmptyChatSelectionView: View {
    var body: some View {
        ContentUnavailableView(
            "home.no_selected_chat.title",
            systemImage: "message",
            description: Text("home.no_selected_chat.description")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
#if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
#endif
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [ChatSession.self, ChatMessage.self], inMemory: true)
}
