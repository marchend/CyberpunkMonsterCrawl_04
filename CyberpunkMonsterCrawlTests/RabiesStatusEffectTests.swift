import XCTest
@testable import CyberpunkMonsterCrawl

/// A scripted `RandomNumberGenerator` that replays a fixed sequence of raw
/// `UInt64` values, one per call to `next()`, then repeats the last value
/// forever once exhausted -- lets a test pin `RabiesStatusEffect
/// .rollInfects(tier:rng:)`'s exact roll (`rawValue % 20 + 1`) rather than
/// only its statistical distribution.
private struct ScriptedRandomNumberGenerator: RandomNumberGenerator {
    private var values: [UInt64]
    private var index = 0

    init(_ values: [UInt64]) {
        precondition(!values.isEmpty)
        self.values = values
    }

    mutating func next() -> UInt64 {
        let value = values[min(index, values.count - 1)]
        index += 1
        return value
    }
}

/// `CYBERPUN-17-8` PR 3: the d20-vs-tier-threshold rabies infection roll.
final class RabiesStatusEffectTests: XCTestCase {

    // MARK: - DoT rate

    func test_damagePerSecond_isOneHPPerSecond_perTheStory() {
        XCTAssertEqual(RabiesStatusEffect.damagePerSecond, 1.0, accuracy: 1e-9)
    }

    // MARK: - Roll-vs-threshold boundary, pinned exactly via a scripted RNG

    /// `rawValue % 20 + 1` maps raw `0` to roll `1`. `.base`'s threshold is
    /// 10, so roll `1` must infect.
    func test_rollInfects_true_whenRollIsWellBelowTheBaseThreshold() {
        var rng = ScriptedRandomNumberGenerator([0])
        XCTAssertTrue(RabiesStatusEffect.rollInfects(tier: .base, rng: &rng))
    }

    /// Raw `9` maps to roll `10` -- exactly `.base`'s threshold. The rule
    /// is inclusive (`<=`), so this must infect.
    func test_rollInfects_true_whenRollExactlyEqualsTheBaseThreshold() {
        var rng = ScriptedRandomNumberGenerator([9])
        XCTAssertTrue(RabiesStatusEffect.rollInfects(tier: .base, rng: &rng))
    }

    /// Raw `10` maps to roll `11` -- one past `.base`'s threshold of 10.
    /// Must not infect.
    func test_rollInfects_false_whenRollIsOneAboveTheBaseThreshold() {
        var rng = ScriptedRandomNumberGenerator([10])
        XCTAssertFalse(RabiesStatusEffect.rollInfects(tier: .base, rng: &rng))
    }

    /// Raw `19` maps to roll `20`, the worst possible roll -- must not
    /// infect against either tier's threshold.
    func test_rollInfects_false_atTheWorstPossibleRoll_forBothTiers() {
        var baseRng = ScriptedRandomNumberGenerator([19])
        XCTAssertFalse(RabiesStatusEffect.rollInfects(tier: .base, rng: &baseRng))

        var eliteRng = ScriptedRandomNumberGenerator([19])
        XCTAssertFalse(RabiesStatusEffect.rollInfects(tier: .elite, rng: &eliteRng))
    }

    /// Raw `14` maps to roll `15` -- exactly `.elite`'s (higher) threshold.
    /// Must infect for elite, but not for base (whose threshold is 10).
    func test_rollInfects_atTheEliteThreshold_infectsElite_butNotBase() {
        var eliteRng = ScriptedRandomNumberGenerator([14])
        XCTAssertTrue(RabiesStatusEffect.rollInfects(tier: .elite, rng: &eliteRng))

        var baseRng = ScriptedRandomNumberGenerator([14])
        XCTAssertFalse(RabiesStatusEffect.rollInfects(tier: .base, rng: &baseRng))
    }

    /// The elite's higher threshold must make it strictly easier to infect
    /// than the base tier -- checked directly against the tier data rather
    /// than only via spot rolls above.
    func test_eliteThreshold_isHigherThanBase_soEliteInfectsMoreOften() {
        XCTAssertGreaterThan(RaccoonTier.elite.rabiesThreshold, RaccoonTier.base.rabiesThreshold)
    }

    // MARK: - Statistical shape: observed infection fraction matches threshold/20

    func test_rollInfects_observedFraction_matchesBaseThresholdOverTwenty() {
        var rng = SplitMix64RandomNumberGenerator(seed: 123)
        var infections = 0
        let trials = 20_000

        for _ in 0..<trials {
            if RabiesStatusEffect.rollInfects(tier: .base, rng: &rng) {
                infections += 1
            }
        }

        let observedFraction = Double(infections) / Double(trials)
        let expectedFraction = Double(RaccoonTier.base.rabiesThreshold) / 20.0
        XCTAssertEqual(observedFraction, expectedFraction, accuracy: 0.02)
    }

    func test_rollInfects_observedFraction_matchesEliteThresholdOverTwenty() {
        var rng = SplitMix64RandomNumberGenerator(seed: 456)
        var infections = 0
        let trials = 20_000

        for _ in 0..<trials {
            if RabiesStatusEffect.rollInfects(tier: .elite, rng: &rng) {
                infections += 1
            }
        }

        let observedFraction = Double(infections) / Double(trials)
        let expectedFraction = Double(RaccoonTier.elite.rabiesThreshold) / 20.0
        XCTAssertEqual(observedFraction, expectedFraction, accuracy: 0.02)
    }

    // MARK: - Player DoT tick: exactly 1 HP per second, sampled over a duration

    func test_infectedPlayer_loses1HPPerSecond_sampledOver10SecondsAt60fps() {
        let player = PlayerNode()
        let stats = RunSummaryStats()
        let startingHP = player.hp

        player.infect(stats: stats)

        let frameDelta: TimeInterval = 1.0 / 60.0
        let totalSeconds: TimeInterval = 10
        var elapsed: TimeInterval = 0
        while elapsed < totalSeconds {
            player.tickRabies(deltaTime: frameDelta)
            elapsed += frameDelta
        }

        // Exactly 10 HP in exact real-number arithmetic; tolerate +/-1 HP
        // for the summed floating-point `deltaTime` steps possibly landing
        // a whole-second boundary a frame either side (600 additions of
        // `1.0 / 60.0`, a non-terminating binary fraction) -- `Int` has no
        // `accuracy:` overload, so the tolerance is checked by hand.
        let hpLost = startingHP - player.hp
        XCTAssertGreaterThanOrEqual(hpLost, 9, "10 seconds of infection at 60fps must cost ~10 HP.")
        XCTAssertLessThanOrEqual(hpLost, 11, "10 seconds of infection at 60fps must cost ~10 HP.")
    }

    func test_infectedPlayer_loses1HPPerSecond_regardlessOfFrameRate() {
        let player = PlayerNode()
        let stats = RunSummaryStats()
        let startingHP = player.hp

        player.infect(stats: stats)

        // A much coarser frame rate (e.g. a stalled frame) must accumulate
        // to the same whole-HP result rather than losing fractional
        // damage between calls.
        for _ in 0..<5 {
            player.tickRabies(deltaTime: 1.0)
        }

        XCTAssertEqual(player.hp, startingHP - 5)
    }

    func test_uninfectedPlayer_tickRabies_isANoOp() {
        let player = PlayerNode()
        let startingHP = player.hp

        player.tickRabies(deltaTime: 5)

        XCTAssertEqual(player.hp, startingHP)
    }
}
