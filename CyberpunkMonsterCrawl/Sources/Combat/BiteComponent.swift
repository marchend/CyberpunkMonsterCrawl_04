import CoreGraphics
import Foundation

/// The on-contact bite trigger (`CYBERPUN-17-8` PR 3): turns "a raccoon is
/// in contact with the player" into a concrete attack-animation + damage +
/// rabies-roll event, at a fixed cadence rather than every single frame
/// contact holds.
///
/// **Who determines "contact".** `isInContact(raccoonPosition:
/// playerPosition:tier:)` below, from the same
/// `RaccoonSeekBehavior.contactStandoffPoints(forTier:)` ring the swarm
/// already settles on. `update(...)` itself carries no positional logic --
/// a caller drives it only on frames where that predicate held.
///
/// **The production caller.** `RaccoonSpawnDirector` owns one instance of
/// this per live raccoon (see "One instance per raccoon" below) and drives
/// it from its own per-frame loop, which already has each raccoon's
/// resolved tile position and the player's; `GameScene
/// .advanceMovementAndCamera(currentTime:)` passes the mounted
/// `PlayerNode` in, inside the existing `stateMachine.currentState ==
/// .gameplay` gate. Review of PR #34 caught that this file previously had
/// *no* production caller at all -- nothing in a device build could bite,
/// which is the shape of feature that never gets switched on, so the
/// contact check landed here rather than being deferred.
///
/// **One instance per raccoon.** Each raccoon needs its own bite cadence
/// independent of every other raccoon biting the same player, so
/// `RaccoonSpawnDirector` builds one `BiteComponent` per live raccoon (in
/// its `ActiveRaccoon` record, retired with the raccoon) rather than
/// sharing a single instance across the swarm.
final class BiteComponent {

    /// Seconds between successive bites from one raccoon while contact is
    /// sustained -- "guards against re-triggering every frame", per the
    /// story. An initial tuning constant, expected to move in a later
    /// playtesting pass like the rest of this story's combat numbers.
    static let biteIntervalSeconds: TimeInterval = 1.0

    /// Direct HP damage one bite deals to the player, independent of the
    /// separate rabies DoT. An initial tuning constant.
    static let biteDamage: Int = 5

    /// On-screen slack (points) added to the standoff ring when deciding
    /// contact. `RaccoonSeekBehavior.tileDisplacement` clamps a raccoon's
    /// step so it settles at *exactly*
    /// `contactStandoffPoints(forTier:)` -- the distance at which the two
    /// ground footprints touch -- so a strict `<` comparison would depend
    /// on the sign of the last floating-point rounding in that clamp for
    /// whether the swarm ever bites at all. One point is smaller than a
    /// device pixel at `@2x`/`@3x` and far smaller than a single frame's
    /// travel (`RaccoonSeekBehavior.pointsPerSecond` is in the hundreds),
    /// so it widens the ring by nothing a player could perceive.
    static let contactSlackPoints: Double = 1.0

    /// Whether a raccoon of `tier` standing at tile `raccoonPosition` is
    /// touching a player at tile `playerPosition`: their **screen**-space
    /// distance is within `RaccoonSeekBehavior.contactStandoffPoints(
    /// forTier:)` (plus `contactSlackPoints`) -- the same ring
    /// `RaccoonSeekBehavior` steers the swarm onto, so "close enough to
    /// stop walking" and "close enough to bite" are one number rather than
    /// two that can drift apart.
    ///
    /// Screen space (not tile distance) because the standoff itself is
    /// measured in points off the shipped art, and this 2:1 isometric
    /// projection makes a fixed tile radius a different on-screen distance
    /// per heading.
    ///
    /// A pure `static` function so tests can pin the threshold without a
    /// live scene, the same shape `RaccoonSpawnDirector.isOnScreen(tile:
    /// cameraPosition:viewportSize:)` uses.
    static func isInContact(
        raccoonPosition: TilePoint,
        playerPosition: TilePoint,
        tier: RaccoonTier
    ) -> Bool {
        let raccoonScreen = IsometricProjection.tileToScreen(raccoonPosition)
        let playerScreen = IsometricProjection.tileToScreen(playerPosition)
        let distance = hypot(
            Double(raccoonScreen.x - playerScreen.x),
            Double(raccoonScreen.y - playerScreen.y)
        )
        return distance <= RaccoonSeekBehavior.contactStandoffPoints(forTier: tier) + contactSlackPoints
    }

    private let stats: RunSummaryStats

    /// Seconds elapsed since this raccoon's last bite. Starts at
    /// `biteIntervalSeconds` so the very first frame contact is observed
    /// bites immediately, rather than waiting out a full cooldown before
    /// the first hit lands.
    private var elapsedSinceLastBite: TimeInterval

    /// - Parameter stats: the run's counters a successful rabies roll
    ///   records a new infection into.
    init(stats: RunSummaryStats) {
        self.stats = stats
        self.elapsedSinceLastBite = Self.biteIntervalSeconds
    }

    /// Advances this bite's cooldown by `deltaTime` and, once
    /// `biteIntervalSeconds` has elapsed since the last bite, triggers one
    /// bite: `raccoon.playAttack()` (12 fps attack animation, per
    /// `RaccoonAnimationController.attackFramesPerSecond`), direct damage
    /// to `player`, and a `RabiesStatusEffect` roll against
    /// `raccoon.tier` that infects `player` on success.
    ///
    /// A no-op while the cooldown has not yet elapsed -- this is what
    /// stops a bite (and its damage) firing every single frame contact is
    /// sustained -- and while `deltaTime <= 0`.
    func update<R: RandomNumberGenerator>(
        raccoon: RaccoonNode,
        player: PlayerNode,
        deltaTime: TimeInterval,
        rng: inout R
    ) {
        guard deltaTime > 0 else { return }
        elapsedSinceLastBite += deltaTime
        guard elapsedSinceLastBite >= Self.biteIntervalSeconds else { return }
        elapsedSinceLastBite = 0

        raccoon.playAttack()
        player.takeDamage(Self.biteDamage)

        if RabiesStatusEffect.rollInfects(tier: raccoon.tier, rng: &rng) {
            player.infect(stats: stats)
        }
    }
}
