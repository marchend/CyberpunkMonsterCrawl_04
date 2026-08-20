import XCTest
@testable import CyberpunkMonsterCrawl

/// PR 1 (`CYBERPUN-17-13`): `HighScoreStore`'s persistence-across-relaunch,
/// deterministically-ranked reads, bounded table, schema tolerance, loud
/// failure modes, and per-test isolation (AC4).
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

    func test_freshStore_startsEmpty() throws {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }

        let store = HighScoreStore(defaults: defaults)
        XCTAssertTrue(try store.sortedEntries().isEmpty)
    }

    func test_recordRun_persistsAcrossSimulatedRelaunch() throws {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }

        let firstLaunchInstance = HighScoreStore(defaults: defaults)
        try firstLaunchInstance.recordRun(makeSummary(score: 500))

        // Simulate an app relaunch: a brand-new `HighScoreStore` instance
        // constructed over the SAME `UserDefaults` suite must read back
        // what the previous instance wrote.
        let relaunchedInstance = HighScoreStore(defaults: defaults)
        let entries = try relaunchedInstance.sortedEntries()

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.score, 500)
        XCTAssertEqual(entries.first?.raccoonsDown, 3)
        XCTAssertEqual(entries.first?.level, 2)
        XCTAssertEqual(entries.first?.rabies, 1)
        XCTAssertEqual(entries.first?.damageDealt, 50)
        XCTAssertEqual(entries.first?.survivedSeconds, 42)
    }

    func test_sortedEntries_ordersDescendingByScore() throws {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }

        let store = HighScoreStore(defaults: defaults)
        try store.recordRun(makeSummary(score: 100))
        try store.recordRun(makeSummary(score: 900))
        try store.recordRun(makeSummary(score: 450))

        XCTAssertEqual(try store.sortedEntries().map(\.score), [900, 450, 100])
    }

    func test_recordRun_multipleEntries_eachHasAStableUniqueID() throws {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }

        let store = HighScoreStore(defaults: defaults)
        try store.recordRun(makeSummary(score: 10))
        try store.recordRun(makeSummary(score: 20))

        let ids = try store.sortedEntries().map(\.id)
        XCTAssertEqual(Set(ids).count, 2, "each recorded run must get its own identity")
    }

    func test_differentSuites_doNotLeakStateBetweenStores() throws {
        let (defaultsA, cleanupA) = makeIsolatedDefaults()
        let (defaultsB, cleanupB) = makeIsolatedDefaults()
        defer {
            cleanupA()
            cleanupB()
        }

        let storeA = HighScoreStore(defaults: defaultsA)
        try storeA.recordRun(makeSummary(score: 777))

        let storeB = HighScoreStore(defaults: defaultsB)
        XCTAssertTrue(try storeB.sortedEntries().isEmpty, "a fresh suite must start empty regardless of other stores' state")
    }

    // MARK: - Tie ordering (PR #49 review)

    /// `sorted(by:)` is an introsort with no stability guarantee, so equal
    /// scores need an explicit tie-break or the "highlight the current run"
    /// AC can land on a different row between two reads of the same data.
    func test_sortedEntries_breaksScoreTiesByRecordOrder_deterministically() throws {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }

        let store = HighScoreStore(defaults: defaults)
        try store.recordRun(makeSummary(score: 250))
        try store.recordRun(makeSummary(score: 250))
        try store.recordRun(makeSummary(score: 250))

        let firstRead = try store.sortedEntries()
        XCTAssertEqual(
            firstRead.map(\.sequence), [0, 1, 2],
            "tied scores must read back in the order they were recorded"
        )

        // Same data, a second read and a relaunched instance: identical
        // order, row for row.
        XCTAssertEqual(try store.sortedEntries().map(\.id), firstRead.map(\.id))
        let relaunched = HighScoreStore(defaults: defaults)
        XCTAssertEqual(try relaunched.sortedEntries().map(\.id), firstRead.map(\.id))
    }

    func test_ranked_isATotalOrder_evenWhenSequencesCollide() {
        // v1 entries all decode with `sequence == 0`; the `id` tie-break
        // keeps the order total (and so stable) anyway.
        let summary = makeSummary(score: 250)
        let a = HighScoreEntry(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!, sequence: 0, summary: summary)
        let b = HighScoreEntry(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!, sequence: 0, summary: summary)

        XCTAssertEqual(HighScoreStore.ranked([b, a], limitedTo: 10).map(\.id), [a.id, b.id])
        XCTAssertEqual(HighScoreStore.ranked([a, b], limitedTo: 10).map(\.id), [a.id, b.id])
    }

    // MARK: - Schema tolerance and failure modes (PR #49 review)

    /// A table written by an older build (a bare `[HighScoreEntry]` array,
    /// no `version` key, no `sequence` key) must still decode -- otherwise
    /// adding one field silently wipes every existing player's history.
    func test_v1ShapedPayload_stillDecodes_andSurvivesTheNextRecordRun() throws {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }

        let v1Payload = Data("""
        [{"id":"00000000-0000-0000-0000-000000000001","score":250,"survivedSeconds":30,\
        "raccoonsDown":2,"level":3,"rabies":1,"damageDealt":40,"killBonus":200,"survivalBonus":90}]
        """.utf8)
        defaults.set(v1Payload, forKey: HighScoreStore.storageKey)

        let store = HighScoreStore(defaults: defaults)
        let migrated = try store.sortedEntries()
        XCTAssertEqual(migrated.count, 1)
        XCTAssertEqual(migrated.first?.score, 250)
        XCTAssertEqual(migrated.first?.level, 3)
        XCTAssertEqual(migrated.first?.sequence, 0, "a missing sequence key defaults rather than failing the decode")

        try store.recordRun(makeSummary(score: 100))
        XCTAssertEqual(
            try store.sortedEntries().map(\.score), [250, 100],
            "recording a new run must not drop the pre-existing v1 table"
        )
    }

    func test_unreadablePayload_throws_ratherThanReadingAsNoScoresYet() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }

        defaults.set(Data("not a high score table".utf8), forKey: HighScoreStore.storageKey)

        let store = HighScoreStore(defaults: defaults)
        XCTAssertThrowsError(try store.loadEntries()) { error in
            XCTAssertEqual(error as? HighScoreStoreError, .storedDataUnreadable)
        }
        XCTAssertThrowsError(try store.sortedEntries())
    }

    func test_recordRun_overAnUnreadablePayload_quarantinesItRatherThanDestroyingIt() throws {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }

        let unreadable = Data("not a high score table".utf8)
        defaults.set(unreadable, forKey: HighScoreStore.storageKey)

        let store = HighScoreStore(defaults: defaults)
        let outcome = try store.recordRun(makeSummary(score: 42))

        XCTAssertEqual(outcome, .recordedAfterQuarantiningUnreadableTable, "the caller must be able to tell this happened")
        XCTAssertEqual(
            defaults.data(forKey: HighScoreStore.unreadableBackupKey), unreadable,
            "the un-decodable bytes must be preserved, not overwritten in place"
        )
        XCTAssertEqual(try store.sortedEntries().map(\.score), [42])
    }

    // MARK: - Bounded table + reset (PR #49 review)

    func test_recordRun_trimsToMaxEntries_soStorageStaysBounded() throws {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }

        let store = HighScoreStore(defaults: defaults, maxEntries: 3)
        for score in [10, 50, 20, 90, 30] {
            try store.recordRun(makeSummary(score: score))
        }

        XCTAssertEqual(try store.sortedEntries().map(\.score), [90, 50, 30])

        // The trim happens at write time, so the *stored* blob is bounded
        // too -- not just the view a reader slices off it.
        let relaunched = HighScoreStore(defaults: defaults, maxEntries: 100)
        XCTAssertEqual(try relaunched.loadEntries().count, 3)
    }

    func test_clear_removesTheTable() throws {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }

        let store = HighScoreStore(defaults: defaults)
        try store.recordRun(makeSummary(score: 600))
        XCTAssertFalse(try store.sortedEntries().isEmpty)

        store.clear()

        XCTAssertTrue(try store.sortedEntries().isEmpty)
        XCTAssertNil(defaults.data(forKey: HighScoreStore.storageKey))
    }

    // MARK: - The suite-name initializer (PR #49 review)

    func test_initWithSuiteName_roundTripsThroughTheNamedSuite() throws {
        let suiteName = "com.cyberpunkmonstercrawl.tests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        let store = try XCTUnwrap(HighScoreStore(suiteName: suiteName))
        try store.recordRun(makeSummary(score: 321))

        let relaunched = try XCTUnwrap(HighScoreStore(suiteName: suiteName))
        XCTAssertEqual(try relaunched.sortedEntries().map(\.score), [321])
    }

    /// The initializer production is meant to use must fail loudly on a
    /// suite it cannot construct, instead of silently backing the store with
    /// `.standard` where the scores are shared with everything else the app
    /// stores and never cleaned up.
    func test_initWithSuiteName_returnsNil_insteadOfFallingBackToStandard() {
        XCTAssertNil(HighScoreStore(suiteName: UserDefaults.globalDomain))
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            XCTAssertNil(
                HighScoreStore(suiteName: bundleIdentifier),
                "UserDefaults(suiteName:) rejects the app's own bundle identifier"
            )
        }
    }

    /// The production path itself, previously exercised by zero tests. Only
    /// constructed -- deliberately never written through, so a test run
    /// cannot touch a real player's table.
    func test_productionSuiteName_isConstructible_andNotAReservedDomain() {
        XCTAssertNotEqual(HighScoreStore.productionSuiteName, UserDefaults.globalDomain)
        XCTAssertNotEqual(HighScoreStore.productionSuiteName, Bundle.main.bundleIdentifier)
        XCTAssertNotNil(HighScoreStore(suiteName: HighScoreStore.productionSuiteName))
    }
}
