import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appServices) private var appServices
    @State private var selectedSession: ChatSession?
    @State private var isSidebarOpen: Bool = false
    @State private var showSettings: Bool = false
#if os(macOS)
    @State private var selectedTab: NavigationTab = .chat
#endif

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
            HStack(spacing: 0) {
                // Left: Icon navigation sidebar
                NavigationSidebarView(
                    selectedTab: $selectedTab,
                    onOpenSettings: { selectedTab = .settings }
                )

                Divider()

                // Right: Main content area
                if selectedTab == .chat {
                    NavigationSplitView {
                        // Assistant list
                        ChatSidebarView(selectedSession: $selectedSession)
                            .navigationSplitViewColumnWidth(min: 200, ideal: 250)
                    } detail: {
                        // Chat messages
                        MainStageView(
                            selectedSession: selectedSession,
                            onToggleSidebar: nil,
                            onOpenSettings: nil
                        )
                    }
                } else if selectedTab == .settings {
                    SettingsView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
#endif
        }
#if os(iOS)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
#endif
        .task {
            await appServices.toolServiceFactory.releaseServicesNotInModelContext(modelContext)
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [ChatSession.self, ChatMessage.self], inMemory: true)
}
