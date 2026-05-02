import SwiftUI
import SwiftData

struct ChatSidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Assistant.createdAt) private var assistants: [Assistant]
    @Binding var selectedSession: ChatSession?
    var onSessionSelected: (() -> Void)? = nil
    
    @State private var expandedIDs: Set<UUID> = []
    @State private var showNewAssistant = false
    @State private var editingAssistant: Assistant? = nil
    
    private var sortedAssistants: [Assistant] {
        assistants.sorted { $0.isBuiltIn && !$1.isBuiltIn || ($0.isBuiltIn == $1.isBuiltIn && $0.createdAt < $1.createdAt) }
    }
    
    var body: some View {
        ZStack {
            if assistants.isEmpty {
                ContentUnavailableView(
                    "还没有助手",
                    systemImage: "person.2",
                    description: Text("点击底部按钮创建第一个助手")
                )
            } else {
                List {
                    ForEach(sortedAssistants) { assistant in
                    Section {
                        HStack {
                            Button(action: {
                                if assistant.isBuiltIn {
                                    editingAssistant = assistant
                                } else {
                                    withAnimation {
                                        if expandedIDs.contains(assistant.id) {
                                            expandedIDs.remove(assistant.id)
                                        } else {
                                            expandedIDs.insert(assistant.id)
                                        }
                                    }
                                }
                            }) {
                                HStack {
                                    if !assistant.isBuiltIn {
                                        Image(systemName: expandedIDs.contains(assistant.id) ? "chevron.down" : "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(assistant.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    if assistant.isBuiltIn {
                                        Text("内置")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { editingAssistant = assistant }) {
                                Image(systemName: "square.and.pencil")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    
                    if !assistant.isBuiltIn, expandedIDs.contains(assistant.id) {
                        let sortedSessions = assistant.sessions.sorted { $0.lastModified > $1.lastModified }
                        
                        ForEach(sortedSessions) { session in
                            Button(action: {
                                selectedSession = session
                                onSessionSelected?()
                            }) {
                                VStack(alignment: .leading) {
                                    Text(session.title)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                        .foregroundStyle(selectedSession == session ? Color.accentColor : Color.primary)
                                    Text(session.lastModified, style: .time)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 2)
                                .padding(.leading, 20)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            deleteSessions(offsets, from: assistant)
                        }
                        
                        Button(action: { addSession(to: assistant) }) {
                            Label("新建对话", systemImage: "plus.circle")
                                .font(.subheadline)
                                .foregroundStyle(.blue)
                                .padding(.leading, 20)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            }
            }
        }
        .navigationTitle("助手")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .safeAreaInset(edge: .bottom) {
            Button(action: { showNewAssistant = true }) {
                HStack {
                    Label("新增助手", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.blue)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showNewAssistant) {
            NewAssistantView()
        }
        .sheet(item: $editingAssistant) { assistant in
            AssistantSettingsView(assistant: assistant)
        }
        .onAppear {
            let seeded = UserDefaults.standard.bool(forKey: "builtInAssistantsSeeded")
            if !seeded {
                let t = Assistant(name: "翻译助手", systemPrompt: "你是一个专业的翻译助手，请将用户输入的内容准确翻译为目标语言。", isBuiltIn: true)
                modelContext.insert(t)
                let q = Assistant(name: "快速任务助手", systemPrompt: "你是一个高效的任务助手，请简洁准确地完成用户指定的任务。", isBuiltIn: true)
                modelContext.insert(q)
                UserDefaults.standard.set(true, forKey: "builtInAssistantsSeeded")
            }
        }
    }
    
    private func addSession(to assistant: Assistant) {
        withAnimation {
            let newSession = ChatSession(title: "新对话", assistant: assistant)
            modelContext.insert(newSession)
            assistant.sessions.append(newSession)
            selectedSession = newSession
        }
    }
    
    private func deleteSessions(_ offsets: IndexSet, from assistant: Assistant) {
        let sorted = assistant.sessions.sorted { $0.lastModified > $1.lastModified }
        for index in offsets {
            let session = sorted[index]
            if selectedSession == session {
                selectedSession = nil
            }
            modelContext.delete(session)
        }
    }
}
