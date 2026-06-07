import Foundation
import Observation
import SwiftUI
#if canImport(UIKit)
import UIKit
typealias AvatarPlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias AvatarPlatformImage = NSImage
#endif

@MainActor
@Observable final class AvatarManager {
    static let fileName = "user_avatar.jpg"
    static var avatarDirectoryProvider: () -> URL? = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    private(set) var cachedImage: AvatarPlatformImage?
    private var hasLoadedCache = false

    static var avatarURL: URL? {
        avatarDirectoryProvider()?.appendingPathComponent(fileName)
    }

    nonisolated deinit {}

    func save(_ data: Data) {
        guard let url = Self.avatarURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url)
        cachedImage = Self.image(from: data)
        hasLoadedCache = true
    }

    func loadAsync() -> AvatarPlatformImage? {
        if hasLoadedCache {
            return cachedImage
        }
        hasLoadedCache = true
        guard let url = Self.avatarURL, let data = try? Data(contentsOf: url) else { return nil }
        cachedImage = Self.image(from: data)
        return cachedImage
    }

    func remove() {
        guard let url = Self.avatarURL else { return }
        try? FileManager.default.removeItem(at: url)
        cachedImage = nil
        hasLoadedCache = false
    }

    static func image(from data: Data) -> AvatarPlatformImage? {
#if canImport(UIKit)
        UIImage(data: data)
#elseif canImport(AppKit)
        NSImage(data: data)
#endif
    }

    static func data(from image: AvatarPlatformImage) -> Data? {
#if canImport(UIKit)
        image.jpegData(compressionQuality: 0.92)
#elseif canImport(AppKit)
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
#endif
    }

    func resetCacheForTesting() {
        cachedImage = nil
        hasLoadedCache = false
    }
}

// MARK: - Environment Key
private struct AvatarManagerKey: EnvironmentKey {
    static let defaultValue = AvatarManager()
}

extension EnvironmentValues {
    var avatarManager: AvatarManager {
        get { self[AvatarManagerKey.self] }
        set { self[AvatarManagerKey.self] = newValue }
    }
}
