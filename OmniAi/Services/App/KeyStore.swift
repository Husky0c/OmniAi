import Foundation
import Security

enum KeyStoreError: LocalizedError {
    case encodingFailed
    case keychainFailure(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return L10n.string("keystore.encoding_failed")
        case .keychainFailure(let status):
            return L10n.format("keystore.keychain_failure_format", status)
        }
    }
}

protocol KeyStoreProtocol {
    func apiKeyString(for channel: APIKeys) -> String?
    func saveAPIKey(_ value: String, for channel: APIKeys) throws
    func deleteAPIKey(for channel: APIKeys) throws
}

final class KeychainKeyStore: KeyStoreProtocol {
    private let service: String

    init(service: String = Bundle.main.bundleIdentifier.map { "\($0).apiKeys" } ?? "win.husky0c.OmniAi.apiKeys") {
        self.service = service
    }

    func apiKeyString(for channel: APIKeys) -> String? {
        try? readAPIKey(for: channel)
    }

    func saveAPIKey(_ value: String, for channel: APIKeys) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try deleteAPIKey(for: channel)
            return
        }

        guard let data = trimmed.data(using: .utf8) else {
            throw KeyStoreError.encodingFailed
        }

        let query = baseQuery(for: channel)
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw KeyStoreError.keychainFailure(status: updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeyStoreError.keychainFailure(status: addStatus)
        }
    }

    func deleteAPIKey(for channel: APIKeys) throws {
        let status = SecItemDelete(baseQuery(for: channel) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeyStoreError.keychainFailure(status: status)
        }
    }

    private func readAPIKey(for channel: APIKeys) throws -> String? {
        var query = baseQuery(for: channel)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeyStoreError.keychainFailure(status: status)
        }
        guard let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func baseQuery(for channel: APIKeys) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: channel.resolvedKeychainAccount
        ]
    }
}
