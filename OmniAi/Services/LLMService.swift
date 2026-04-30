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

class LLMService {
    static let shared = LLMService()
    
    @AppStorage("defaultProvider") private var defaultProvider: String = "openai"
    @AppStorage("defaultModelId") private var defaultModelId: String = "gpt-4o"
    @AppStorage("openAIApiKey") private var openAIApiKey: String = ""
    @AppStorage("customBaseURL") private var customBaseURL: String = ""
    
    func getBaseURL() -> String {
        if !customBaseURL.isEmpty {
            return customBaseURL
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
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let (result, response) = try await URLSession.shared.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw URLError(.badServerResponse)
                    }
                    
                    guard httpResponse.statusCode == 200 else {
                        // try to read some error body
                        throw NSError(domain: "LLMService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP Error: \(httpResponse.statusCode)"])
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
