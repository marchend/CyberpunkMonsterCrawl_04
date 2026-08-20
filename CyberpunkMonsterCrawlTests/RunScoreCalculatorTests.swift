import XCTest
@testable import CyberpunkMonsterCrawl

/// PR 1 (`CYBERPUN-17-13`): `RunScoreCalculator`'s SCORE/KILL BONUS
/// formulas and the RABIES row's infection-count semantics (AC2/AC3).
final class RunScoreCalculatorTests: XCTestCase {

    /// Advances a fresh `XPLevelSystem` to exactly `level` via `awardXP`,
    /// the only production way its `level` ever changes. `level(forXP:)`
    /// crosses to `level` at cumulative XP `(level - 1) * xpPerLevel`.
    private func makeXPLevelSystem(level: Int) -> XPLevelSystem {
        let system = XPLevelSystem()
        if level > 1 {
            system.awardXP((level - 1) * XPLevelSystem.xpPerLevel)
        }
        XCTAssertEqual(system.level, level, "test fixture setup is wrong")
        return system
    }

    func test_score_forFixtureRun_allZero() {
        let summary = RunScoreCalculator.summarize(
            runSummaryStats: RunSummaryStats(),
            runStats: RunStats(),
            xpLevelSystem: makeXPLevelSystem(level: 1),
            elapsedSeconds: 0
        )

        XCTAssertEqual(summary.damageDealt, 0)
        XCTAssertEqual(summary.killBonus, 0)
        XCTAssertEqual(summary.survivalBonus, 0)
        XCTAssertEqual(summary.score, 0)
    }

    func test_score_forFixtureRun_typicalValues() {
        let runSummaryStats = RunSummaryStats()
        for _ in 0..<5 { runSummaryStats.recordKill() }

        let runStats = RunStats()
        runStats.recordDamage(120)

        let summary = RunScoreCalculator.summarize(
            runSummaryStats: runSummaryStats,
            runStats: runStats,
            xpLevelSystem: makeXPLevelSystem(level: 3),
            elapsedSeconds: 95.7
        )

        // SCORE = damageDealt + killBonus + floor(elapsedSeconds) * level
        let expectedKillBonus = 100 * 5
        let expectedSurvivalBonus = 95 * 3
        let expectedScore = 120 + expectedKillBonus + expectedSurvivalBonus

        XCTAssertEqual(summary.damageDealt, 120)
        XCTAssertEqual(summary.raccoonsDown, 5)
        XCTAssertEqual(summary.level, 3)
        XCTAssertEqual(summary.survivedSeconds, 95)
        XCTAssertEqual(summary.killBonus, expectedKillBonus)
        XCTAssertEqual(summary.survivalBonus, expectedSurvivalBonus)
        XCTAssertEqual(summary.score, expectedScore)
    }

    func test_score_forFixtureRun_highLevelLongSurvival() {
        let runSummaryStats = RunSummaryStats()
        for _ in 0..<12 { runSummaryStats.recordKill() }

        let runStats = RunStats()
        runStats.recordDamage(340)

        let summary = RunScoreCalculator.summarize(
            runSummaryStats: runSummaryStats,
            runStats: runStats,
            xpLevelSystem: makeXPLevelSystem(level: 6),
            elapsedSeconds: 250.99
        )

        let expectedKillBonus = 100 * 12
        let expectedSurvivalBonus = 250 * 6
        let expectedScore = 340 + expectedKillBonus + expectedSurvivalBonus

        XCTAssertEqual(summary.survivedSeconds, 250, "elapsedSeconds must be floored, not rounded")
        XCTAssertEqual(summary.killBonus, expectedKillBonus)
        XCTAssertEqual(summary.survivalBonus, expectedSurvivalBonus)
        XCTAssertEqual(summary.score, expectedScore)
    }

    func test_score_forFixtureRun_noKillsStillScoresFromDamageAndSurvival() {
        let runStats = RunStats()
        runStats.recordDamage(42)

        let summary = RunScoreCalculator.summarize(
            runSummaryStats: RunSummaryStats(),
            runStats: runStats,
            xpLevelSystem: makeXPLevelSystem(level: 2),
            elapsedSeconds: 10.0
        )

        XCTAssertEqual(summary.killBonus, 0)
        XCTAssertEqual(summary.survivalBonus, 20)
        XCTAssertEqual(summary.score, 62)
    }

    func test_killBonus_isAlwaysOneHundredTimesKillCount() {
        for killCount in [0, 1, 3, 7, 20] {
            XCTAssertEqual(
                RunScoreCalculator.killBonus(forKillCount: killCount),
                100 * killCount
            )
        }
    }

    func test_rabies_reflectsTimesInfected_notHPLostToRabies() {
        let runSummaryStats = RunSummaryStats()
        runSummaryStats.recordInfection()
        runSummaryStats.recordInfection()
        runSummaryStats.recordInfection()

        let runStats = RunStats()
        // A large, unrelated damage figure: RABIES must reflect the 3
        // recorded infection *events* above, never this or any other
        // HP-lost-to-rabies bookkeeping.
        runStats.recordDamage(999)

        let summary = RunScoreCalculator.summarize(
            runSummaryStats: runSummaryStats,
            runStats: runStats,
            xpLevelSystem: makeXPLevelSystem(level: 1),
            elapsedSeconds: 10
        )

        XCTAssertEqual(summary.rabies, 3)
        XCTAssertNotEqual(summary.rabies, 999)
    }

    func test_rabies_zeroInfections_isZero() {
        let summary = RunScoreCalculator.summarize(
            runSummaryStats: RunSummaryStats(),
            runStats: RunStats(),
            xpLevelSystem: makeXPLevelSystem(level: 1),
            elapsedSeconds: 0
        )

        XCTAssertEqual(summary.rabies, 0)
    }
}
