import Foundation

/// The player's med-kit consumption effect (`CYBERPUN-17-11` PR 2): rolls
/// `PickupKind.medKit`'s dice (1d10, from PR 1) and applies the result as
/// healing, capped at `maxHP` via `hp`'s own clamping `didSet`
/// (`PlayerNode.swift`'s "Combat state" section -- the same `0...maxHP`
/// invariant `takeDamage(_:)` relies on for damage).
///
/// **Scope of this PR.** This is the consumer-side effect in isolation --
/// nothing here mounts a pickup, detects player/med-kit contact, or removes
/// the collected `Pickup` from `PickupManager.activePickups`. `PickupManager
/// .attemptCollectMedKit` (PR 1) already reports a rolled value and
/// consumes the pickup record; this method deliberately rolls its *own*
/// independent 1d10 rather than taking that value as a parameter, so it can
/// be proven correct (roll, then cap) entirely on its own, the same
/// "in isolation from GameScene" bar this story's PR2 acceptance criteria
/// set. A later scene-wiring PR is what actually calls this on contact.
///
/// **Deliberately no shared code with the raccoon's own garbage-can consume
/// effect** (`RaccoonSeekBehavior.swift`) beyond the `PickupKind` tuning
/// table both read -- per this story's PR2 scope note ("each in its own
/// file with no shared code").
extension PlayerNode {

    /// Rolls `PickupKind.medKit.tuning.dice` (1d10) via `rng` and applies
    /// the result as healing, returning the amount **actually applied** --
    /// strictly less than the raw roll whenever it would have pushed `hp`
    /// past `maxHP`, since `hp`'s `didSet` clamps the write.
    ///
    /// `rng` is generic and taken by `inout`, the same shape
    /// `RabiesStatusEffect.rollInfects(tier:rng:)` and
    /// `RaccoonSpawnDirector.selectTier(rng:)` already use, so a test can
    /// pin the exact roll with a scripted generator without any live
    /// pickup, scene, or collision. The roll itself uses the same raw
    /// `next() % sides` mapping `RabiesStatusEffect.rollInfects` documents
    /// choosing over `Int.random(in:using:)`: an exact, hand-computable
    /// result from a known raw generator value, rather than the stdlib's
    /// unexposed rejection-sampling internals.
    @discardableResult
    func collectMedKit<R: RandomNumberGenerator>(rng: inout R) -> Int {
        let roll = Self.rollDice(PickupKind.medKit.tuning.dice, rng: &rng)
        let before = hp
        hp += roll
        return hp - before
    }

    /// Sums `dice.count` dice of `dice.sides` faces each, via the raw
    /// `next() % sides + 1` mapping described above.
    private static func rollDice<R: RandomNumberGenerator>(_ dice: DiceSpec, rng: inout R) -> Int {
        var total = 0
        for _ in 0..<dice.count {
            total += Int(rng.next() % UInt64(dice.sides)) + 1
        }
        return total
    }
}
