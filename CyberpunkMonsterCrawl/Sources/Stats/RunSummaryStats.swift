import Foundation

/// Run-level counters exposed for the death-screen run summary
/// (`CYBERPUN-17-13`, a later PR) and any other later consumer --
/// incremented from the systems that observe the underlying events as they
/// happen, never recomputed after the fact from scene state (a raccoon
/// that has died is gone from the scene graph by the time a summary
/// screen could inspect it).
///
/// **Scope of this PR (`CYBERPUN-17-8` PR 3).** Only the two counters this
/// PR's own systems produce:
/// - `timesInfected`, incremented by `PlayerNode.infect(stats:)` the
///   moment a **new** rabies infection starts (`RabiesStatusEffect`'s d20
///   roll succeeding while the player was not already infected) -- never
///   once per DoT tick.
/// - `killCount`, incremented by `RaccoonNode+Combat.swift`'s `die()` once
///   per raccoon death.
///
/// Later PRs in this story add their own counters here (distance
/// travelled, survival time, XP/level reached, weapon tier) beside these --
/// see the `CYBERPUN-17-8` entry in AGENT.md/CLAUDE.md for what remains
/// outstanding.
final class RunSummaryStats {

    /// Distinct infection *occurrences* this run -- incremented once when
    /// the player transitions from uninfected to infected, never per
    /// second of the DoT tick.
    private(set) var timesInfected: Int

    /// Raccoons killed this run -- incremented once per raccoon death.
    private(set) var killCount: Int

    init(timesInfected: Int = 0, killCount: Int = 0) {
        self.timesInfected = timesInfected
        self.killCount = killCount
    }

    /// Records one new infection occurrence. Callers must only invoke this
    /// when the player was not already infected -- `PlayerNode
    /// .infect(stats:)` is the one production caller, and it guards this
    /// exact condition.
    func recordInfection() {
        timesInfected += 1
    }

    /// Records one raccoon kill.
    func recordKill() {
        killCount += 1
    }

    /// Zeroes every counter for a fresh run.
    ///
    /// `GameScene` holds one instance for the lifetime of the scene (so a
    /// later HUD/summary consumer can hold the same reference) and calls
    /// this on every `.gameplay` entry, beside
    /// `RaccoonSpawnDirector.reset()` and `PlayerNode.resetCombatState()`.
    /// Without it, RUN AGAIN would report the previous run's kills and
    /// infections -- the same inherited-state bug those two resets exist
    /// to prevent.
    func reset() {
        timesInfected = 0
        killCount = 0
    }
}
