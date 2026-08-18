import CoreGraphics

/// The raccoon swarm's two tiers \u2014 ordinary spawns and the tougher "elite"
/// tier a fraction of spawns are promoted to (`CYBERPUN-17-8`: "Elite tier: a
/// fraction of spawns are elites \u2014 tougher, drawn 1.6x, with a higher rabies
/// threshold").
///
/// **Scope of this PR (`CYBERPUN-17-8-t1`).** This type only carries the
/// per-tier constants \u2014 visual scale, HP multiplier, rabies-roll threshold.
/// *Which* fraction of spawns become elite (swarm spawning) and the actual
/// d20-vs-threshold infection roll (bite/rabies behaviour) are later parts of
/// the `CYBERPUN-17-8` story; this PR's job is the rendering/actor-state
/// layer those systems will read from.
enum RaccoonTier: Equatable, CaseIterable {
    case base
    case elite

    /// Visual scale factor applied to the raccoon's base 48x28 cell size
    /// (`RaccoonAnimationController.cellSize`). `1.6` for elite, per the
    /// story ("Elite tier drawn 1.6x"); `1.0` (unscaled) for the base tier.
    var scale: CGFloat {
        switch self {
        case .base: return 1.0
        case .elite: return 1.6
        }
    }

    /// Multiplier applied to `RaccoonNode.baseMaxHP` for this tier \u2014 elites
    /// are "tougher" per the story, not just visually larger.
    ///
    /// `2.0` is an initial tuning constant, not a measured fact: the story
    /// explicitly defers exact swarm/difficulty numbers to playtesting
    /// ("Tune spawn cadence and swarm size in playtesting; expose the
    /// numbers as named constants"), so a later PR in this story is expected
    /// to retune this value.
    var maxHPMultiplier: CGFloat {
        switch self {
        case .base: return 1.0
        case .elite: return 2.0
        }
    }

    /// The d20 threshold a bite's infection roll is checked against
    /// (`CYBERPUN-17-8`: "a bite may infect (d20 vs tier threshold)"). Elites
    /// carry "a higher rabies threshold" per the story.
    ///
    /// Like `maxHPMultiplier`, this is an initial tuning constant \u2014 the
    /// actual d20 roll and infection/rabies-tick behaviour is this story's
    /// bite/rabies PR, not this one; this PR only carries the per-tier
    /// constant that PR will read.
    var rabiesThreshold: Int {
        switch self {
        case .base: return 10
        case .elite: return 15
        }
    }
}
