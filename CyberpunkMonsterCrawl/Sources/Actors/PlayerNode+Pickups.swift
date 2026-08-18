import Foundation

/// The player's med-kit consumption effect (`CYBERPUN-17-11` PR 2):
/// applies a collected med kit's rolled amount as healing, capped at
/// `maxHP` via `hp`'s own clamping `didSet` (`PlayerNode.swift`'s "Combat
/// state" section -- the same `0...maxHP` invariant `takeDamage(_:)`
/// relies on for damage).
///
/// **One roll per med kit, and `PickupManager` owns it** (PR #37 review).
/// `PickupManager.attemptCollectMedKit(at:radius:)` (PR 1) is what
/// consumes the pickup record *and* rolls `PickupKind.medKit`'s 1d10, so
/// that returned value is the authoritative one and this method simply
/// applies it. An earlier revision of this file rolled a second,
/// independent 1d10 here, which left the wiring PR two numbers -- the one
/// the manager reported and the one the player actually got -- with no way
/// to make both true.
///
/// **Scope of this PR.** This is the consumer-side effect in isolation --
/// nothing here mounts a pickup, detects player/med-kit contact, or
/// removes the collected `Pickup` from `PickupManager.activePickups`. A
/// later scene-wiring PR is what calls
/// `attemptCollectMedKit(at:radius:)` on contact and feeds its result
/// here.
///
/// **Deliberately no shared code with the raccoon's own garbage-can
/// consume effect** (`RaccoonSeekBehavior.swift`) beyond the `PickupKind`
/// tuning table and `DiceSpec.roll(using:)` both read -- per this story's
/// PR2 scope note ("each in its own file with no shared code"), which is
/// about the two *effects*, not about copying one dice roller three times.
extension PlayerNode {

    /// Applies `amount` HP of healing -- typically a med kit's rolled 1d10
    /// from `PickupManager.attemptCollectMedKit(at:radius:)` -- and returns
    /// the amount **actually applied**: strictly less than `amount`
    /// whenever it would have pushed `hp` past `maxHP`, since `hp`'s
    /// `didSet` clamps the write. That returned value, not the raw roll, is
    /// what a HUD or a run-summary counter should report.
    ///
    /// A non-positive `amount` is a no-op returning `0`: healing is not a
    /// back door into the damage path, which is `takeDamage(_:)`'s job.
    @discardableResult
    func heal(_ amount: Int) -> Int {
        guard amount > 0 else { return 0 }
        let before = hp
        hp += amount
        return hp - before
    }
}
