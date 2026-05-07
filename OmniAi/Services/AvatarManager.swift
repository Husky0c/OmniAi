import Foundation
import UIKit

struct AvatarManager {
    static let fileName = "user_avatar.jpg"
    private static var _cachedImage: UIImage?
    private static var _hasLoadedCache = false

    static var avatarURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?.appendingPathComponent(fileName)
    }

    static func save(_ data: Data) {
        guard let url = avatarURL else { return }
        try? data.write(to: url)
        _cachedImage = UIImage(data: data)
    }

    static func loadAsync() -> UIImage? {
        if _hasLoadedCache {
            return _cachedImage
        }
        _hasLoadedCache = true
        guard let url = avatarURL, let data = try? Data(contentsOf: url) else { return nil }
        _cachedImage = UIImage(data: data)
        return _cachedImage
    }

    static func remove() {
        guard let url = avatarURL else { return }
        try? FileManager.default.removeItem(at: url)
        _cachedImage = nil
    }
}
