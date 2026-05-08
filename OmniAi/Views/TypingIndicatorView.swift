import SwiftUI
import Combine

struct TypingIndicatorView: View {
    @State private var startTime = Date()
    @State private var elapsedTime: TimeInterval = 0

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 8, height: 8)
                    .opacity(Int(elapsedTime / 0.35) % 3 == index ? 1 : 0.25)
                    .scaleEffect(Int(elapsedTime / 0.35) % 3 == index ? 1 : 0.7)
                    .animation(.easeInOut(duration: 0.2), value: elapsedTime)
            }

            Text(String(format: "%.1f S", elapsedTime))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            elapsedTime = Date().timeIntervalSince(startTime)
        }
    }
}
