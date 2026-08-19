import CoreGraphics
import Foundation

/// The player-triggered pulse ability's pure gameplay logic
/// (`CYBERPUN-17-10` PR 1): push geometry, crush/footprint clamping,
/// damage rolls and cooldown gating -- entirely independent of SpriteKit,
/// the HUD pulse button and its cooldown indicator, and the
/// `sprite_pulse` ring animation. All three of those are later PRs in
/// this story; this type is the decision layer they will drive, the same
/// split `WeaponFiringController`/`TargetSelection` already establish for
/// the auto-fire weapon (decide, then let a wiring PR render/apply).
///
/// **Why `trigger(...)` returns data instead of mutating `RaccoonNode`
/// directly.** `RaccoonNode.takeDamage(_:)` already owns clamping/death,
/// and a raccoon's tile-space position is tracked externally by whichever
/// system steers it (`RaccoonSeekBehavior`'s and `TargetSelection`'s own
/// doc comments both make this point) -- `RaccoonNode` itself carries no
/// position. So, exactly like `WeaponFiringController.onFire`, this type
/// only *decides*: it hands back each hit raccoon's new tile-space
/// position and the damage it took, and a later scene-wiring PR applies
/// both (`raccoon.takeDamage(hit.damage)`, plus whatever external
/// position store the caller keeps).
///
/// **A class, not an enum namespace** -- like `WeaponFiringController` and
/// `BiteComponent`, and unlike the stateless `TargetSelection`/
/// `CollisionResolver` -- because a cooldown is inherently per-instance
/// state carried across calls. One instance per player, matching "the
/// player has exactly one pulse ability" (unlike `BiteComponent`, which
/// the swarm story gives one instance *per raccoon*).
///
/// **Cooldown as a per-frame countdown, not a last-fire timestamp.**
/// `WeaponFiringController.cooldownRemaining` and
/// `BiteComponent.elapsedSinceLastBite` both tick a stored
/// `TimeInterval` down/up via an `update(deltaTime:)` call rather than
/// comparing a fire timestamp against a clock reading, so a test never
/// has to fabricate two `Date`/`TimeInterval` readings that are
/// "sufficiently far apart" -- it just calls `update(deltaTime:)` with
/// however much time it wants to simulate. `PulseAbility` follows the
/// same convention: `cooldownRemaining` starts at `0` (ready
/// immediately, the same "no waiting out a cooldown before the very
/// first shot" convention `WeaponFiringController` documents), ticks
/// down in `update(deltaTime:)`, and `trigger(...)` is gated on it
/// reading `<= 0`.
///
/// **Crush detection reuses `CollisionResolver`, never reimplements
/// it.** A push is modelled as `CollisionResolver.resolve(currentPosition
/// :proposedDelta:obstructions:)` moving the raccoon (not the player)
/// from its current tile position by the vector to its intended push
/// target. `CollisionResolver` already guarantees flat-footprint-only
/// collision (never building height), a clamp that lands exactly on the
/// blocking footprint's edge (never inside it), and identical behaviour
/// for two placements that share a footprint no matter which of the 12
/// catalog sprites -- and therefore which height class -- either one is.
/// This type adds nothing to that contract beyond scoring the *resolved*
/// position against the pulse radius and rolling a second damage die for
/// a raccoon still inside it.
///
/// **"Crushed" means still inside the radius, not "short of the push
/// target".** `CollisionResolver.resolve` is deliberately a per-axis
/// slide ("The slide, not a stop"): it clamps one axis and lets the
/// other complete, so a raccoon deflected along a footprint's edge ends
/// up somewhere other than its full push target while *still being
/// shoved clear of the blast*. Scoring that raccoon as crushed would
/// hand it a second die it did not earn, so the flag is derived from the
/// story's own wording -- "cannot be pushed clear of the radius because
/// a building footprint blocks its path" -- as a plain distance check on
/// the resolved position.
///
/// **Known consequence: a raccoon that starts *inside* a footprint is
/// pushed straight through it.** `CollisionResolver` deliberately skips
/// any obstruction that already contains the starting point ("An illegal
/// starting position ejects forwards, never backwards"), so a raccoon
/// streamed in on top of a building is not clamped by that building: it
/// completes the full push and takes a single die. That is the
/// resolver's contract working as designed rather than a gap here --
/// deciding where such an actor belongs is spawn-safety policy, owned by
/// the wiring PR that places actors -- but it is recorded here so the
/// behaviour reads as known rather than accidental.
final class PulseAbility {

    /// Seconds a fresh `PulseAbility` must wait after a trigger before its
    /// next one is accepted -- the named constant the story calls for
    /// ("short, tuned in playtesting, exposed as a named constant, so the
    /// pulse reads as a deliberate ability, not a second fire button"). An
    /// initial tuning constant, like every other per-ability cooldown in
    /// this codebase (`WeaponTier.fireIntervalSeconds`,
    /// `BiteComponent.biteIntervalSeconds`); expected to move in a later
    /// playtesting pass.
    static let cooldownSeconds: TimeInterval = 4.0

    /// The pulse's tile-space radius at level 0 (before any level-scaling
    /// multiplier is applied) -- an initial tuning constant, the same
    /// "expected to move in a later playtesting pass" status every other
    /// combat radius/range constant in this codebase carries
    /// (`WeaponTier.rangeTiles`, `RaccoonSeekBehavior
    /// .contactStandoffPoints(forTier:)`).
    static let baseRadiusTiles: Double = 3.0

    /// How far past the pulse radius's edge a fully-clear push lands a
    /// raccoon, in tile units -- the story's own "shoved outward to
    /// (just past) the radius edge" wording. Kept far smaller than a
    /// single tile so "just past the edge" reads as intended rather than
    /// as an extra half-tile of unexplained knockback.
    static let pushOvershootEpsilon: Double = 0.05

    /// One raccoon's outcome from a single `trigger(...)` call: its
    /// resolved tile-space position after the push (and, for a crushed
    /// raccoon, the footprint-clamped position rather than the full push
    /// target) and the total damage it took.
    struct Hit {
        /// The raccoon this hit applies to. Carried alongside the
        /// position/damage (rather than left for the caller to re-derive
        /// by scanning its own swarm) for the same reason
        /// `TargetSelection.Candidate` and `WeaponFiringController.onFire`
        /// both hand back the node itself: a consumer needs both ends of
        /// the interaction and re-scanning by `===` risks picking the
        /// wrong entry if the same node ever appears twice.
        let raccoon: RaccoonNode
        /// This raccoon's tile-space position after the push: at
        /// (radius + `pushOvershootEpsilon`) tile units from the player
        /// along the ray from the player through the raccoon's *original*
        /// position, or the position `CollisionResolver` clamped it to if
        /// a building stood in the way. A clamped position need not sit on
        /// that ray: the resolver slides per axis, so a deflected raccoon
        /// can come to rest off the original bearing.
        let newPosition: TilePoint
        /// Total damage this raccoon took: one roll of the level-scaled
        /// damage die for a clear push, two rolls (summed) if the push was
        /// crushed against a footprint.
        let damage: Int
        /// Whether this raccoon ended the push *still inside the pulse
        /// radius* because a building footprint blocked its path --
        /// exactly the raccoons that took the second damage roll. A
        /// raccoon merely deflected along a footprint's edge but still
        /// shoved clear of the radius reads `false`. Exposed so a later
        /// rendering PR can choose a distinct hit-effect for a crush
        /// without recomputing the check itself.
        let wasCrushed: Bool
    }

    /// The full outcome of one `trigger(...)` call that was not rejected
    /// by the cooldown gate: the radius the pulse fired at (level-scaled,
    /// so a rendering PR can size the `sprite_pulse` ring to match without
    /// re-deriving `LevelScaling.pulseRadiusMultiplier(forLevel:)` itself)
    /// and every living, in-radius raccoon's push outcome. `hits` is empty
    /// -- not `nil` -- when no raccoon was in range: the pulse still
    /// fired (the ring should still play), it simply pushed nobody.
    struct Result {
        let radius: Double
        let hits: [Hit]
    }

    /// Seconds remaining before `trigger(...)` will accept another press.
    /// Starts at `0` -- see this type's "ready immediately" note.
    private(set) var cooldownRemaining: TimeInterval = 0

    /// Whether a `trigger(...)` call right now would be rejected by the
    /// cooldown gate. Exposed so a later HUD PR can drive the pulse
    /// button's cooldown visual without reaching into `cooldownRemaining`
    /// and reimplementing this comparison.
    var isOnCooldown: Bool { cooldownRemaining > 0 }

    init() {}

    /// Counts the cooldown down by `deltaTime`. A complete no-op on
    /// `deltaTime <= 0`, matching every other per-frame update in this
    /// codebase (`WeaponFiringController.update`,
    /// `RaccoonSeekBehavior.update`, `BiteComponent.update`).
    func update(deltaTime: TimeInterval) {
        guard deltaTime > 0 else { return }
        cooldownRemaining = max(0, cooldownRemaining - deltaTime)
    }

    /// Clears the cooldown so the next `trigger(...)` is accepted
    /// immediately -- the "ready immediately" state a freshly constructed
    /// instance starts in, restored.
    ///
    /// `GameScene.updateWorldContent(for:)` calls this on every fresh entry
    /// to `.gameplay`, alongside `raccoonSpawnDirector.reset()` /
    /// `startPickups()` / `runStats.reset()` / `startPlayer(at:)`. Without
    /// it a run that ended mid-cooldown starts the *next* run with up to
    /// `cooldownSeconds` already burned, and the player's first RUN AGAIN
    /// press does nothing -- indistinguishable from a dropped input, which
    /// is the precise failure this ability's "must respond to every press"
    /// product gate is about (PR #48 review). The auto-fire weapon can
    /// carry its cooldown across a run invisibly because nobody presses
    /// anything for it; a button cannot.
    func reset() {
        cooldownRemaining = 0
    }

    /// Fires the pulse from `playerPosition` at `level`'s scaled
    /// radius/damage die, against every candidate in `raccoons`, with
    /// `obstructions` as the only footprint data consulted (flat
    /// diamonds -- see this type's own doc comment on why building height
    /// never enters the computation).
    ///
    /// Returns `nil` -- emitting nothing, damaging nobody, pushing
    /// nobody -- while `isOnCooldown` holds. Otherwise resets the
    /// cooldown to `PulseAbility.cooldownSeconds` and returns a `Result`,
    /// even when `raccoons` yields no in-radius living candidate (see
    /// `Result.hits`'s own doc comment).
    ///
    /// Dead raccoons (`RaccoonNode.isDead`) are filtered out before any
    /// distance/push computation runs at all, so a dead raccoon can never
    /// appear in the returned `hits`, take damage, or be moved -- the
    /// same "filtered before any real work" shape
    /// `TargetSelection.nearestLivingTarget` uses.
    @discardableResult
    func trigger<R: RandomNumberGenerator>(
        playerPosition: TilePoint,
        level: Int,
        raccoons: [TargetSelection.Candidate],
        obstructions: [CollisionResolver.FootprintBounds],
        rng: inout R
    ) -> Result? {
        guard !isOnCooldown else { return nil }

        let radius = Self.baseRadiusTiles * LevelScaling.pulseRadiusMultiplier(forLevel: level)
        let damageDie = LevelScaling.pulseDamageDie(forLevel: level)

        var hits: [Hit] = []
        for candidate in raccoons {
            guard !candidate.raccoon.isDead else { continue }

            let distance = Self.tileDistance(playerPosition, candidate.position)
            guard distance < radius else { continue }

            let target = Self.pushTarget(
                playerPosition: playerPosition,
                raccoonPosition: candidate.position,
                radius: radius,
                epsilon: Self.pushOvershootEpsilon
            )

            let proposedDelta = CGVector(
                dx: CGFloat(target.x - candidate.position.x),
                dy: CGFloat(target.y - candidate.position.y)
            )
            let resolved = CollisionResolver.resolve(
                currentPosition: candidate.position,
                proposedDelta: proposedDelta,
                obstructions: obstructions
            )

            // "Crushed" is the story's own criterion -- the raccoon
            // *could not be pushed clear of the radius* -- not the much
            // broader "the resolver landed it somewhere other than the
            // full push target". `CollisionResolver.resolve` is a
            // per-axis *slide*: it routinely clamps one axis while the
            // other completes, which leaves a raccoon short of `target`
            // yet still outside the radius (a glancing deflection off a
            // footprint corner). Measuring the *resolved* position
            // against the radius scores exactly the raccoons a building
            // actually pinned inside the blast, and needs no
            // floating-point tolerance: a push that completes lands at
            // `radius + pushOvershootEpsilon`, a whole epsilon clear of
            // this comparison.
            let wasCrushed = Self.tileDistance(playerPosition, resolved) < radius
            var damage = damageDie.roll(using: &rng)
            if wasCrushed {
                damage += damageDie.roll(using: &rng)
            }

            hits.append(Hit(raccoon: candidate.raccoon, newPosition: resolved, damage: damage, wasCrushed: wasCrushed))
        }

        cooldownRemaining = Self.cooldownSeconds
        return Result(radius: radius, hits: hits)
    }

    /// The tile-space position a raccoon currently at `raccoonPosition`
    /// should be pushed to: along the ray from `playerPosition` through
    /// `raccoonPosition` (so the raccoon's bearing from the player is
    /// preserved exactly), at distance `radius + epsilon` from
    /// `playerPosition`.
    ///
    /// Exposed (`static`, not private) so `PulseAbilityTests` can pin the
    /// push geometry directly, independent of damage rolls, cooldown
    /// gating or footprint clamping -- the same "expose the pure
    /// sub-computation for its own test" shape `RaccoonSeekBehavior
    /// .seekVector` and `BiteComponent.isInContact` use.
    ///
    /// A raccoon standing exactly on the player's own tile has no defined
    /// ray direction; rather than divide by zero, this degenerate input
    /// returns `raccoonPosition` unchanged. Production never reaches this
    /// branch -- `RaccoonSeekBehavior.contactStandoffPoints(forTier:)`
    /// keeps every raccoon off the player's exact tile -- but a pure
    /// function should still be total rather than trap on an input a
    /// caller could construct.
    static func pushTarget(
        playerPosition: TilePoint,
        raccoonPosition: TilePoint,
        radius: Double,
        epsilon: Double
    ) -> TilePoint {
        let dx = raccoonPosition.x - playerPosition.x
        let dy = raccoonPosition.y - playerPosition.y
        let distance = hypot(dx, dy)
        guard distance > 0 else { return raccoonPosition }

        let scale = (radius + epsilon) / distance
        return TilePoint(x: playerPosition.x + dx * scale, y: playerPosition.y + dy * scale)
    }

    /// Plain tile-space Euclidean distance, matching `TargetSelection`'s
    /// own private helper of the same shape.
    private static func tileDistance(_ a: TilePoint, _ b: TilePoint) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }

}
