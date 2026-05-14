import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum ImageProcessor {
    private static let skipCompressionThreshold: Int = 1_048_576

    static func compressImage(_ data: Data, compressionQuality: CGFloat = 0.85) -> Data? {
#if canImport(UIKit)
        if isJpeg(data), data.count < skipCompressionThreshold {
            return data
        }
        guard let image = UIImage(data: data) else { return nil }
        return image.jpegData(compressionQuality: compressionQuality)
#else
        return data
#endif
    }

    static func generateThumbnail(_ data: Data, maxPixelSize: CGFloat = 200, compressionQuality: CGFloat = 0.6) -> Data? {
#if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let scale = min(maxPixelSize / max(size.width, size.height), 1)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let thumbnail = renderer.jpegData(withCompressionQuality: compressionQuality) { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return thumbnail
#else
        return data
#endif
    }

    private static func isJpeg(_ data: Data) -> Bool {
        guard data.count >= 3 else { return false }
        let header = [data[0], data[1], data[2]]
        return header == [0xFF, 0xD8, 0xFF]
    }
}
