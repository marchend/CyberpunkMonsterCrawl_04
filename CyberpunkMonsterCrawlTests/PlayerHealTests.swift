import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-11` PR 2: `PlayerNode.heal(_:)` -- the med-kit consumption
/// effect (apply a collected med kit's rolled amount, capped at `maxHP`),
/// proven entirely independent of scene/collision wiring per this PR's
/// acceptance criteria.
///
/// The roll itself is no longer this type's job (PR #37 review):
/// `PickupManager.attemptCollectMedKit(at:radius:)` consumes the pickup
/// record and reports the authoritative 1d10, and `heal(_:)` applies it.
/// The roll-then-apply composition a wiring PR performs is still pinned
/// here, via `DiceSpec.roll(using:)` against a scripted generator.
final class PlayerHealTests: XCTestCase {

    /// A scripted `RandomNumberGenerator` that replays one fixed raw
    /// `UInt64` value forever -- lets a test pin `DiceSpec.roll(using:)`'s
    /// exact result (`rawValue % 10 + 1` for a 1d10) rather than only its
    /// range, the same shape `RabiesStatusEffectTests`' own (private,
    /// file-local) `ScriptedRandomNumberGenerator` uses for the same reason.
    private struct ScriptedRandomNumberGenerator: RandomNumberGenerator {
        private let value: UInt64
        init(_ value: UInt64) { self.value = value }
        func next() -> UInt64 { value }
    }

    // MARK: - Far from max HP: the full amount is applied

    func test_heal_appliesTheFullAmount_whenFarFromMaxHP() {
        let player = PlayerNode()
        player.hp = 10 // far below maxHP (100)

        let applied = player.heal(4)

        XCTAssertEqual(applied, 4)
        XCTAssertEqual(player.hp, 14)
    }

    // MARK: - Near max HP: the applied amount is capped

    func test_heal_capsTheAppliedAmount_whenNearMaxHP() {
        let player = PlayerNode()
        player.hp = player.maxHP - 3 // only 3 HP short of max

        let applied = player.heal(8) // would overshoot maxHP by 5

        XCTAssertEqual(applied, 3, "the applied amount must be capped to exactly what HP was missing")
        XCTAssertEqual(player.hp, player.maxHP)
    }

    func test_heal_atExactlyMaxHP_appliesNothing() {
        let player = PlayerNode()
        XCTAssertEqual(player.hp, player.maxHP, "sanity: a fresh player spawns at full HP")

        let applied = player.heal(10)

        XCTAssertEqual(applied, 0)
        XCTAssertEqual(player.hp, player.maxHP)
    }

    // MARK: - Healing is never a back door into the damage path

    func test_heal_ignoresNonPositiveAmounts() {
        let player = PlayerNode()
        player.hp = 40

        XCTAssertEqual(player.heal(0), 0)
        XCTAssertEqual(player.hp, 40)

        XCTAssertEqual(player.heal(-15), 0, "a negative heal must not damage the player -- that is takeDamage(_:)'s job")
        XCTAssertEqual(player.hp, 40)
    }

    // MARK: - The roll-then-apply composition a wiring PR performs

    /// The exact shape the scene-wiring PR runs: roll the med kit's dice
    /// once (as `PickupManager.attemptCollectMedKit` does internally), then
    /// hand that single number to `heal(_:)`. Pins that the *applied*
    /// amount, not the raw roll, is what a capped heal reports.
    func test_medKitRoll_appliedThroughHeal_reportsTheCappedAmount_notTheRawRoll() {
        let player = PlayerNode()
        player.hp = player.maxHP - 3

        // rawValue 7 -> 7 % 10 + 1 == 8, which would overshoot maxHP by 5.
        var rng = ScriptedRandomNumberGenerator(7)
        let roll = PickupKind.medKit.tuning.dice.roll(using: &rng)
        XCTAssertEqual(roll, 8, "sanity: the scripted 1d10 roll is pinned")

        let applied = player.heal(roll)

        XCTAssertEqual(applied, 3)
        XCTAssertEqual(player.hp, player.maxHP)
    }

    func test_medKitRoll_appliedThroughHeal_isAlwaysWithinTheMedKitDiceRange_whenNeverCapped() {
        let player = PlayerNode()
        var rng = SplitMix64RandomNumberGenerator(seed: 99)

        for _ in 0..<200 {
            player.hp = 1 // reset far below max so the roll is never capped
            let applied = player.heal(PickupKind.medKit.tuning.dice.roll(using: &rng))
            XCTAssertTrue(
                PickupKind.medKit.tuning.dice.range.contains(applied),
                "applied amount \(applied) fell outside the med kit's 1d10 range"
            )
        }
    }
}
