import XCTest
@testable import CyberpunkMonsterCrawl

/// PR 1 (`CYBERPUN-17-13`): `HighScoreStore`'s persistence-across-relaunch,
/// sorted-descending reads, and per-test isolation (AC4).
final class HighScoreStoreTests: XCTestCase {

    private func makeSummary(score: Int) -> RunSummary {
        RunSummary(
            survivedSeconds: 42,
            raccoonsDown: 3,
            level: 2,
            rabies: 1,
            damageDealt: 50,
            killBonus: 300,
            survivalBonus: 84,
            score: score
        )
    }

    /// Every test uses its own uniquely-named suite (never `.standard`,
    /// never a shared fixed suite name) so tests never leak state into one
    /// another regardless of run order, and removes the suite's persistent
    /// domain in `defer` so nothing survives the test itself.
    private func makeIsolatedDefaults() -> (defaults: UserDefaults, cleanup: () -> Void) {
        let suiteName = "com.cyberpunkmonstercrawl.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (defaults, { defaults.removePersistentDomain(forName: suiteName) })
    }

    func test_freshStore_startsEmpty() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }

        let store = HighScoreStore(defaults: defaults)
        XCTAssertTrue(store.sortedEntries().isEmpty)
    }

    func test_recordRun_persistsAcrossSimulatedRelaunch() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }

        let firstLaunchInstance = HighScoreStore(defaults: defaults)
        firstLaunchInstance.recordRun(makeSummary(score: 500))

        // Simulate an app relaunch: a brand-new `HighScoreStore` instance
        // constructed over the SAME `UserDefaults` suite must read back
        // what the previous instance wrote.
        let relaunchedInstance = HighScoreStore(defaults: defaults)
        let entries = relaunchedInstance.sortedEntries()

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.score, 500)
        XCTAssertEqual(entries.first?.raccoonsDown, 3)
        XCTAssertEqual(entries.first?.level, 2)
        XCTAssertEqual(entries.first?.rabies, 1)
        XCTAssertEqual(entries.first?.damageDealt, 50)
        XCTAssertEqual(entries.first?.survivedSeconds, 42)
    }

    func test_sortedEntries_ordersDescendingByScore() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }

        let store = HighScoreStore(defaults: defaults)
        store.recordRun(makeSummary(score: 100))
        store.recordRun(makeSummary(score: 900))
        store.recordRun(makeSummary(score: 450))

        XCTAssertEqual(store.sortedEntries().map(\.score), [900, 450, 100])
    }

    func test_recordRun_multipleEntries_eachHasAStableUniqueID() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }

        let store = HighScoreStore(defaults: defaults)
        store.recordRun(makeSummary(score: 10))
        store.recordRun(makeSummary(score: 20))

        let ids = store.sortedEntries().map(\.id)
        XCTAssertEqual(Set(ids).count, 2, "each recorded run must get its own identity")
    }

    func test_differentSuites_doNotLeakStateBetweenStores() {
        let (defaultsA, cleanupA) = makeIsolatedDefaults()
        let (defaultsB, cleanupB) = makeIsolatedDefaults()
        defer {
            cleanupA()
            cleanupB()
        }

        let storeA = HighScoreStore(defaults: defaultsA)
        storeA.recordRun(makeSummary(score: 777))

        let storeB = HighScoreStore(defaults: defaultsB)
        XCTAssertTrue(storeB.sortedEntries().isEmpty, "a fresh suite must start empty regardless of other stores' state")
    }
}
