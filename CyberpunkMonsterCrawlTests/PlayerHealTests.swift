import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-11` PR 2: `PlayerNode.collectMedKit(rng:)` -- the med-kit
/// consumption effect (roll 1d10, apply capped at `maxHP`), proven
/// entirely independent of scene/collision wiring per this PR's
/// acceptance criteria.
final class PlayerHealTests: XCTestCase {

    /// A scripted `RandomNumberGenerator` that replays one fixed raw
    /// `UInt64` value forever -- lets a test pin `collectMedKit(rng:)`'s
    /// exact roll (`rawValue % 10 + 1`) rather than only its range, the
    /// same shape `RabiesStatusEffectTests`' own (private, file-local)
    /// `ScriptedRandomNumberGenerator` uses for the same reason.
    private struct ScriptedRandomNumberGenerator: RandomNumberGenerator {
        private let value: UInt64
        init(_ value: UInt64) { self.value = value }
        func next() -> UInt64 { value }
    }

    // MARK: - Far from max HP: the full roll is applied

    func test_collectMedKit_appliesTheFullRoll_whenFarFromMaxHP() {
        let player = PlayerNode()
        player.hp = 10 // far below maxHP (100)

        // rawValue 3 -> 3 % 10 + 1 == 4.
        var rng = ScriptedRandomNumberGenerator(3)
        let applied = player.collectMedKit(rng: &rng)

        XCTAssertEqual(applied, 4)
        XCTAssertEqual(player.hp, 14)
    }

    // MARK: - Near max HP: the roll is capped

    func test_collectMedKit_capsHealing_whenNearMaxHP() {
        let player = PlayerNode()
        player.hp = player.maxHP - 3 // only 3 HP short of max

        // rawValue 7 -> 7 % 10 + 1 == 8, which would overshoot maxHP by 5.
        var rng = ScriptedRandomNumberGenerator(7)
        let applied = player.collectMedKit(rng: &rng)

        XCTAssertEqual(applied, 3, "the applied amount must be capped to exactly what HP was missing")
        XCTAssertEqual(player.hp, player.maxHP)
    }

    func test_collectMedKit_atExactlyMaxHP_appliesNothing() {
        let player = PlayerNode()
        XCTAssertEqual(player.hp, player.maxHP, "sanity: a fresh player spawns at full HP")

        var rng = ScriptedRandomNumberGenerator(9)
        let applied = player.collectMedKit(rng: &rng)

        XCTAssertEqual(applied, 0)
        XCTAssertEqual(player.hp, player.maxHP)
    }

    // MARK: - The applied amount is always within PickupKind.medKit's own dice range

    func test_collectMedKit_appliedAmount_isAlwaysWithinTheMedKitDiceRange_whenNeverCapped() {
        let player = PlayerNode()
        var rng = SplitMix64RandomNumberGenerator(seed: 99)

        for _ in 0..<200 {
            player.hp = 1 // reset far below max so the roll is never capped
            let applied = player.collectMedKit(rng: &rng)
            XCTAssertTrue(
                PickupKind.medKit.tuning.dice.range.contains(applied),
                "applied amount \(applied) fell outside the med kit's 1d10 range"
            )
        }
    }
}
