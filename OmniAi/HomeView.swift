import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

struct HomeView: View {
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
        }
    }
}

struct MainStageView: View {
    var selectedSession: ChatSession?
    var onToggleSidebar: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    
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
                    ContentUnavailableView(
                        "没有选中的对话",
                        systemImage: "message",
                        description: Text("请在左侧选择一个对话或新建对话")
                    )
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
#if canImport(UIKit)
                                Group {
                                    if let image = AvatarManager.load() {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                    } else {
                                        Image(systemName: "person.crop.circle.fill")
                                            .resizable()
                                            .foregroundStyle(.blue)
                                    }
                                }
                                .frame(width: 28, height: 28)
                                .clipShape(Circle())
#else
                                Image(systemName: "person.crop.circle.fill")
                                    .foregroundStyle(.blue)
#endif
                            }
                        }
#else
                        ToolbarItem(placement: .primaryAction) {
                            Button(action: { onOpenSettings?() }) {
                                Image(systemName: "person.crop.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
#endif
                    }
                }
            }
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [ChatSession.self, ChatMessage.self], inMemory: true)
}
