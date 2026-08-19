import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-9` PR 3: `RunStats`'s cumulative `damageDealt`/`killCount`
/// counters (AC8).
final class RunStatsTests: XCTestCase {

    func test_freshRunStats_startsAtZero() {
        let stats = RunStats()
        XCTAssertEqual(stats.damageDealt, 0)
        XCTAssertEqual(stats.killCount, 0)
    }

    func test_recordDamage_accumulatesAcrossMultipleEvents() {
        let stats = RunStats()
        stats.recordDamage(8)
        stats.recordDamage(5)
        stats.recordDamage(9)
        XCTAssertEqual(stats.damageDealt, 22)
    }

    func test_recordDamage_nonPositiveAmount_isANoOp() {
        let stats = RunStats()
        stats.recordDamage(0)
        stats.recordDamage(-4)
        XCTAssertEqual(stats.damageDealt, 0)
    }

    func test_recordKill_accumulatesAcrossMultipleEvents() {
        let stats = RunStats()
        stats.recordKill()
        stats.recordKill()
        stats.recordKill()
        XCTAssertEqual(stats.killCount, 3)
    }

    func test_damageAndKillCounters_areIndependent() {
        let stats = RunStats()
        stats.recordDamage(8)
        stats.recordDamage(8)
        stats.recordKill()

        XCTAssertEqual(stats.damageDealt, 16)
        XCTAssertEqual(stats.killCount, 1)
    }

    func test_interleavedDamageAndKillEvents_bothAccumulateCorrectly() {
        let stats = RunStats()
        stats.recordDamage(5)
        stats.recordKill()
        stats.recordDamage(9)
        stats.recordDamage(8)
        stats.recordKill()

        XCTAssertEqual(stats.damageDealt, 22)
        XCTAssertEqual(stats.killCount, 2)
    }
}
