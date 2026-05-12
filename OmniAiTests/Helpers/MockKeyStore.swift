import Foundation
@testable import OmniAi

final class MockKeyStore: KeyStoreProtocol {
    private var values: [String: String] = [:]

    func apiKeyString(for channel: APIKeys) -> String? {
        values[channel.resolvedKeychainAccount]
    }

    func saveAPIKey(_ value: String, for channel: APIKeys) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            values[channel.resolvedKeychainAccount] = nil
        } else {
            values[channel.resolvedKeychainAccount] = trimmed
        }
    }

    func deleteAPIKey(for channel: APIKeys) throws {
        values[channel.resolvedKeychainAccount] = nil
    }
}
