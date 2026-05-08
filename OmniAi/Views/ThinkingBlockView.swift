import SwiftUI
import Combine

struct ThinkingBlockView: View {
    let thinkingText: String
    let isStreaming: Bool
    @State private var isExpanded = false
    @State private var scrollTrigger = PassthroughSubject<Void, Never>()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { isExpanded.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.caption2)
                    Text("深度思考")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isExpanded {
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if isStreaming {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: "chevron.forward")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        Text(thinkingText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .id("thinkingBottom")
                    }
                    .frame(height: 80)
                    .onReceive(scrollTrigger.debounce(for: .seconds(0.1), scheduler: RunLoop.main)) { _ in
                        withAnimation {
                            proxy.scrollTo("thinkingBottom", anchor: .bottom)
                        }
                    }
                    .task(id: thinkingText) {
                        scrollTrigger.send()
                    }
                }
            }
        }
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear { if isStreaming { isExpanded = true } }
        .onChange(of: isStreaming) { _, new in
            if !new { isExpanded = false }
        }
    }
}
