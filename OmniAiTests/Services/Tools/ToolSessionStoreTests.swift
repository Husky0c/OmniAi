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

    func testReleaseServicesExcludingKeepsActiveSessions() async {
        let store = ToolSessionStore.shared
        let activeId = UUID()
        let staleId = UUID()
        await store.releaseService(for: activeId)
        await store.releaseService(for: staleId)

        _ = store.toolService(for: activeId)
        _ = store.toolService(for: staleId)

        await store.releaseServices(excluding: [activeId])

        XCTAssertTrue(store.hasService(for: activeId))
        XCTAssertFalse(store.hasService(for: staleId))
    }

    func testReleaseServicesNotInModelContextKeepsPersistedSessions() async {
        let store = ToolSessionStore.shared
        let container = TestModelContainer.newInMemoryContainer()
        let context = container.mainContext
        let persistedSession = ChatSession(title: "Persisted")
        let staleId = UUID()
        context.insert(persistedSession)

        _ = store.toolService(for: persistedSession.id)
        _ = store.toolService(for: staleId)

        await store.releaseServicesNotInModelContext(context)

        XCTAssertTrue(store.hasService(for: persistedSession.id))
        XCTAssertFalse(store.hasService(for: staleId))
    }
}
