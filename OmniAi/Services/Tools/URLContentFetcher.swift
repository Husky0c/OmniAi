//
//  URLContentFetcher.swift
//  OmniAi
//
//  Created by Claude on 2026-05-30.
//

import Foundation
import SwiftSoup

/// URL content fetcher with SSRF protection and content extraction
enum URLContentFetcher {

    enum ExtractType: String {
        case text
        case markdown
        case html
    }

    enum FetchError: Error, LocalizedError {
        case invalidURL
        case blockedURL
        case invalidResponse
        case contentTooLarge
        case extractionFailed
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid URL format"
            case .blockedURL: return "Blocked URL (private IP or invalid scheme)"
            case .invalidResponse: return "Invalid HTTP response"
            case .contentTooLarge: return "Content too large (>10MB)"
            case .extractionFailed: return "Failed to extract content"
            case .networkError(let error): return "Network error: \(error.localizedDescription)"
            }
        }

        var errorCode: String {
            switch self {
            case .invalidURL: return "invalid_url"
            case .blockedURL: return "blocked_url"
            case .invalidResponse: return "invalid_response"
            case .contentTooLarge: return "content_too_large"
            case .extractionFailed: return "extraction_failed"
            case .networkError: return "network_error"
            }
        }
    }

    /// Fetch and extract content from a URL
    static func fetch(
        url: String,
        extractType: ExtractType,
        rateLimiter: NetworkToolRateLimiter,
        session: URLSession = .shared
    ) async -> String {
        await rateLimiter.waitIfNeeded()

        do {
            let validURL = try validateURL(url)
            var request = URLRequest(url: validURL, timeoutInterval: 30)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw FetchError.invalidResponse
            }

            // Check content size
            if data.count > 10_485_760 {
                throw FetchError.contentTooLarge
            }

            // Parse HTML
            let html = String(data: data, encoding: .utf8) ?? ""
            let extracted = try extractContent(html: html, url: validURL, extractType: extractType)

            return encodeResult(
                url: url,
                title: extracted.title,
                content: extracted.content,
                statusCode: httpResponse.statusCode
            )

        } catch let error as FetchError {
            return encodeError(error: error.localizedDescription, code: error.errorCode, url: url)
        } catch {
            return encodeError(error: error.localizedDescription, code: "network_error", url: url)
        }
    }

    /// Validate URL and check for SSRF attacks
    private static func validateURL(_ urlString: String) throws -> URL {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host else {
            throw FetchError.invalidURL
        }

        // Block dangerous hosts
        let blockedPatterns = [
            "localhost", "127.0.0.1", "0.0.0.0", "::1",
            "169.254.", "fe80:", "fc00:", "fd00:"
        ]

        let hostLower = host.lowercased()
        for pattern in blockedPatterns {
            if hostLower.contains(pattern) {
                throw FetchError.blockedURL
            }
        }

        // Block private IP ranges
        if host.starts(with: "10.") || host.starts(with: "192.168.") {
            throw FetchError.blockedURL
        }

        // Block 172.16.0.0/12
        if host.starts(with: "172.") {
            if let second = host.split(separator: ".").dropFirst().first,
               let num = Int(second), (16...31).contains(num) {
                throw FetchError.blockedURL
            }
        }

        return url
    }

    /// Extract content from HTML
    private static func extractContent(html: String, url: URL, extractType: ExtractType) throws -> (title: String, content: String) {
        let doc = try SwiftSoup.parse(html)

        // Extract title
        let title = (try? doc.select("title").first()?.text()) ?? url.host ?? "Untitled"

        // Remove unwanted tags
        _ = try? doc.select("script, style, nav, footer, aside, header, iframe, noscript").remove()

        // Try to extract main content
        var contentElement: Element?

        // Priority: main > article > .content > body
        if let main = try? doc.select("main").first() {
            contentElement = main
        } else if let article = try? doc.select("article").first() {
            contentElement = article
        } else if let content = try? doc.select("[class*=content], [id*=content]").first() {
            contentElement = content
        } else {
            contentElement = try? doc.select("body").first()
        }

        guard let element = contentElement else {
            throw FetchError.extractionFailed
        }

        // Extract based on type
        let content: String
        switch extractType {
        case .text:
            content = try element.text()
        case .markdown:
            content = try convertToMarkdown(element: element)
        case .html:
            content = try element.html()
        }

        return (title, content)
    }

    /// Simple markdown conversion (basic implementation)
    private static func convertToMarkdown(element: Element) throws -> String {
        var markdown = ""

        // Process headings
        for heading in try element.select("h1, h2, h3, h4, h5, h6") {
            let level = Int(heading.tagName().dropFirst()) ?? 1
            let prefix = String(repeating: "#", count: level)
            markdown += "\(prefix) \(try heading.text())\n\n"
        }

        // Process paragraphs
        for p in try element.select("p") {
            markdown += "\(try p.text())\n\n"
        }

        // Process lists
        for ul in try element.select("ul") {
            for li in try ul.select("li") {
                markdown += "- \(try li.text())\n"
            }
            markdown += "\n"
        }

        for ol in try element.select("ol") {
            for (index, li) in (try ol.select("li")).enumerated() {
                markdown += "\(index + 1). \(try li.text())\n"
            }
            markdown += "\n"
        }

        // Fallback to plain text if no structured content
        if markdown.isEmpty {
            markdown = try element.text()
        }

        return markdown
    }

    /// Encode successful result as JSON
    private static func encodeResult(url: String, title: String, content: String, statusCode: Int) -> String {
        let resultDict: [String: Any] = [
            "url": url,
            "title": title,
            "content": content,
            "status_code": statusCode
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: resultDict),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return #"{"error": "Failed to encode result", "error_code": "encoding_failed"}"#
        }

        return jsonString
    }

    /// Encode error as JSON
    private static func encodeError(error: String, code: String, url: String) -> String {
        let errorDict: [String: Any] = [
            "error": error,
            "error_code": code,
            "url": url
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: errorDict),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return #"{"error": "Failed to encode error", "error_code": "encoding_failed"}"#
        }

        return jsonString
    }
}

