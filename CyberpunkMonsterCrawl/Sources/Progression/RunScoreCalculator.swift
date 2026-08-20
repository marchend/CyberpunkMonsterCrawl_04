import Foundation

/// The eight death-screen run-summary rows (`CYBERPUN-17-13`), computed once
/// from the run-state counters accumulated by earlier stories.
///
/// The design brief names all eight rows, in this order:
/// 1. **SURVIVED** -- elapsed run time (`survivedSeconds`; formatting into
///    `mm:ss` is left to the screen layer, the numeric contract lives here).
/// 2. **RACCOONS DOWN** -- `RunSummaryStats.killCount`.
/// 3. **LEVEL** -- `XPLevelSystem.level`.
/// 4. **RABIES** -- `RunSummaryStats.timesInfected`, the count of distinct
///    infection *events*, deliberately not any HP-lost-to-rabies figure.
/// 5. **DAMAGE DEALT** -- `RunStats.damageDealt`.
/// 6. **KILL BONUS** -- `100 * killCount` (see `killBonusPerKill`).
/// 7. **SURVIVAL** -- `floor(elapsedSeconds) * level`, the survival-time
///    contribution to SCORE (distinct from the SURVIVED row above, which is
///    the raw elapsed time, not this scoring term).
/// 8. **SCORE** -- `damageDealt + killBonus + survivalBonus`, i.e.
///    `RunStats.damageDealt + 100 * killCount + floor(elapsedSeconds) * level`,
///    exactly as clarified in the ticket's "Scoring formula" section.
enum RunScoreCalculator {

    /// Flat points awarded per raccoon kill toward `killBonus`. A named,
    /// documented **v1 balance placeholder** -- the ticket's "Out of scope"
    /// section explicitly defers tier-weighted kill-bonus scoring, so this
    /// constant is expected to move in a later playtesting pass without the
    /// formula shape (`killBonusPerKill * killCount`) changing.
    static let killBonusPerKill: Int = 100

    /// `killBonus == killBonusPerKill * killCount` -- flat points per kill,
    /// no tier weighting.
    static func killBonus(forKillCount killCount: Int) -> Int {
        killBonusPerKill * killCount
    }

    /// Computes the full `RunSummary` from the three run-state sources plus
    /// elapsed wall-clock seconds.
    ///
    /// - Parameters:
    ///   - runSummaryStats: source of `killCount` (RACCOONS DOWN) and
    ///     `timesInfected` (RABIES).
    ///   - runStats: source of `damageDealt` (DAMAGE DEALT).
    ///   - xpLevelSystem: source of `level` (LEVEL, and the SCORE
    ///     multiplier).
    ///   - elapsedSeconds: wall-clock seconds survived this run; only the
    ///     integer part contributes to SURVIVED/SURVIVAL, per the ticket's
    ///     `floor(elapsedSeconds)` formula.
    static func summarize(
        runSummaryStats: RunSummaryStats,
        runStats: RunStats,
        xpLevelSystem: XPLevelSystem,
        elapsedSeconds: TimeInterval
    ) -> RunSummary {
        let killCount = runSummaryStats.killCount
        let level = xpLevelSystem.level
        let damageDealt = runStats.damageDealt
        let bonus = killBonus(forKillCount: killCount)
        let survivedSeconds = Int(elapsedSeconds.rounded(.down))
        let survivalBonus = survivedSeconds * level
        let score = damageDealt + bonus + survivalBonus

        return RunSummary(
            survivedSeconds: survivedSeconds,
            raccoonsDown: killCount,
            level: level,
            rabies: runSummaryStats.timesInfected,
            damageDealt: damageDealt,
            killBonus: bonus,
            survivalBonus: survivalBonus,
            score: score
        )
    }
}

/// The eight computed death-screen summary values (`CYBERPUN-17-13`),
/// produced by `RunScoreCalculator.summarize(...)`. A pure value type --
/// no reference to the live run state it was computed from -- so it can
/// outlive the run it summarizes (the death screen renders it; later,
/// `HighScoreStore` persists it).
struct RunSummary: Equatable {
    /// SURVIVED row: whole seconds elapsed this run.
    let survivedSeconds: Int
    /// RACCOONS DOWN row: raccoons killed this run.
    let raccoonsDown: Int
    /// LEVEL row: level reached this run.
    let level: Int
    /// RABIES row: distinct infection events this run (not HP lost).
    let rabies: Int
    /// DAMAGE DEALT row: cumulative gunfire damage this run.
    let damageDealt: Int
    /// KILL BONUS row: `100 * raccoonsDown`.
    let killBonus: Int
    /// SURVIVAL row: `survivedSeconds * level`, the survival-time
    /// contribution to SCORE.
    let survivalBonus: Int
    /// SCORE row: `damageDealt + killBonus + survivalBonus`.
    let score: Int
}
