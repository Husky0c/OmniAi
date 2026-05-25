import SwiftUI
import SwiftData

struct ChatSidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appServices) private var appServices
    @Query(sort: \Assistant.createdAt) private var assistants: [Assistant]
    @Binding var selectedSession: ChatSession?
    var onSessionSelected: (() -> Void)? = nil

    @State private var expandedIDs: Set<UUID> = []
    @State private var showNewAssistant = false
    @State private var editingAssistant: Assistant? = nil
    
    var body: some View {
        Group {
            if assistants.isEmpty {
                SidebarEmptyState()
            } else {
                List {
                    ForEach(assistants) { assistant in
                        AssistantSidebarSection(
                            assistant: assistant,
                            selectedSession: selectedSession,
                            isExpanded: expandedIDs.contains(assistant.id),
                            onToggleExpanded: { toggleExpanded(assistant) },
                            onEdit: { editingAssistant = assistant },
                            onSelectSession: selectSession,
                            onDeleteSessions: { offsets in deleteSessions(offsets, from: assistant) },
                            onAddSession: { addSession(to: assistant) }
                        )
                    }
                }
#if os(macOS)
                .listStyle(.sidebar)
#endif
            }
        }
        .navigationTitle("assistant.list.title")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .safeAreaInset(edge: .bottom) {
            AddAssistantButton {
                showNewAssistant = true
            }
        }
        .sheet(isPresented: $showNewAssistant) {
            NewAssistantView()
        }
        .sheet(item: $editingAssistant) { assistant in
            AssistantSettingsView(assistant: assistant)
        }
        .onAppear {
            // No-op: built-in assistants are no longer seeded
        }
    }

    private func toggleExpanded(_ assistant: Assistant) {
        withAnimation(.snappy) {
            if expandedIDs.contains(assistant.id) {
                expandedIDs.remove(assistant.id)
            } else {
                expandedIDs.insert(assistant.id)
            }
        }
    }

    private func selectSession(_ session: ChatSession) {
        selectedSession = session
        onSessionSelected?()
    }

    private func addSession(to assistant: Assistant) {
        withAnimation {
            let newSession = ChatSession(title: L10n.string("chat.new_title"), assistant: assistant)
            modelContext.insert(newSession)
            assistant.sessions.append(newSession)
            selectedSession = newSession
            onSessionSelected?()
        }
    }

    private func deleteSessions(_ offsets: IndexSet, from assistant: Assistant) {
        let sorted = assistant.sessions.sorted { $0.lastModified > $1.lastModified }
        for index in offsets {
            let session = sorted[index]
            let sessionId = session.id
            if selectedSession == session {
                selectedSession = nil
            }
            modelContext.delete(session)
            Task {
                await appServices.toolServiceFactory.releaseService(for: sessionId)
            }
        }
    }
}

private struct SidebarEmptyState: View {
    var body: some View {
        ContentUnavailableView(
            "assistant.empty.title",
            systemImage: "person.2",
            description: Text("assistant.empty.description")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AssistantSidebarSection: View {
    let assistant: Assistant
    let selectedSession: ChatSession?
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    let onEdit: () -> Void
    let onSelectSession: (ChatSession) -> Void
    let onDeleteSessions: (IndexSet) -> Void
    let onAddSession: () -> Void

    private var sortedSessions: [ChatSession] {
        assistant.sessions.sorted { $0.lastModified > $1.lastModified }
    }

    var body: some View {
        Section {
            AssistantHeaderRow(
                name: assistant.name,
                isExpanded: isExpanded,
                onToggleExpanded: onToggleExpanded,
                onEdit: onEdit
            )

            if isExpanded {
                ForEach(sortedSessions) { session in
                    SessionSidebarRow(
                        session: session,
                        isSelected: selectedSession?.id == session.id,
                        onSelect: { onSelectSession(session) }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                }
                .onDelete(perform: onDeleteSessions)

                NewChatSidebarRow(onAdd: onAddSession)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
        }
    }
}

private struct AssistantHeaderRow: View {
    let name: String
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onToggleExpanded) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text(name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onEdit) {
                Image(systemName: "square.and.pencil")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("assistant.edit.title"))
        }
        .padding(.vertical, 4)
    }
}

private struct SessionSidebarRow: View {
    let session: ChatSession
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(width: 3, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    Text(session.lastModified, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .padding(.leading, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct NewChatSidebarRow: View {
    let onAdd: () -> Void

    var body: some View {
        Button(action: onAdd) {
            Label("chat.new", systemImage: "plus.circle")
                .font(.subheadline)
                .foregroundStyle(.blue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 20)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

private struct AddAssistantButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label("assistant.add", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.blue)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
#if os(macOS)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
#else
            .background(.regularMaterial, in: Capsule())
#endif
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
}
