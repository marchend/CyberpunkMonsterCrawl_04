import Foundation

/// Shared level-driven scaling tables (`CYBERPUN-17-10` PR 1) for
/// abilities whose power spikes are keyed off the player's level --
/// `XPLevelSystem.level`, the same counter `XPLevelSystem.tier(forLevel:)`
/// already reads to pick the auto-fire weapon tier.
///
/// **Why this is a separate type from `XPLevelSystem.tier(forLevel:)`.**
/// That function derives a *discrete* choice (which of three weapon tiers
/// is equipped) from level; this story's pulse ability instead needs
/// *continuous* per-level multipliers (a compounding radius bonus) plus a
/// second discrete choice with different level thresholds (the damage
/// die). Folding both shapes into `XPLevelSystem` would mix "what tier is
/// equipped" with "how strong is an unrelated ability", so this lives as
/// its own small table instead -- named `Game`, not `Progression` or
/// `Abilities`, because it is meant to hold whichever future ability's
/// level-scaling table needs one next, not just the pulse's.
///
/// **Compounding, not additive.** The story's own wording is "radius
/// +25%" at level 3 and "a further +25%" at level 6 -- i.e. the second
/// bonus multiplies the already-boosted radius rather than adding another
/// flat 25% of the base. `pulseRadiusMultiplier(forLevel:)` therefore
/// returns `1.25 * 1.25 == 1.5625` at level 6+, not `1.5`.
enum LevelScaling {

    /// The pulse ability's radius multiplier at `level`, relative to
    /// `PulseAbility.baseRadiusTiles`:
    /// - levels `0...2`: `1.0` (no bonus).
    /// - levels `3...5`: `1.25` (+25%).
    /// - level `6` and above: `1.25 * 1.25 == 1.5625` (a further +25%,
    ///   compounding on the level-3 bonus rather than stacking additively).
    static func pulseRadiusMultiplier(forLevel level: Int) -> Double {
        var multiplier = 1.0
        if level >= 3 { multiplier *= 1.25 }
        if level >= 6 { multiplier *= 1.25 }
        return multiplier
    }

    /// The pulse ability's damage die at `level`, applied to both the push
    /// hit and (when a raccoon is crushed against a footprint) the second
    /// crush hit: `1d6` below level 6, `1d8` at level 6 and above -- the
    /// same level-6 threshold `pulseRadiusMultiplier(forLevel:)` uses for
    /// its second compounding step, so both scale together at exactly one
    /// level boundary.
    static func pulseDamageDie(forLevel level: Int) -> DiceSpec {
        level >= 6 ? DiceSpec(count: 1, sides: 8) : DiceSpec(count: 1, sides: 6)
    }
}
