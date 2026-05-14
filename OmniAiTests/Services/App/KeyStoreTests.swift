import XCTest
@testable import OmniAi

final class KeyStoreTests: XCTestCase {
    func testMockKeyStoreSavesAndReadsByKeychainAccount() throws {
        let channel = APIKeys(name: "Test")
        let store = MockKeyStore()

        try store.saveAPIKey(" sk-test ", for: channel)

        XCTAssertEqual(store.apiKeyString(for: channel), "sk-test")
    }

    func testMockKeyStoreDeletesStoredKey() throws {
        let channel = APIKeys(name: "Test")
        let store = MockKeyStore()

        try store.saveAPIKey("sk-test", for: channel)
        try store.deleteAPIKey(for: channel)

        XCTAssertNil(store.apiKeyString(for: channel))
    }

    func testEmptyKeyClearsStoredKey() throws {
        let channel = APIKeys(name: "Test")
        let store = MockKeyStore()

        try store.saveAPIKey("sk-test", for: channel)
        try store.saveAPIKey(" ", for: channel)

        XCTAssertNil(store.apiKeyString(for: channel))
    }
}
