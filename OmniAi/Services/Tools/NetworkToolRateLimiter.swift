//
//  NetworkToolRateLimiter.swift
//  OmniAi
//
//  Created by Claude on 2026-05-30.
//

import Foundation

/// Global rate limiter for network tools to prevent abuse
nonisolated final class NetworkToolRateLimiter: @unchecked Sendable {
    private let lock = NSLock()
    private var lastRequestTime: Date?
    private let minimumInterval: TimeInterval

    init(minimumInterval: TimeInterval = 1.0) {
        self.minimumInterval = minimumInterval
    }

    /// Wait if needed to respect rate limit
    func waitIfNeeded() async {
        let shouldWait: TimeInterval? = lock.withLock {
            guard let last = lastRequestTime else {
                lastRequestTime = Date()
                return nil
            }

            let elapsed = Date().timeIntervalSince(last)
            let jitter = Double.random(in: 0.1...0.3)
            let required = minimumInterval + jitter

            if elapsed < required {
                lastRequestTime = Date()
                return required - elapsed
            }

            lastRequestTime = Date()
            return nil
        }

        if let delay = shouldWait {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }
}
