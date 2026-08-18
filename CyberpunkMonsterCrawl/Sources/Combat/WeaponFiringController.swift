import Foundation

/// The "when and at whom to fire" decision layer (`CYBERPUN-17-9` PR 1):
/// owns the fire-rate cooldown, gates firing on the movement flag
/// (`PlayerMovementController.isMoving`, from `CYBERPUN-17-7`) plus a
/// valid in-range target (`TargetSelection.nearestLivingTarget`), and
/// hands the decision off through an injected closure rather than
/// spawning anything itself.
///
/// **Scope of this PR.** Decision only \u2014 no rendering, no bullet
/// spawning, no SpriteKit dependency. `onFire` is the seam the story's
/// later end-to-end wiring PR hooks up to an actual bullet/hit-puff spawn;
/// a caller that never sets it (every test predating that PR) simply never
/// observes a fire decision anywhere beyond this type's own state.
///
/// **Why this slice lands with no production caller \u2014 and what that
/// costs.** Nothing in this PR constructs a `WeaponFiringController`:
/// `GameScene` is untouched, so on a device build no shot is decided and
/// no `WeaponTier` constant is read. That is the same shape PR #34 review
/// rejected for `BiteComponent` ("nothing in a device build could bite,
/// which is the shape of feature that never gets switched on") and that
/// `GroundTileRenderer`'s doc states as a repo rule. The difference here is
/// what a caller would need: this type's `raccoons` argument is a
/// per-frame `[TargetSelection.Candidate]` built from
/// `RaccoonSpawnDirector`'s live swarm, whose `ActiveRaccoon` bookkeeping
/// is still `private` to that type and still owned by the raccoon-swarm
/// story \u2014 so wiring a real caller now means either widening that type's
/// API or duplicating its swarm tracking, both of which the swarm story
/// would immediately have to undo. Mounting the shot itself additionally
/// needs the held-weapon overlay (`sprite_player_weapons`) that no PR has
/// mounted yet.
///
/// The consequence is recorded rather than hidden: until that wiring PR
/// lands, auto-fire is dead code in a real run \u2014 the swarm cannot be shot,
/// `RaccoonNode.onDeath` stays unset, and the suite stays green only
/// because every test injects its own `onFire`. The follow-up is tracked
/// under this story (`CYBERPUN-17-9`); no separate ticket ID is cited here
/// because none has been filed, and this codebase does not reference
/// invented ticket IDs.
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
    ///
    /// The target arrives as the whole `TargetSelection.Candidate` \u2014 node
    /// *and* its tile-space position \u2014 not the bare `RaccoonNode`, since
    /// `RaccoonNode` carries no position of its own. A consumer needs both
    /// ends of the shot to compute the shot vector (bullets are authored
    /// pointing screen-right and are drawn rotated to it) and to place the
    /// muzzle flash, so the target position travels with the decision
    /// rather than forcing the consumer to re-scan its candidate array by
    /// `===` to recover a position this type had already computed.
    var onFire: ((_ target: TargetSelection.Candidate, _ origin: TilePoint, _ tier: WeaponTier) -> Void)?

    /// - Parameters:
    ///   - tier: the initial weapon tier.
    ///   - onFire: see `onFire`'s own doc comment. Defaults to `nil`.
    init(tier: WeaponTier, onFire: ((TargetSelection.Candidate, TilePoint, WeaponTier) -> Void)? = nil) {
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
