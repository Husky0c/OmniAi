import Foundation
#if canImport(UIKit)
import UIKit
typealias AvatarPlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias AvatarPlatformImage = NSImage
#endif

struct AvatarManager {
    static let fileName = "user_avatar.jpg"
    static var avatarDirectoryProvider: () -> URL? = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    private static var _cachedImage: AvatarPlatformImage?
    private static var _hasLoadedCache = false

    static var avatarURL: URL? {
        avatarDirectoryProvider()?.appendingPathComponent(fileName)
    }

    static func save(_ data: Data) {
        guard let url = avatarURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url)
        _cachedImage = image(from: data)
        _hasLoadedCache = true
    }

    static func loadAsync() -> AvatarPlatformImage? {
        if _hasLoadedCache {
            return _cachedImage
        }
        _hasLoadedCache = true
        guard let url = avatarURL, let data = try? Data(contentsOf: url) else { return nil }
        _cachedImage = image(from: data)
        return _cachedImage
    }

    static func remove() {
        guard let url = avatarURL else { return }
        try? FileManager.default.removeItem(at: url)
        _cachedImage = nil
        _hasLoadedCache = false
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

    static func resetCacheForTesting() {
        _cachedImage = nil
        _hasLoadedCache = false
    }
}
