import Foundation
#if canImport(UIKit)
import UIKit
#endif

struct AvatarManager {
    static let fileName = "user_avatar.jpg"
#if canImport(UIKit)
    private static var _cachedImage: UIImage?
    private static var _hasLoadedCache = false
#endif

    static var avatarURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?.appendingPathComponent(fileName)
    }

    static func save(_ data: Data) {
        guard let url = avatarURL else { return }
        try? data.write(to: url)
#if canImport(UIKit)
        _cachedImage = UIImage(data: data)
#endif
    }

#if canImport(UIKit)
    static func loadAsync() -> UIImage? {
        if _hasLoadedCache {
            return _cachedImage
        }
        _hasLoadedCache = true
        guard let url = avatarURL, let data = try? Data(contentsOf: url) else { return nil }
        _cachedImage = UIImage(data: data)
        return _cachedImage
    }
#endif

    static func remove() {
        guard let url = avatarURL else { return }
        try? FileManager.default.removeItem(at: url)
#if canImport(UIKit)
        _cachedImage = nil
#endif
    }
}
