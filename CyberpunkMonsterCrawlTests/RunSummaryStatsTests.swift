import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-8` PR 3: `RunSummaryStats`'s two combat-layer counters --
/// `timesInfected` (distinct infection occurrences, not per-tick) and
/// `killCount` (raccoon deaths).
final class RunSummaryStatsTests: XCTestCase {

    // MARK: - Defaults

    func test_init_defaultsBothCountersToZero() {
        let stats = RunSummaryStats()
        XCTAssertEqual(stats.timesInfected, 0)
        XCTAssertEqual(stats.killCount, 0)
    }

    // MARK: - timesInfected

    func test_recordInfection_incrementsTimesInfected_byOnePerCall() {
        let stats = RunSummaryStats()
        stats.recordInfection()
        XCTAssertEqual(stats.timesInfected, 1)
        stats.recordInfection()
        XCTAssertEqual(stats.timesInfected, 2)
    }

    /// `PlayerNode.infect(stats:)` is the one production caller and it
    /// guards against calling `recordInfection()` while already infected --
    /// pinned end-to-end here rather than only unit-testing the guard on
    /// `PlayerNode` in isolation, since this counter's entire contract is
    /// "once per **occurrence**, not per successful roll".
    func test_playerInfect_recordsExactlyOneInfection_evenAcrossRepeatedInfectAttempts() {
        let stats = RunSummaryStats()
        let player = PlayerNode()

        player.infect(stats: stats)
        player.infect(stats: stats)
        player.infect(stats: stats)

        XCTAssertEqual(stats.timesInfected, 1)
    }

    /// The DoT tick itself must never touch this counter -- only the
    /// initial `infect(stats:)` call does.
    func test_tickRabies_neverIncrementsTimesInfected() {
        let stats = RunSummaryStats()
        let player = PlayerNode()
        player.infect(stats: stats)
        XCTAssertEqual(stats.timesInfected, 1)

        for _ in 0..<120 {
            player.tickRabies(deltaTime: 1.0 / 60.0)
        }

        XCTAssertEqual(stats.timesInfected, 1, "ticking the DoT must never record another infection occurrence.")
    }

    // MARK: - killCount

    func test_recordKill_incrementsKillCount_byOnePerCall() {
        let stats = RunSummaryStats()
        stats.recordKill()
        stats.recordKill()
        stats.recordKill()
        XCTAssertEqual(stats.killCount, 3)
    }

    /// `RaccoonNode+Combat.swift`'s `die()` is the production caller;
    /// pinned end-to-end so a change to that wiring is caught here too.
    func test_raccoonDeath_incrementsKillCount_exactlyOnce() {
        let stats = RunSummaryStats()
        let raccoon = RaccoonNode(tier: .base, hp: 1)
        raccoon.runStats = stats

        raccoon.takeDamage(1)

        XCTAssertEqual(stats.killCount, 1)
    }

    func test_raccoonDeath_doesNotDoubleCount_whenDamagedAgainAfterDeath() {
        let stats = RunSummaryStats()
        let raccoon = RaccoonNode(tier: .base, hp: 1)
        raccoon.runStats = stats

        raccoon.takeDamage(1)
        raccoon.takeDamage(5)

        XCTAssertEqual(stats.killCount, 1)
    }
}
