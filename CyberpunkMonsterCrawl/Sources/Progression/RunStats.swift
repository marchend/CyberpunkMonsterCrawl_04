import Foundation

/// The player's own weapon-combat counters -- cumulative damage dealt and
/// raccoons killed by gunfire (`CYBERPUN-17-9` PR 3).
///
/// **Not the same counter as `RunSummaryStats.killCount`, and
/// `RunSummaryStats` is the authoritative one for the run summary.** That
/// decision is made here rather than deferred, now that `GameScene`
/// mounts `Player` (`startPlayer(at:)`) and drives it every frame:
///
/// - `RunSummaryStats.killCount` (`CYBERPUN-17-8` PR 3) counts **every**
///   raccoon death in the run, whatever killed it, because
///   `RaccoonNode.die()` increments the `runStats` instance
///   `RaccoonSpawnDirector.spawnRaccoon` injects into every raccoon it
///   mounts. It is the counter the death-screen summary
///   (`CYBERPUN-17-13`) reads, and the only one that stays correct if a
///   later story adds a second way to kill a raccoon.
/// - `RunStats` (this type) is the weapon system's own bookkeeping: the
///   two numbers `Player`'s bullet-hit resolution alone produces --
///   cumulative `damageDealt`, and a `killCount` restricted to kills
///   *this player's gunfire* caused. It answers "how did the weapon
///   perform", not "how did the run go", and nothing outside `Player`
///   reads it today.
///
/// A gunfire kill therefore increments both counters, deliberately: they
/// are different questions, not a double count of the same one. `Player`
/// does **not** forward `recordKill()` into `RunSummaryStats` -- that
/// would double-count every gunfire kill in the summary, since `die()`
/// has already recorded it -- and neither counter is retired, because
/// `damageDealt` has no home in `RunSummaryStats` and cause-attributed
/// kills have no home outside the weapon system.
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
