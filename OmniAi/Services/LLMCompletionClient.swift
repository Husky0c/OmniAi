import Foundation
import OSLog

final class LLMCompletionClient {
    private let logger = Logger(subsystem: "com.omniai.network", category: "LLMCompletionClient")
    private let session: URLSessionProtocol

    init(session: URLSessionProtocol) {
        self.session = session
    }

    func sendMessageCompletion(
        messages: [OpenAIMessage],
        apiKey: String,
        baseURL: String,
        modelId: String,
        temperature: Double?,
        endpointType: EndpointType,
        protocolConfig: ProtocolConfig
    ) async throws -> String {
        if endpointType == .anthropic {
            return try await sendAnthropicCompletion(
                messages: messages,
                apiKey: apiKey,
                baseURL: baseURL,
                modelId: modelId,
                temperature: temperature,
                protocolConfig: protocolConfig
            )
        }

        let adapter = OpenAIEndpointAdapter()
        let urlString = "\(baseURL)/chat/completions"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let chatRequest = OpenAIChatRequest(
            model: modelId,
            messages: messages,
            stream: false,
            temperature: temperature,
            stream_options: nil
        )

        do {
            request.httpBody = try JSONEncoder().encode(chatRequest)
        } catch {
            logger.error("Request encode failed: \(error.localizedDescription)")
            throw error
        }

        if let body = request.httpBody,
           let jsonString = String(data: body, encoding: .utf8) {
            logger.debug("Completion request to: \(urlString)")
            logger.debug("Model: \(modelId)")
            if let prettyData = try? JSONSerialization.data(withJSONObject: try JSONSerialization.jsonObject(with: body), options: [.prettyPrinted, .sortedKeys]),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                logger.debug("Request body:\n\(prettyString)")
            } else {
                logger.debug("Request body: \(jsonString)")
            }
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                logger.error("Completion request failed [\(statusCode)]: \(errorResponse.error.message)")
                throw NSError(domain: "LLMService", code: statusCode, userInfo: [NSLocalizedDescriptionKey: errorResponse.error.message])
            }
            let raw = String(data: data, encoding: .utf8) ?? "Empty response"
            logger.error("Completion request failed [\(statusCode)]: \(raw)")
            throw URLError(.badServerResponse)
        }

        let result = try adapter.parseCompletionResponse(data: data)
        logger.debug("Completion request successful")
        return result
    }

    private func sendAnthropicCompletion(
        messages: [OpenAIMessage],
        apiKey: String,
        baseURL: String,
        modelId: String,
        temperature: Double?,
        protocolConfig: ProtocolConfig
    ) async throws -> String {
        let adapter = AnthropicEndpointAdapter()

        var request = try adapter.buildRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            messages: messages,
            modelId: modelId,
            temperature: temperature,
            reasoningParams: ReasoningParams(),
            tools: nil,
            protocolConfig: protocolConfig
        )

        if let bodyData = request.httpBody,
           var dict = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
            dict["stream"] = false
            request.httpBody = try JSONSerialization.data(withJSONObject: dict)
        }

        logger.debug("Anthropic completion request to: \(request.url?.absoluteString ?? "nil")")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = parsed["error"] as? [String: Any],
               let message = err["message"] as? String {
                throw NSError(domain: "LLMService", code: statusCode, userInfo: [NSLocalizedDescriptionKey: message])
            }
            throw URLError(.badServerResponse)
        }

        return try adapter.parseCompletionResponse(data: data)
    }
}
