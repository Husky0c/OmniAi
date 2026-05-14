import Foundation

protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
    func bytes(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, URLResponse)
}

extension URLSession: URLSessionProtocol {
    func bytes(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, URLResponse) {
        let (bytes, response) = try await self.bytes(for: request, delegate: nil)
        let stream = AsyncThrowingStream<String, Error> { continuation in
            Task {
                do {
                    for try await line in bytes.lines {
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
        return (stream, response)
    }
}