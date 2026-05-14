import XCTest
@testable import OmniAi

@MainActor
final class ToolSessionStoreTests: XCTestCase {
    override func tearDown() async throws {
        await ToolSessionStore.shared.resetAll()
        try await super.tearDown()
    }
    func testReturnsSameServiceForSameSessionId() async {
        let store = ToolSessionStore.shared
        let sessionId = UUID()
        await store.releaseService(for: sessionId)

        let first = store.toolService(for: sessionId)
        let second = store.toolService(for: sessionId)

        XCTAssertTrue(first === second)
        await store.releaseService(for: sessionId)
    }

    func testReleaseServiceRemovesStoredService() async {
        let store = ToolSessionStore.shared
        let sessionId = UUID()
        await store.releaseService(for: sessionId)

        _ = store.toolService(for: sessionId)
        XCTAssertTrue(store.hasService(for: sessionId))

        await store.releaseService(for: sessionId)

        XCTAssertFalse(store.hasService(for: sessionId))
    }
}
