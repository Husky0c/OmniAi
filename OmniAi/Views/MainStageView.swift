import SwiftUI
import SwiftData

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
#if os(iOS)
                    .toolbar {
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
                    }
#endif
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
