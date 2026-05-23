import XCTest
@testable import OmniAi

final class AvatarManagerTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AvatarManagerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        AvatarManager.avatarDirectoryProvider = { self.directory }
        AvatarManager.resetCacheForTesting()
    }

    override func tearDownWithError() throws {
        AvatarManager.remove()
        AvatarManager.avatarDirectoryProvider = {
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        }
        AvatarManager.resetCacheForTesting()
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }

    func testSaveLoadAndRemoveAvatarData() throws {
        let data = try XCTUnwrap(Self.samplePNGData)

        AvatarManager.save(data)

        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(AvatarManager.avatarURL).path))
        XCTAssertNotNil(AvatarManager.loadAsync())

        AvatarManager.remove()

        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(AvatarManager.avatarURL).path))
        XCTAssertNil(AvatarManager.loadAsync())
    }

    func testCreatesPlatformImageFromStoredData() throws {
        let data = try XCTUnwrap(Self.samplePNGData)

        XCTAssertNotNil(AvatarManager.image(from: data))
    }

    private static var samplePNGData: Data? {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")
    }
}
