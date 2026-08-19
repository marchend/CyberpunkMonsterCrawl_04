import Foundation
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-9` PR 3: `XPLevelSystem`'s XP curve, level-up boundaries,
/// the pure `tier(forLevel:)` mapping, and the "no manual tier-set API"
/// contract (AC4).
final class XPLevelSystemTests: XCTestCase {

    // MARK: - XP curve / level boundaries

    func test_freshSystem_startsAtLevel1_withZeroXP() {
        let system = XPLevelSystem()
        XCTAssertEqual(system.xp, 0)
        XCTAssertEqual(system.level, 1)
    }

    func test_level_staysBelow3_untilTheThresholdXP_thenTransitionsExactlyAtIt() {
        let threshold = 2 * XPLevelSystem.xpPerLevel // 200: level(forXP:) crosses to level 3 here.
        let system = XPLevelSystem()

        // One short of the threshold: still below level 3.
        system.awardXP(threshold - 1)
        XCTAssertLessThan(system.level, 3, "level must stay below 3 until the threshold XP is reached.")

        // The remaining single point of XP crosses the threshold exactly.
        system.awardXP(1)
        XCTAssertEqual(system.level, 3, "level must transition to exactly 3 at the threshold XP.")
    }

    func test_level_staysBelow6_untilTheThresholdXP_thenTransitionsExactlyAtIt() {
        let threshold = 5 * XPLevelSystem.xpPerLevel // 500: level(forXP:) crosses to level 6 here.
        let system = XPLevelSystem()

        system.awardXP(threshold - 1)
        XCTAssertLessThan(system.level, 6, "level must stay below 6 until the threshold XP is reached.")

        system.awardXP(1)
        XCTAssertEqual(system.level, 6, "level must transition to exactly 6 at the threshold XP.")
    }

    func test_levelForXP_matchesTheFlatCurve_acrossMultipleLevels() {
        XCTAssertEqual(XPLevelSystem.level(forXP: 0), 1)
        XCTAssertEqual(XPLevelSystem.level(forXP: XPLevelSystem.xpPerLevel - 1), 1)
        XCTAssertEqual(XPLevelSystem.level(forXP: XPLevelSystem.xpPerLevel), 2)
        XCTAssertEqual(XPLevelSystem.level(forXP: 2 * XPLevelSystem.xpPerLevel), 3)
        XCTAssertEqual(XPLevelSystem.level(forXP: 5 * XPLevelSystem.xpPerLevel), 6)
    }

    func test_awardXP_accumulatesAcrossMultipleCalls() {
        let system = XPLevelSystem()
        system.awardXP(30)
        system.awardXP(45)
        XCTAssertEqual(system.xp, 75)
    }

    func test_awardXP_nonPositiveAmount_isANoOp() {
        let system = XPLevelSystem()
        system.awardXP(0)
        system.awardXP(-10)
        XCTAssertEqual(system.xp, 0)
        XCTAssertEqual(system.level, 1)
    }

    // MARK: - onLevelChange notification

    func test_onLevelChange_neverFires_atConstruction() {
        let system = XPLevelSystem()
        var fired = false
        system.onLevelChange = { _ in fired = true }
        // No awardXP call at all: subscribing itself must never fire.
        XCTAssertFalse(fired)
    }

    func test_onLevelChange_firesOnlyOnAGenuineLevelChange() {
        let system = XPLevelSystem()
        var changes: [Int] = []
        system.onLevelChange = { level in changes.append(level) }

        // Within level 1 the whole way: must not fire.
        system.awardXP(10)
        system.awardXP(10)
        XCTAssertTrue(changes.isEmpty, "no level boundary was crossed yet.")

        // Crosses into level 2.
        system.awardXP(XPLevelSystem.xpPerLevel)
        XCTAssertEqual(changes, [2])

        // Another award that stays within level 2: must not fire again.
        system.awardXP(5)
        XCTAssertEqual(changes, [2], "no new level boundary was crossed.")

        // Crosses into level 3.
        system.awardXP(XPLevelSystem.xpPerLevel)
        XCTAssertEqual(changes, [2, 3])
    }

    // MARK: - tier(forLevel:) boundaries

    func test_tierForLevel_handgunBelowLevel3() {
        XCTAssertEqual(XPLevelSystem.tier(forLevel: 1), .handgun)
        XCTAssertEqual(XPLevelSystem.tier(forLevel: 2), .handgun)
    }

    func test_tierForLevel_smgFromLevel3Through5() {
        XCTAssertEqual(XPLevelSystem.tier(forLevel: 3), .smg)
        XCTAssertEqual(XPLevelSystem.tier(forLevel: 4), .smg)
        XCTAssertEqual(XPLevelSystem.tier(forLevel: 5), .smg)
    }

    func test_tierForLevel_assaultRifleFromLevel6Upward() {
        XCTAssertEqual(XPLevelSystem.tier(forLevel: 6), .assaultRifle)
        XCTAssertEqual(XPLevelSystem.tier(forLevel: 20), .assaultRifle)
    }

    // MARK: - AC4: no manual tier-set API exists anywhere on this type

    /// A plain source scan (the same shape
    /// `NoBuildingGeometryConstructionTests` uses for its own gate): proves
    /// `XPLevelSystem.swift` declares no `tier` stored property and no
    /// `setTier`-shaped method of its own, so the only way this type's
    /// notion of tier ever reaches a consumer is the pure, stateless
    /// `tier(forLevel:)` function.
    func test_xpLevelSystemSource_declaresNoManualTierSetAPI() throws {
        let fileURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // CyberpunkMonsterCrawlTests/
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("CyberpunkMonsterCrawl")
            .appendingPathComponent("Sources")
            .appendingPathComponent("Progression")
            .appendingPathComponent("XPLevelSystem.swift")

        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            throw XCTSkip("XPLevelSystem.swift not reachable at \(fileURL.path); this gate is not running.")
        }

        XCTAssertFalse(
            contents.contains("func setTier"),
            "XPLevelSystem must expose no setTier(_:)-shaped API of its own."
        )
        XCTAssertFalse(
            contents.contains("var tier"),
            "XPLevelSystem must not store a tier of its own -- tier is always derived via tier(forLevel:)."
        )
    }
}
