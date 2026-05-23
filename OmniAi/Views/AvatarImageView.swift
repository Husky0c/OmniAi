import SwiftUI

struct AvatarImageView: View {
    let image: AvatarPlatformImage?
    let systemImageName: String
    let tint: Color

    init(image: AvatarPlatformImage?, systemImageName: String = "person.crop.circle.fill", tint: Color = .blue) {
        self.image = image
        self.systemImageName = systemImageName
        self.tint = tint
    }

    var body: some View {
        Group {
            if let image {
#if canImport(UIKit)
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
#elseif canImport(AppKit)
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
#endif
            } else {
                Image(systemName: systemImageName)
                    .resizable()
                    .foregroundStyle(tint)
            }
        }
    }
}
