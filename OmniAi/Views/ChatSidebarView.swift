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
    @State private var showDeleteConfirmation: Bool = false
    @State private var assistantToDelete: Assistant? = nil
    
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
                    ForEach(assistants) { assistant in
                Section {
                    Button(action: {
                        withAnimation {
                            if expandedIDs.contains(assistant.id) {
                                expandedIDs.remove(assistant.id)
                            } else {
                                expandedIDs.insert(assistant.id)
                            }
                        }
                    }) {
                        HStack {
                            Image(systemName: expandedIDs.contains(assistant.id) ? "chevron.down" : "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(assistant.name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Button(action: { editingAssistant = assistant }) {
                                Image(systemName: "square.and.pencil")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .onTapGesture { editingAssistant = assistant }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    if expandedIDs.contains(assistant.id) {
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
