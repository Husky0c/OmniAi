import Foundation

enum ChatErrorFormatter {
    static func render(_ error: ChatEngineError, existingContent: String) -> String {
        let message = UserFacingErrorFormatter.make(from: error).rendered(style: .inlineWarning)
        if existingContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return message
        }
        return "\(existingContent)\n\n\(message)"
    }
}
