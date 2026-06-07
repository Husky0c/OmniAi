import Foundation

struct ProviderErrorInfo: Equatable {
    let statusCode: Int
    let message: String
    let type: String?
    let code: String?
    let requestId: String?
    let retryAfter: Int?
    let rawSnippet: String
}

enum ProviderErrorParser {
    static func parse(statusCode: Int, data: Data, response: HTTPURLResponse?) -> ProviderErrorInfo {
        parse(statusCode: statusCode, body: String(data: data, encoding: .utf8) ?? "", response: response)
    }

    static func parse(statusCode: Int, body: String, response: HTTPURLResponse?) -> ProviderErrorInfo {
        let normalizedBody = stripSSEPrefixes(from: body)
        let rawSnippet = String(sanitizedBody(normalizedBody).prefix(300))
        let retryAfter = response?.value(forHTTPHeaderField: "retry-after").flatMap(Int.init)
        let requestId = firstHeaderValue(response, names: ["x-request-id", "request-id", "cf-ray"])

        if let parsed = parseJSONError(from: normalizedBody) {
            return ProviderErrorInfo(
                statusCode: statusCode,
                message: parsed.message,
                type: parsed.type,
                code: parsed.code,
                requestId: parsed.requestId ?? requestId,
                retryAfter: retryAfter,
                rawSnippet: rawSnippet
            )
        }

        let fallback = rawSnippet.isEmpty
            ? fallbackMessage(for: statusCode, retryAfter: retryAfter)
            : L10n.format("llm.http_error_format", statusCode, rawSnippet)
        return ProviderErrorInfo(
            statusCode: statusCode,
            message: fallback,
            type: nil,
            code: nil,
            requestId: requestId,
            retryAfter: retryAfter,
            rawSnippet: rawSnippet
        )
    }

    static func sanitizedBody(_ body: String) -> String {
        let withoutScriptAndStyle = body
            .replacingOccurrences(of: #"(?is)<script\b[^>]*>.*?</script>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<style\b[^>]*>.*?</style>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
        return withoutScriptAndStyle
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func stripSSEPrefixes(from body: String) -> String {
        let lines = body
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("data: ") {
                    return String(trimmed.dropFirst("data: ".count))
                }
                return trimmed
            }
            .filter { !$0.isEmpty && $0 != "[DONE]" }
        return lines.joined(separator: "\n")
    }

    private static func parseJSONError(from body: String) -> (message: String, type: String?, code: String?, requestId: String?)? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data)
        else {
            return nil
        }

        if let dict = json as? [String: Any] {
            return parseDictionaryError(dict)
        }

        if let array = json as? [[String: Any]] {
            for item in array {
                if let parsed = parseDictionaryError(item) {
                    return parsed
                }
            }
        }

        return nil
    }

    private static func parseDictionaryError(_ dict: [String: Any]) -> (message: String, type: String?, code: String?, requestId: String?)? {
        let requestId = stringValue(dict["request_id"]) ?? stringValue(dict["requestId"]) ?? stringValue(dict["id"])

        if let errorDict = dict["error"] as? [String: Any] {
            let message = stringValue(errorDict["message"])
                ?? stringValue(errorDict["error"])
                ?? stringValue(errorDict["detail"])
            if let message, !message.isEmpty {
                return (
                    message,
                    stringValue(errorDict["type"]),
                    stringValue(errorDict["code"]),
                    stringValue(errorDict["request_id"]) ?? requestId
                )
            }
        }

        if let errorString = stringValue(dict["error"]), !errorString.isEmpty {
            return (errorString, stringValue(dict["type"]), stringValue(dict["code"]), requestId)
        }

        for key in ["message", "detail", "error_message"] {
            if let message = stringValue(dict[key]), !message.isEmpty {
                return (message, stringValue(dict["type"]), stringValue(dict["code"]), requestId)
            }
        }

        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            return value
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }

    private static func firstHeaderValue(_ response: HTTPURLResponse?, names: [String]) -> String? {
        for name in names {
            if let value = response?.value(forHTTPHeaderField: name), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func fallbackMessage(for statusCode: Int, retryAfter: Int?) -> String {
        switch statusCode {
        case 401:
            return LLMServiceError.authenticationFailed.localizedDescription
        case 429:
            return LLMServiceError.rateLimitExceeded(retryAfter: retryAfter).localizedDescription
        case 400...599:
            return L10n.format("llm.http_error_format", statusCode, L10n.string("common.unknown_error"))
        default:
            return L10n.string("common.unknown_error")
        }
    }
}
