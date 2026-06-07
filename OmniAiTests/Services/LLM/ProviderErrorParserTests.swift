import XCTest
@testable import OmniAi

final class ProviderErrorParserTests: XCTestCase {
    func testParsesOpenAIErrorEnvelope() {
        let data = #"{"error":{"message":"Invalid API key","type":"auth_error","code":"invalid_api_key"}}"#
            .data(using: .utf8)!

        let info = ProviderErrorParser.parse(statusCode: 401, data: data, response: nil)

        XCTAssertEqual(info.statusCode, 401)
        XCTAssertEqual(info.message, "Invalid API key")
        XCTAssertEqual(info.type, "auth_error")
        XCTAssertEqual(info.code, "invalid_api_key")
    }

    func testParsesAnthropicErrorEnvelope() {
        let data = #"{"type":"error","error":{"type":"invalid_request_error","message":"bad request"}}"#
            .data(using: .utf8)!

        let info = ProviderErrorParser.parse(statusCode: 400, data: data, response: nil)

        XCTAssertEqual(info.message, "bad request")
        XCTAssertEqual(info.type, "invalid_request_error")
    }

    func testParsesCommonProxyErrorShapes() {
        let message = ProviderErrorParser.parse(
            statusCode: 502,
            data: #"{"message":"upstream unavailable"}"#.data(using: .utf8)!,
            response: nil
        )
        let detail = ProviderErrorParser.parse(
            statusCode: 400,
            data: #"{"detail":"invalid payload"}"#.data(using: .utf8)!,
            response: nil
        )
        let errorString = ProviderErrorParser.parse(
            statusCode: 500,
            data: #"{"error":"backend exploded"}"#.data(using: .utf8)!,
            response: nil
        )

        XCTAssertEqual(message.message, "upstream unavailable")
        XCTAssertEqual(detail.message, "invalid payload")
        XCTAssertEqual(errorString.message, "backend exploded")
    }

    func testStripsSSEDataPrefixBeforeParsing() {
        let body = #"data: {"error":{"message":"stream denied","type":"auth_error"}}"#

        let info = ProviderErrorParser.parse(statusCode: 403, body: body, response: nil)

        XCTAssertEqual(info.message, "stream denied")
        XCTAssertEqual(info.type, "auth_error")
    }

    func testPlainTextAndHTMLFallbackAreSanitized() {
        let html = """
        <html>
        <head><style>body { color: red; }</style></head>
        <body><script>alert(1)</script><h1>Forbidden</h1><p>IP blocked</p></body>
        </html>
        """

        let info = ProviderErrorParser.parse(statusCode: 403, body: html, response: nil)

        XCTAssertTrue(info.message.contains("403"))
        XCTAssertTrue(info.message.contains("Forbidden"))
        XCTAssertTrue(info.message.contains("IP blocked"))
        XCTAssertFalse(info.message.contains("<html"))
        XCTAssertFalse(info.message.contains("color: red"))
    }

    func testEmptyRateLimitUsesRetryAfterHeader() {
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["retry-after": "7"]
        )

        let info = ProviderErrorParser.parse(statusCode: 429, data: Data(), response: response)

        XCTAssertEqual(info.retryAfter, 7)
        XCTAssertEqual(info.message, "API 速率限制，请在 7 秒后重试")
    }
}
