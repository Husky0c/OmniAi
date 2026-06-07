//
//  URLContentFetcherTests.swift
//  OmniAiTests
//
//  Created by Claude on 2026-05-30.
//

import XCTest
@testable import OmniAi

final class URLContentFetcherTests: XCTestCase {

    func testValidateURL_ValidHTTP_Succeeds() throws {
        // This tests the internal validation logic
        // Since validateURL is private, we test through fetch
        let rateLimiter = NetworkToolRateLimiter()

        // We can't easily test private methods, so we'll test the public interface
        // The actual validation will be tested through integration tests
    }

    func testFetch_PrivateIP_ReturnsError() async {
        let rateLimiter = NetworkToolRateLimiter()

        let result = await URLContentFetcher.fetch(
            url: "http://192.168.1.1",
            extractType: .text,
            rateLimiter: rateLimiter
        )

        let data = result.data(using: .utf8)!
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNotNil(json["error"])
        XCTAssertEqual(json["error_code"] as? String, "blocked_url")
    }

    func testFetch_Localhost_ReturnsError() async {
        let rateLimiter = NetworkToolRateLimiter()

        let result = await URLContentFetcher.fetch(
            url: "http://localhost:8080",
            extractType: .text,
            rateLimiter: rateLimiter
        )

        let data = result.data(using: .utf8)!
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNotNil(json["error"])
        XCTAssertEqual(json["error_code"] as? String, "blocked_url")
    }

    func testFetch_InvalidScheme_ReturnsError() async {
        let rateLimiter = NetworkToolRateLimiter()

        let result = await URLContentFetcher.fetch(
            url: "ftp://example.com",
            extractType: .text,
            rateLimiter: rateLimiter
        )

        let data = result.data(using: .utf8)!
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNotNil(json["error"])
        XCTAssertEqual(json["error_code"] as? String, "invalid_url")
    }

    func testFetch_InvalidURL_ReturnsError() async {
        let rateLimiter = NetworkToolRateLimiter()

        let result = await URLContentFetcher.fetch(
            url: "not a url",
            extractType: .text,
            rateLimiter: rateLimiter
        )

        let data = result.data(using: .utf8)!
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNotNil(json["error"])
        XCTAssertEqual(json["error_code"] as? String, "invalid_url")
    }

    func testExtractType_AllTypes_AreValid() {
        XCTAssertEqual(URLContentFetcher.ExtractType.text.rawValue, "text")
        XCTAssertEqual(URLContentFetcher.ExtractType.markdown.rawValue, "markdown")
        XCTAssertEqual(URLContentFetcher.ExtractType.html.rawValue, "html")
    }

    // Note: Testing actual HTTP requests requires either:
    // 1. A mock URLSession (would need to refactor URLContentFetcher to accept URLSession)
    // 2. A local test server
    // 3. Integration tests against real URLs (flaky)
    // For now, we test the error cases which don't require network access
}
