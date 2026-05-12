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
        protocolConfig: ProtocolConfig,
        requestContext: LLMRequestContext
    ) async throws -> String {
        if endpointType == .anthropic {
            return try await sendAnthropicCompletion(
                messages: messages,
                apiKey: apiKey,
                baseURL: baseURL,
                modelId: modelId,
                temperature: temperature,
                protocolConfig: protocolConfig,
                requestContext: requestContext
            )
        }

        let adapter = OpenAIEndpointAdapter()
        let urlString = "\(baseURL)/chat/completions"
        guard let url = URL(string: urlString) else {
            throw AppError.requestBuildFailure(context: requestContext, underlying: LLMServiceError.invalidURL(urlString))
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
            throw AppError.requestBuildFailure(context: requestContext, underlying: error)
        }

        if let body = request.httpBody,
           let jsonString = String(data: body, encoding: .utf8) {
            logger.debug("Completion request to: \(urlString)")
            logger.debug("\(requestContext.logDescription)")
            if let prettyData = try? JSONSerialization.data(withJSONObject: try JSONSerialization.jsonObject(with: body), options: [.prettyPrinted, .sortedKeys]),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                logger.debug("Request body:\n\(prettyString)")
            } else {
                logger.debug("Request body: \(jsonString)")
            }
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AppError.transportFailure(context: requestContext, underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                let appError = AppError.serverFailure(statusCode: statusCode, message: errorResponse.error.message, context: requestContext)
                logger.error("\(appError.logDescription)")
                throw appError
            }
            let raw = String(data: data, encoding: .utf8) ?? "Empty response"
            let appError = AppError.serverFailure(statusCode: statusCode, message: raw, context: requestContext)
            logger.error("\(appError.logDescription)")
            throw appError
        }

        let result: String
        do {
            result = try adapter.parseCompletionResponse(data: data)
        } catch {
            throw AppError.invalidResponse(context: requestContext, message: error.localizedDescription)
        }
        logger.debug("Completion request successful")
        return result
    }

    private func sendAnthropicCompletion(
        messages: [OpenAIMessage],
        apiKey: String,
        baseURL: String,
        modelId: String,
        temperature: Double?,
        protocolConfig: ProtocolConfig,
        requestContext: LLMRequestContext
    ) async throws -> String {
        let adapter = AnthropicEndpointAdapter()

        var request: URLRequest
        do {
            request = try adapter.buildRequest(
                baseURL: baseURL,
                apiKey: apiKey,
                messages: messages,
                modelId: modelId,
                temperature: temperature,
                reasoningParams: ReasoningParams(),
                tools: nil,
                protocolConfig: protocolConfig
            )
        } catch {
            throw AppError.requestBuildFailure(context: requestContext, underlying: error)
        }

        if let bodyData = request.httpBody,
           var dict = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
            dict["stream"] = false
            request.httpBody = try JSONSerialization.data(withJSONObject: dict)
        }

        logger.debug("Anthropic completion request to: \(request.url?.absoluteString ?? "nil"), \(requestContext.logDescription)")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AppError.transportFailure(context: requestContext, underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = parsed["error"] as? [String: Any],
               let message = err["message"] as? String {
                throw AppError.serverFailure(statusCode: statusCode, message: message, context: requestContext)
            }
            throw AppError.serverFailure(statusCode: statusCode, message: "无效响应", context: requestContext)
        }

        do {
            return try adapter.parseCompletionResponse(data: data)
        } catch {
            throw AppError.invalidResponse(context: requestContext, message: error.localizedDescription)
        }
    }
}
