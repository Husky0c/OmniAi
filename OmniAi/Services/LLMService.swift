import Foundation
import SwiftUI

// OpenAI API Models
struct OpenAIChatRequest: Codable {
    let model: String
    let messages: [OpenAIMessage]
    let stream: Bool
}

struct OpenAIMessage: Codable {
    let role: String
    let content: String
}

struct OpenAIStreamResponse: Codable {
    let id: String?
    let choices: [Choice]
    
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

class LLMService {
    static let shared = LLMService()
    
    @AppStorage("defaultProvider") private var defaultProvider: String = "openai"
    @AppStorage("defaultModelId") private var defaultModelId: String = "gpt-4o"
    @AppStorage("openAIApiKey") private var openAIApiKey: String = ""
    @AppStorage("customBaseURL") private var customBaseURL: String = ""
    
    func getBaseURL() -> String {
        var base = customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.isEmpty {
            if base.hasSuffix("/") {
                base.removeLast()
            }
            if base.hasSuffix("/chat/completions") {
                base = String(base.dropLast("/chat/completions".count))
            }
            return base
        }
        return "https://api.openai.com/v1"
    }
    
    func sendMessageStream(messages: [(role: String, content: String)]) -> AsyncThrowingStream<String, Error> {
        let baseURL = getBaseURL()
        let urlString = "\(baseURL)/chat/completions"
        guard let url = URL(string: urlString) else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: URLError(.badURL))
            }
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(openAIApiKey)", forHTTPHeaderField: "Authorization")
        
        let openAIMessages = messages.map { OpenAIMessage(role: $0.role, content: $0.content) }
        let chatRequest = OpenAIChatRequest(model: defaultModelId, messages: openAIMessages, stream: true)
        
        request.httpBody = try? JSONEncoder().encode(chatRequest)
        
        print("[LLMService] 🚀 发送请求至: \(urlString)")
        print("[LLMService] 📝 模型: \(defaultModelId)")
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let (result, response) = try await URLSession.shared.bytes(for: request)
                    
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
                            if let content = streamResponse.choices.first?.delta.content {
                                continuation.yield(content)
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
