import Foundation

/// The on-contact bite trigger (`CYBERPUN-17-8` PR 3): turns "a raccoon is
/// in contact with the player" into a concrete attack-animation + damage +
/// rabies-roll event, at a fixed cadence rather than every single frame
/// contact holds.
///
/// **Who determines "contact".** This type has no positional/collision
/// logic of its own -- it does not touch `RaccoonSeekBehavior` or
/// `BuildingAvoidance` (PR 2's files, left unmodified by this PR). A
/// caller drives `update(...)` only on frames where it has already decided
/// the raccoon and player are in contact, e.g. by comparing their
/// tile/screen-space distance against `RaccoonSeekBehavior
/// .contactStandoffPoints(forTier:)` -- the exact public seam that
/// constant already exists for. Wiring that per-frame contact check into
/// the live scene loop (`GameScene`) is scene-integration work for a later
/// PR in this story (see the `CYBERPUN-17-8` entry in AGENT.md/CLAUDE.md
/// for what remains outstanding); this PR ships the bite trigger itself,
/// fully unit-tested against the two collaborators it does own
/// (`RaccoonNode`/`PlayerNode`).
///
/// **One instance per raccoon.** Each raccoon needs its own bite cadence
/// independent of every other raccoon biting the same player, so a caller
/// (a later PR's per-raccoon bookkeeping) owns one `BiteComponent` per
/// live raccoon rather than sharing a single instance across the swarm.
final class BiteComponent {

    /// Seconds between successive bites from one raccoon while contact is
    /// sustained -- "guards against re-triggering every frame", per the
    /// story. An initial tuning constant, expected to move in a later
    /// playtesting pass like the rest of this story's combat numbers.
    static let biteIntervalSeconds: TimeInterval = 1.0

    /// Direct HP damage one bite deals to the player, independent of the
    /// separate rabies DoT. An initial tuning constant.
    static let biteDamage: Int = 5

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
