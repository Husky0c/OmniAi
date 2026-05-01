import Foundation
import SwiftUI

enum LLMStreamEvent {
    case chunk(String)
    case thinking(String)
    case usage(promptTokens: Int, completionTokens: Int, totalTokens: Int)
}

struct OpenAIChatRequest: Codable {
    let model: String
    let messages: [OpenAIMessage]
    let stream: Bool
    let temperature: Double?
    let stream_options: StreamOptions?
    
    struct StreamOptions: Codable {
        let include_usage: Bool
    }
}

struct OpenAIMessage: Codable {
    let role: String
    let content: String
}

struct OpenAIStreamResponse: Codable {
    let id: String?
    let choices: [Choice]?
    let usage: Usage?
    
    struct Choice: Codable {
        let delta: Delta
        let finishReason: String?
        
        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }
    
    struct Delta: Codable {
        let content: String?
        let role: String?
        let reasoning_content: String?
        let thinking: String?
    }
    
    struct Usage: Codable {
        let promptTokens: Int?
        let completionTokens: Int?
        let totalTokens: Int?
        
        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

struct OpenAIErrorResponse: Codable {
    let error: ErrorDetail
    
    struct ErrorDetail: Codable {
        let message: String
        let type: String?
        let code: String?
    }
}

struct OpenAIModelListResponse: Codable {
    let data: [OpenAIModelItem]
}

struct OpenAIModelItem: Codable {
    let id: String
}

class LLMService {
    static let shared = LLMService()
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 3600
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()
    
    func getBaseURL(customURL: String?) -> String {
        var base = (customURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty {
            return "https://api.openai.com/v1"
        }
        while base.hasSuffix("/") {
            base.removeLast()
        }
        if base.hasSuffix("/chat/completions") {
            base = String(base.dropLast("/chat/completions".count))
            while base.hasSuffix("/") {
                base.removeLast()
            }
        }
        if !base.hasSuffix("/v1") {
            base.append("/v1")
        }
        return base
    }
    
    func fetchAvailableModels(apiKey: String, baseURL: String?) async throws -> [String] {
        let urlString = "\(getBaseURL(customURL: baseURL))/models"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        print("[LLMService] 🚀 尝试获取模型列表: \(urlString)")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                throw NSError(domain: "LLMService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorResponse.error.message])
            } else {
                let raw = String(data: data, encoding: .utf8) ?? "无法读取响应体"
                throw NSError(domain: "LLMService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: raw])
            }
        }
        
        do {
            let listResponse = try JSONDecoder().decode(OpenAIModelListResponse.self, from: data)
            let models = listResponse.data.map { $0.id }.sorted()
            print("[LLMService] ✅ 成功获取 \(models.count) 个模型")
            return models
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "无法解析响应体"
            print("[LLMService] ❌ 模型列表解析失败，原始返回: \(raw.prefix(500))")
            throw NSError(domain: "LLMService", code: 0, userInfo: [NSLocalizedDescriptionKey: "模型列表格式异常: \(raw.prefix(200))"])
        }
    }
    
    func sendMessageStream(messages: [(role: String, content: String)], apiKey: String, baseURL: String?, modelId: String, temperature: Double? = nil) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        let urlString = "\(getBaseURL(customURL: baseURL))/chat/completions"
        guard let url = URL(string: urlString) else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: URLError(.badURL))
            }
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let openAIMessages = messages.map { OpenAIMessage(role: $0.role, content: $0.content) }
        let chatRequest = OpenAIChatRequest(
            model: modelId,
            messages: openAIMessages,
            stream: true,
            temperature: temperature,
            stream_options: OpenAIChatRequest.StreamOptions(include_usage: true)
        )
        
        request.httpBody = try? JSONEncoder().encode(chatRequest)
        
        print("[LLMService] 🚀 发送请求至: \(urlString)")
        print("[LLMService] 📝 模型: \(modelId)")
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let (result, response) = try await session.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw URLError(.badServerResponse)
                    }
                    
                    print("[LLMService] 📡 收到响应状态码: \(httpResponse.statusCode)")
                    
                    guard httpResponse.statusCode == 200 else {
                        var errorBody = ""
                        for try await line in result.lines {
                            errorBody += line + "\n"
                        }
                        
                        if let data = errorBody.data(using: .utf8),
                           let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                            throw NSError(domain: "LLMService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorResponse.error.message])
                        } else {
                            let fallbackMessage = errorBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "服务器返回 HTTP 错误码: \(httpResponse.statusCode) (503通常代表中转服务器宕机或配置错误)" : errorBody
                            throw NSError(domain: "LLMService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: fallbackMessage])
                        }
                    }
                    
                    var hasReceivedContent = false
                    
                    for try await line in result.lines {
                        let prefix = "data: "
                        guard line.hasPrefix(prefix) else { continue }
                        let jsonStr = String(line.dropFirst(prefix.count))
                        
                        if jsonStr.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
                            continuation.finish()
                            return
                        }
                        
                        if let data = jsonStr.data(using: .utf8),
                           let streamResponse = try? JSONDecoder().decode(OpenAIStreamResponse.self, from: data) {
                            if let usage = streamResponse.usage,
                               let prompt = usage.promptTokens,
                               let completion = usage.completionTokens,
                               let total = usage.totalTokens {
                                continuation.yield(.usage(promptTokens: prompt, completionTokens: completion, totalTokens: total))
                            } else if let thinking = streamResponse.choices?.first?.delta.reasoning_content
                                       ?? streamResponse.choices?.first?.delta.thinking {
                                if !thinking.isEmpty {
                                    continuation.yield(.thinking(thinking))
                                }
                            } else if let content = streamResponse.choices?.first?.delta.content {
                                if !hasReceivedContent {
                                    hasReceivedContent = true
                                    let trimmed = content.trimmingCharacters(in: CharacterSet.newlines.union(.whitespaces))
                                    if !trimmed.isEmpty {
                                        continuation.yield(.chunk(trimmed))
                                    }
                                } else {
                                    continuation.yield(.chunk(content))
                                }
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
