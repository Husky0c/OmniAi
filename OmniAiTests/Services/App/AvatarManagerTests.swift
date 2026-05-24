import XCTest
@testable import OmniAi

@MainActor
final class AvatarManagerTests: XCTestCase {
    private var directory: URL!
    private var avatarManager: AvatarManager!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AvatarManagerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        AvatarManager.avatarDirectoryProvider = { self.directory }
        avatarManager = AvatarManager()
    }

    override func tearDownWithError() throws {
        avatarManager.remove()
        AvatarManager.avatarDirectoryProvider = {
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        }
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        avatarManager = nil
    }

    func testSaveLoadAndRemoveAvatarData() throws {
        let data = try XCTUnwrap(Self.samplePNGData)

        avatarManager.save(data)

        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(AvatarManager.avatarURL).path))
        XCTAssertNotNil(avatarManager.cachedImage)

        avatarManager.remove()

        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(AvatarManager.avatarURL).path))
        XCTAssertNil(avatarManager.cachedImage)
    }

    func testCreatesPlatformImageFromStoredData() throws {
        let data = try XCTUnwrap(Self.samplePNGData)

        XCTAssertNotNil(AvatarManager.image(from: data))
    }

    private static var samplePNGData: Data? {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")
    }
}
