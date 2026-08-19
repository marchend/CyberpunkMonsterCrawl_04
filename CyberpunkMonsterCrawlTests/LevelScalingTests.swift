import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-10` PR 1: `LevelScaling`'s pulse radius-multiplier and
/// damage-die tables -- the shared level-scaling accessors the pulse
/// ability (and any future level-scaled ability) reads.
final class LevelScalingTests: XCTestCase {

    // MARK: - Radius multiplier: compounding +25% / +25%

    func test_pulseRadiusMultiplier_belowLevel3_isUnscaled() {
        XCTAssertEqual(LevelScaling.pulseRadiusMultiplier(forLevel: 0), 1.0, accuracy: 1e-9)
        XCTAssertEqual(LevelScaling.pulseRadiusMultiplier(forLevel: 2), 1.0, accuracy: 1e-9)
    }

    func test_pulseRadiusMultiplier_atLevels3Through5_isPlus25Percent() {
        XCTAssertEqual(LevelScaling.pulseRadiusMultiplier(forLevel: 3), 1.25, accuracy: 1e-9)
        XCTAssertEqual(LevelScaling.pulseRadiusMultiplier(forLevel: 5), 1.25, accuracy: 1e-9)
    }

    func test_pulseRadiusMultiplier_atLevel6AndAbove_compoundsAnotherPlus25Percent() {
        // 1.25 * 1.25 == 1.5625 -- compounding on the level-3 bonus, not
        // an additive +50%.
        XCTAssertEqual(LevelScaling.pulseRadiusMultiplier(forLevel: 6), 1.5625, accuracy: 1e-9)
        XCTAssertEqual(LevelScaling.pulseRadiusMultiplier(forLevel: 9), 1.5625, accuracy: 1e-9)
    }

    // MARK: - Damage die: d6 below level 6, d8 at/above level 6

    func test_pulseDamageDie_belowLevel6_isD6() {
        XCTAssertEqual(LevelScaling.pulseDamageDie(forLevel: 0), DiceSpec(count: 1, sides: 6))
        XCTAssertEqual(LevelScaling.pulseDamageDie(forLevel: 5), DiceSpec(count: 1, sides: 6))
    }

    func test_pulseDamageDie_atLevel6AndAbove_isD8() {
        XCTAssertEqual(LevelScaling.pulseDamageDie(forLevel: 6), DiceSpec(count: 1, sides: 8))
        XCTAssertEqual(LevelScaling.pulseDamageDie(forLevel: 9), DiceSpec(count: 1, sides: 8))
    }
}
