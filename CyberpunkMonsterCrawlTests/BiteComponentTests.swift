import XCTest
@testable import CyberpunkMonsterCrawl

/// A `RandomNumberGenerator` that always reports the same raw value --
/// deterministically forces (or forbids) `RabiesStatusEffect.rollInfects`
/// via `RabiesStatusEffectTests`'s own documented `rawValue % 20 + 1`
/// mapping, so this file's tests can assert on the infection side-effect
/// without depending on statistical odds.
private struct ConstantRandomNumberGenerator: RandomNumberGenerator {
    let value: UInt64
    mutating func next() -> UInt64 { value }
}

/// `CYBERPUN-17-8` PR 3: `BiteComponent`'s contact-trigger cadence -- an
/// attack animation + damage + rabies roll on the first frame of contact,
/// then silence until the bite interval elapses again, however many
/// frames of sustained contact pass in between.
final class BiteComponentTests: XCTestCase {

    /// Raw `0` maps to roll `1` (`RabiesStatusEffectTests`'s documented
    /// mapping), which infects against every tier's threshold.
    private func alwaysInfectsRNG() -> ConstantRandomNumberGenerator {
        ConstantRandomNumberGenerator(value: 0)
    }

    /// Raw `19` maps to roll `20`, the worst possible roll, which never
    /// infects against either tier's threshold.
    private func neverInfectsRNG() -> ConstantRandomNumberGenerator {
        ConstantRandomNumberGenerator(value: 19)
    }

    // MARK: - First contact: bites immediately

    func test_firstUpdate_playsAttackAnimation_andDamagesThePlayer() {
        let raccoon = RaccoonNode(tier: .base)
        let player = PlayerNode()
        let startingHP = player.hp
        let bite = BiteComponent(stats: RunSummaryStats())
        var rng = neverInfectsRNG()

        bite.update(raccoon: raccoon, player: player, deltaTime: 1.0 / 60.0, rng: &rng)

        XCTAssertEqual(raccoon.animationController.state, .attack, "contact must switch the raccoon to its attack animation.")
        XCTAssertEqual(player.hp, startingHP - BiteComponent.biteDamage)
    }

    func test_firstUpdate_attackAnimation_playsAt12fps() {
        // `playAttack()` selects the attack sheet; `RaccoonAnimationController
        // .attackFramesPerSecond` (12) is what then drives that sheet's frame
        // cadence, per the story ("attack 12 fps"). This pins the cadence
        // BiteComponent's trigger hands off into.
        XCTAssertEqual(RaccoonAnimationController.attackFramesPerSecond, 12)
    }

    // MARK: - Sustained contact: does not re-trigger every frame

    func test_sustainedContact_withinTheBiteInterval_doesNotDamageAgain() {
        let raccoon = RaccoonNode(tier: .base)
        let player = PlayerNode()
        let bite = BiteComponent(stats: RunSummaryStats())
        var rng = neverInfectsRNG()

        // First frame: bites once.
        bite.update(raccoon: raccoon, player: player, deltaTime: 1.0 / 60.0, rng: &rng)
        let hpAfterFirstBite = player.hp

        // Many more frames, still well inside `biteIntervalSeconds` (1s):
        // 30 frames at 1/60s each is half a second.
        for _ in 0..<30 {
            bite.update(raccoon: raccoon, player: player, deltaTime: 1.0 / 60.0, rng: &rng)
        }

        XCTAssertEqual(
            player.hp, hpAfterFirstBite,
            "sustained contact inside the bite window must not deal damage again."
        )
    }

    func test_sustainedContact_pastTheBiteInterval_bitesAgain() {
        let raccoon = RaccoonNode(tier: .base)
        let player = PlayerNode()
        let bite = BiteComponent(stats: RunSummaryStats())
        var rng = neverInfectsRNG()

        bite.update(raccoon: raccoon, player: player, deltaTime: 1.0 / 60.0, rng: &rng)
        let hpAfterFirstBite = player.hp

        // Advance clear past the bite interval (1s) in one jump.
        bite.update(raccoon: raccoon, player: player, deltaTime: BiteComponent.biteIntervalSeconds + 0.01, rng: &rng)

        XCTAssertEqual(player.hp, hpAfterFirstBite - BiteComponent.biteDamage)
    }

    func test_repeatedFramesOverManySeconds_bitesRoughlyOncePerInterval_neverMoreOftenThanTheInterval() {
        let raccoon = RaccoonNode(tier: .base)
        let player = PlayerNode()
        let startingHP = player.hp
        let bite = BiteComponent(stats: RunSummaryStats())
        var rng = neverInfectsRNG()

        let frameDelta: TimeInterval = 1.0 / 60.0
        let totalSeconds: TimeInterval = 5.0
        var elapsed: TimeInterval = 0
        while elapsed < totalSeconds {
            bite.update(raccoon: raccoon, player: player, deltaTime: frameDelta, rng: &rng)
            elapsed += frameDelta
        }

        // One bite at first contact, then one every `biteIntervalSeconds`
        // (1s) thereafter: about 5 bites over a 5 second window sampled at
        // 60fps. Bounded rather than pinned to an exact count -- summing
        // many small floating-point `deltaTime` steps can land the
        // interval boundary a frame either side, which must not be read as
        // "bites every frame" (the defect this component exists to
        // prevent) nor as the interval silently growing.
        let bites = (startingHP - player.hp) / BiteComponent.biteDamage
        XCTAssertGreaterThanOrEqual(bites, 4, "sampled over 5 seconds, a ~1s bite interval must land at least 4 bites.")
        XCTAssertLessThanOrEqual(bites, 6, "sampled over 5 seconds, a ~1s bite interval must not land more than 6 bites.")
    }

    // MARK: - deltaTime <= 0 is a no-op

    func test_zeroOrNegativeDeltaTime_isANoOp() {
        let raccoon = RaccoonNode(tier: .base)
        let player = PlayerNode()
        let startingHP = player.hp
        let bite = BiteComponent(stats: RunSummaryStats())
        var rng = neverInfectsRNG()

        bite.update(raccoon: raccoon, player: player, deltaTime: 0, rng: &rng)
        bite.update(raccoon: raccoon, player: player, deltaTime: -1, rng: &rng)

        XCTAssertEqual(player.hp, startingHP)
        XCTAssertNotEqual(raccoon.animationController.state, .attack)
    }

    // MARK: - Infection roll

    func test_bite_infectsThePlayer_whenTheRollSucceeds() {
        let raccoon = RaccoonNode(tier: .base)
        let player = PlayerNode()
        let stats = RunSummaryStats()
        let bite = BiteComponent(stats: stats)
        var rng = alwaysInfectsRNG()

        bite.update(raccoon: raccoon, player: player, deltaTime: 1.0 / 60.0, rng: &rng)

        XCTAssertTrue(player.isInfected)
        XCTAssertEqual(stats.timesInfected, 1)
    }

    func test_bite_doesNotInfect_whenTheRollFails() {
        let raccoon = RaccoonNode(tier: .base)
        let player = PlayerNode()
        let stats = RunSummaryStats()
        let bite = BiteComponent(stats: stats)
        var rng = neverInfectsRNG()

        bite.update(raccoon: raccoon, player: player, deltaTime: 1.0 / 60.0, rng: &rng)

        XCTAssertFalse(player.isInfected)
        XCTAssertEqual(stats.timesInfected, 0)
    }

    func test_repeatedSuccessfulBites_recordOnlyOneInfectionOccurrence() {
        let raccoon = RaccoonNode(tier: .base)
        let player = PlayerNode()
        let stats = RunSummaryStats()
        let bite = BiteComponent(stats: stats)
        var rng = alwaysInfectsRNG()

        bite.update(raccoon: raccoon, player: player, deltaTime: 1.0 / 60.0, rng: &rng)
        bite.update(raccoon: raccoon, player: player, deltaTime: BiteComponent.biteIntervalSeconds + 0.01, rng: &rng)
        bite.update(raccoon: raccoon, player: player, deltaTime: BiteComponent.biteIntervalSeconds + 0.01, rng: &rng)

        XCTAssertEqual(stats.timesInfected, 1, "a player already infected must not be recorded as re-infected on a later successful roll.")
    }
}
