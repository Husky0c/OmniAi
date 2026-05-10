import Foundation

final class ThinkTagParser {
    private enum State {
        case normal
        case insideThinking
    }

    private var state: State = .normal
    private var didYieldFirstChunk = false
    private let tagPairs: [TagPair]

    private struct TagPair {
        let open: String
        let close: String
    }

    init(tagPairs: [ResponseParserConfig.TagPair]) {
        self.tagPairs = tagPairs.map { TagPair(open: $0.open, close: $0.close) }
    }

    func feed(_ raw: String) -> [LLMStreamEvent] {
        var remaining = raw
        var events: [LLMStreamEvent] = []

        while !remaining.isEmpty {
            switch state {
            case .insideThinking:
                handleInsideThinking(&remaining, events: &events)
            case .normal:
                handleNormal(&remaining, events: &events)
            }
        }

        return events
    }

    private func handleInsideThinking(_ remaining: inout String, events: inout [LLMStreamEvent]) {
        for pair in tagPairs {
            if let endRange = remaining.range(of: pair.close) {
                let thinking = String(remaining[remaining.startIndex..<endRange.lowerBound])
                if !thinking.isEmpty {
                    events.append(.thinking(thinking))
                }
                state = .normal
                remaining = String(remaining[endRange.upperBound...])
                if !remaining.isEmpty {
                    let trimmed = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        didYieldFirstChunk = true
                        events.append(.chunk(trimmed))
                    }
                    remaining = ""
                }
                return
            }
        }
        events.append(.thinking(remaining))
        remaining = ""
    }

    private func handleNormal(_ remaining: inout String, events: inout [LLMStreamEvent]) {
        for pair in tagPairs {
            if let startRange = remaining.range(of: pair.open) {
                let before = String(remaining[remaining.startIndex..<startRange.lowerBound])
                if !before.isEmpty {
                    let trimmed = before.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        didYieldFirstChunk = true
                        events.append(.chunk(trimmed))
                    }
                }
                state = .insideThinking
                remaining = String(remaining[startRange.upperBound...])
                return
            }
        }
        if !didYieldFirstChunk {
            didYieldFirstChunk = true
            let trimmed = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                events.append(.chunk(trimmed))
            }
        } else {
            events.append(.chunk(remaining))
        }
        remaining = ""
    }
}
