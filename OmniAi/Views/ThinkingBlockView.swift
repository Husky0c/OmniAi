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
                    Text("thinking.title")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isStreaming {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
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
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.95, anchor: .top).combined(with: .opacity),
                    removal: .scale(scale: 0.95, anchor: .top).combined(with: .opacity)
                ))
            }
        }
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isExpanded)
        .onAppear { if isStreaming { isExpanded = true } }
        .onChange(of: isStreaming) { _, new in
            if !new { isExpanded = false }
        }
    }
}
