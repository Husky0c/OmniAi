import SwiftUI
import SwiftData

struct ChatSidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatSession.lastModified, order: .reverse) private var sessions: [ChatSession]
    @Binding var selectedSession: ChatSession?
    var onSessionSelected: (() -> Void)? = nil
    
    var body: some View {
        // 使用条件编译区分 List 行为
#if os(iOS)
        List {
            listContent
        }
        .onChange(of: selectedSession) { _, newValue in
            print("ChatSidebarView: selectedSession changed to \(String(describing: newValue?.id))")
            onSessionSelected?()
        }
        .navigationTitle("会话")
#else
        List(selection: $selectedSession) {
            listContent
        }
        .onChange(of: selectedSession) { _, _ in
            onSessionSelected?()
        }
        .navigationTitle("会话")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: addSession) {
                    Label("新建对话", systemImage: "square.and.pencil")
                }
            }
        }
#endif
    }
    
    @ViewBuilder
    private var listContent: some View {
        Button(action: {
            print("ChatSidebarView: 新建对话按钮被点击了")
            addSession()
        }) {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("新建对话")
                    .fontWeight(.bold)
            }
            .padding(.vertical, 8)
            .foregroundStyle(.blue)
            // 确保整个 HStack 区域可点击
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        
        ForEach(sessions) { session in
#if os(iOS)
            // iOS 侧滑栏：使用 Button 防止 NavigationLink 的异常 Push 行为
            Button(action: {
                print("ChatSidebarView: 历史会话被点击了 - \(session.title)")
                selectedSession = session
            }) {
                VStack(alignment: .leading) {
                    Text(session.title)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundStyle(selectedSession == session ? Color.accentColor : Color.primary)
                    Text(session.lastModified, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
#else
            // macOS: SplitView 配合 NavigationLink 工作最佳
            NavigationLink(value: session) {
                VStack(alignment: .leading) {
                    Text(session.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(session.lastModified, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
#endif
        }
        .onDelete(perform: deleteSessions)
    }
    
    private func addSession() {
        print("ChatSidebarView: 正在执行 addSession()...")
        withAnimation {
            let newSession = ChatSession(title: "新对话")
            modelContext.insert(newSession)
            do {
                try modelContext.save()
                print("ChatSidebarView: 会话保存成功")
            } catch {
                print("ChatSidebarView: 会话保存失败 - \(error)")
            }
            selectedSession = newSession
            print("ChatSidebarView: 已更新 selectedSession = \(newSession.id)")
        }
    }
    
    private func deleteSessions(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let session = sessions[index]
                if selectedSession == session {
                    selectedSession = nil
                }
                modelContext.delete(session)
            }
            try? modelContext.save()
        }
    }
}
