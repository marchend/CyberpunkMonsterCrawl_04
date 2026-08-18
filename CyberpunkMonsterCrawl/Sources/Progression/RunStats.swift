import Foundation

/// The player's own weapon-combat counters -- cumulative damage dealt and
/// raccoons killed by gunfire (`CYBERPUN-17-9` PR 3).
///
/// **Not the same counter as `RunSummaryStats.killCount`.** `RunSummaryStats`
/// (`CYBERPUN-17-8` PR 3) already tracks a scene-wide `killCount` fed by
/// *every* raccoon death `GameScene` mounts, regardless of cause, plus
/// `timesInfected` -- it is what a future death-screen summary
/// (`CYBERPUN-17-13`) reads. `RunStats` is `Player`'s own composed
/// bookkeeping (this same PR) for the two numbers its bullet-hit
/// resolution alone produces (`damageDealt`, and its own `killCount` for a
/// gunfire kill specifically): the two types are deliberately not merged
/// here, since `Player` is not itself wired into `GameScene` by this PR
/// (see `Player`'s own doc comment) and so has no reference to
/// `GameScene.runStats` to write into. A later integration task that mounts
/// `Player` onto the live game is the right place to decide whether
/// `Player.runStats.recordKill()` should also forward into
/// `RunSummaryStats.recordKill()`, or whether one of the two counters is
/// retired in favour of the other.
final class RunStats {

    /// Cumulative HP damage this player's shots have dealt this run.
    private(set) var damageDealt: Int = 0

    /// Cumulative raccoons killed by this player's shots this run.
    private(set) var killCount: Int = 0

    /// Records `amount` HP of damage dealt. A non-positive `amount` is a
    /// no-op: damage is not a back door for decrementing the counter, the
    /// same "guard before mutating" shape `PlayerNode+Pickups.heal(_:)`
    /// uses for healing.
    func recordDamage(_ amount: Int) {
        guard amount > 0 else { return }
        damageDealt += amount
    }

    /// Records one kill.
    func recordKill() {
        killCount += 1
    }

    /// Zeroes both counters for a fresh run. `Player.reset()` calls this on
    /// every fresh `.gameplay` entry, the same reason
    /// `RunSummaryStats.reset()` / `RaccoonSpawnDirector.reset()` exist:
    /// without it, RUN AGAIN would report the previous run's damage/kills.
    func reset() {
        damageDealt = 0
        killCount = 0
    }
}
