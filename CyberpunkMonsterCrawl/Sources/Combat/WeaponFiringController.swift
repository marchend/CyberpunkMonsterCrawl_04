import Foundation

/// The "when and at whom to fire" decision layer (`CYBERPUN-17-9` PR 1):
/// owns the fire-rate cooldown, gates firing on the movement flag
/// (`PlayerMovementController.isMoving`, from `CYBERPUN-17-7`) plus a
/// valid in-range target (`TargetSelection.nearestLivingTarget`), and
/// hands the decision off through an injected closure rather than
/// spawning anything itself.
///
/// **Scope of this PR.** Decision only \u2014 no rendering, no bullet
/// spawning, no SpriteKit dependency. `onFire` is the seam the story's own
/// PR 3 (the end-to-end wiring PR named in this story's plan) hooks up to
/// an actual bullet/hit-puff spawn; a caller that never sets it (every
/// test predating that PR) simply never observes a fire decision anywhere
/// beyond this type's own state.
final class WeaponFiringController {

    /// This controller's current weapon tier \u2014 set at construction,
    /// swappable in place via `setTier(_:)` without resetting the
    /// in-flight cooldown.
    private(set) var tier: WeaponTier

    /// Seconds remaining before the next shot may fire. Starts at `0` so a
    /// freshly-built controller is ready to fire on its very first
    /// qualifying frame, rather than waiting out a full cooldown first \u2014
    /// the same "ready immediately" convention `BiteComponent` follows
    /// (that type starts its own *elapsed* clock already at the interval,
    /// the inverse representation for the same reason).
    ///
    /// Ticks down every frame regardless of the movement gate: only the
    /// *fire* decision below is gated on `isMoving`, so stopping and
    /// restarting movement can never "bank" extra cooldown progress, and
    /// resuming movement fires again exactly when the real-time cooldown
    /// has elapsed \u2014 not instantly, and not later than that.
    private var cooldownRemaining: TimeInterval = 0

    /// Invoked exactly once per shot, the instant the movement gate, the
    /// cooldown, and a valid in-range target all hold on the same frame.
    /// `nil` by default, so a controller built for a test that only cares
    /// about gating/cooldown behaviour needs no closure at all.
    var onFire: ((_ target: RaccoonNode, _ origin: TilePoint, _ tier: WeaponTier) -> Void)?

    /// - Parameters:
    ///   - tier: the initial weapon tier.
    ///   - onFire: see `onFire`'s own doc comment. Defaults to `nil`.
    init(tier: WeaponTier, onFire: ((RaccoonNode, TilePoint, WeaponTier) -> Void)? = nil) {
        self.tier = tier
        self.onFire = onFire
    }

    /// Advances this controller by one frame: counts the cooldown down by
    /// `deltaTime`, then \u2014 only while `isMoving` is `true` and the cooldown
    /// has fully elapsed \u2014 selects the nearest living raccoon within this
    /// tier's range from `origin` (`TargetSelection.nearestLivingTarget`)
    /// and, if one exists, fires: invokes `onFire` and resets the cooldown
    /// to `tier.fireIntervalSeconds`.
    ///
    /// A complete no-op on `deltaTime <= 0`, matching every other
    /// per-frame update in this codebase (`RaccoonSeekBehavior`,
    /// `BiteComponent`).
    ///
    /// **Standing still stops fire, but does not "save up" cooldown.** The
    /// cooldown clock still ticks down every frame regardless of
    /// `isMoving` \u2014 only the fire itself is gated \u2014 so a player who
    /// stands still through part (or all) of a cooldown simply sees that
    /// time pass; there is no bonus shot waiting the instant they move
    /// again beyond what a normal cooldown would already allow.
    func update(
        deltaTime: TimeInterval,
        isMoving: Bool,
        origin: TilePoint,
        raccoons: [TargetSelection.Candidate]
    ) {
        guard deltaTime > 0 else { return }
        cooldownRemaining = max(0, cooldownRemaining - deltaTime)

        guard isMoving, cooldownRemaining <= 0 else { return }

        guard let target = TargetSelection.nearestLivingTarget(
            from: origin,
            raccoons: raccoons,
            maxRange: tier.rangeTiles
        ) else { return }

        cooldownRemaining = tier.fireIntervalSeconds
        onFire?(target, origin, tier)
    }

    /// Swaps this controller's tier in place \u2014 fire rate/range/damage
    /// change immediately for every future `update(...)` call \u2014 **without**
    /// touching `cooldownRemaining`. The in-flight cooldown keeps counting
    /// down exactly where it was; only the *next* shot (and every one
    /// after) fires at the new tier's rate. Matches the story's own
    /// wording: "swaps tier config in place without resetting the
    /// in-flight cooldown."
    func setTier(_ newTier: WeaponTier) {
        tier = newTier
    }
}
