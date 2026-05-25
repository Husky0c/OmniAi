import SwiftUI

struct EmptyChatSelectionView: View {
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
