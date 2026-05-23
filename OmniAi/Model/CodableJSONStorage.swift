import Foundation
import OSLog

enum CodableJSONStorage {
    private static let logger = Logger(subsystem: "com.omniai.model", category: "CodableJSONStorage")
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func decode<T: Decodable>(
        _ type: T.Type,
        from json: String?,
        fallback: T,
        owner: String,
        field: String
    ) -> T {
        guard let json, !json.isEmpty else {
            return fallback
        }

        guard let data = json.data(using: .utf8) else {
            logger.error("Invalid UTF-8 JSON for \(owner).\(field, privacy: .public)")
            return fallback
        }

        do {
            return try decoder.decode(type, from: data)
        } catch {
            logger.error("Failed to decode \(owner).\(field, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return fallback
        }
    }

    static func encode<T: Encodable>(
        _ value: T,
        isEmpty: (T) -> Bool,
        owner: String,
        field: String
    ) -> String? {
        guard !isEmpty(value) else {
            return nil
        }

        do {
            let data = try encoder.encode(value)
            guard let json = String(data: data, encoding: .utf8) else {
                logger.error("Failed to encode \(owner).\(field, privacy: .public): encoded data is not UTF-8")
                return nil
            }
            return json
        } catch {
            logger.error("Failed to encode \(owner).\(field, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
