import Foundation
import UIKit

struct AvatarManager {
    static let fileName = "user_avatar.jpg"

    static var avatarURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?.appendingPathComponent(fileName)
    }

    static func save(_ data: Data) {
        guard let url = avatarURL else { return }
        try? data.write(to: url)
    }

    static func load() -> UIImage? {
        guard let url = avatarURL, let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func remove() {
        guard let url = avatarURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
