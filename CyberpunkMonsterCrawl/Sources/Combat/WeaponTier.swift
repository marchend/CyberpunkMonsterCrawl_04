import CoreGraphics
import Foundation

/// The three auto-fire weapon tiers the player's gun auto-progresses
/// through (`docs/bootstrap.md`'s "weapons auto-progress" note,
/// `CYBERPUN-17-9`).
///
/// **Scope of this PR (`CYBERPUN-17-9` PR 1).** This type only carries the
/// per-tier tunable constants \u2014 fire rate, range, damage \u2014 plus the two
/// atlas-index seams (`weaponSheetRow`, `bulletSheetColumn`) a later
/// rendering/bullet-spawning PR reads from, and the per-direction
/// barrel-tip offset table. Nothing here fires a shot, spawns a bullet, or
/// renders anything: that is `WeaponFiringController` (the decision layer,
/// this same PR) and later PRs (the actual spawn/rendering), matching the
/// convention `RaccoonTier` set for the raccoon swarm's own per-tier
/// constants.
enum WeaponTier: Equatable, CaseIterable {
    case handgun
    case smg
    case assaultRifle

    /// Seconds between successive shots at this tier \u2014 the cooldown
    /// `WeaponFiringController` counts down before it may fire again. An
    /// initial tuning constant: like every other per-tier combat number in
    /// this codebase (`RaccoonTier.maxHPMultiplier`,
    /// `BiteComponent.biteIntervalSeconds`), the story defers exact
    /// numbers to playtesting.
    var fireIntervalSeconds: TimeInterval {
        switch self {
        case .handgun: return 0.6
        case .smg: return 0.25
        case .assaultRifle: return 0.15
        }
    }

    /// Tile-space Euclidean radius (in tile units) `TargetSelection`
    /// considers "in range" for a shot at this tier. An initial tuning
    /// constant, expected to move in a later playtesting pass.
    var rangeTiles: Double {
        switch self {
        case .handgun: return 5.0
        case .smg: return 6.0
        case .assaultRifle: return 7.0
        }
    }

    /// Direct HP damage one shot at this tier deals \u2014 a plain `Int`
    /// applied via `Damageable.takeDamage(_:)`, mirroring
    /// `BiteComponent.biteDamage`'s shape. Whichever later PR spawns the
    /// actual bullet/hit is what calls `takeDamage(_:)` with this value;
    /// nothing does yet. An initial tuning constant.
    var damage: Int {
        switch self {
        case .handgun: return 8
        case .smg: return 5
        case .assaultRifle: return 9
        }
    }

    /// This tier's row within `AtlasSheet.playerWeapons`' 8-column
    /// (direction) x 3-row (tier) grid \u2014 that sheet's own measured-geometry
    /// comment reads "rows 0/1/2 = handgun/SMG/AR", so this table exists
    /// only to name that mapping once rather than leaving a later
    /// rendering PR to re-derive it (or worse, hardcode the row number at
    /// its own call site).
    var weaponSheetRow: Int {
        switch self {
        case .handgun: return 0
        case .smg: return 1
        case .assaultRifle: return 2
        }
    }

    /// This tier's column within `AtlasSheet.bullets`' single-row,
    /// 3-variant grid \u2014 that sheet's own measured-geometry comment reads
    /// "0 slug \u00b7 1 SMG tracer \u00b7 2 rifle round", in the same tier order
    /// as `weaponSheetRow`. A later bullet-spawning PR reads this to pick
    /// which bullet sprite variant to draw for a shot fired at this tier.
    var bulletSheetColumn: Int {
        switch self {
        case .handgun: return 0
        case .smg: return 1
        case .assaultRifle: return 2
        }
    }

    /// The on-screen (SpriteKit y-up) offset from an actor's anchor to the
    /// weapon's barrel tip while facing `direction` \u2014 the point a later
    /// bullet-spawning PR should originate a shot from, rather than the
    /// player's bare center.
    ///
    /// **Deliberately uniform across tiers, for now.** No PR yet mounts
    /// `sprite_player_weapons` on screen, so there is no measured
    /// per-weapon muzzle pixel to differ against \u2014 inventing tier-specific
    /// numbers here would be exactly the "art fact guessed instead of
    /// measured" this codebase's atlas-contract tests exist to catch (see
    /// `AtlasContractConventionTests`, `RaccoonSpriteSheetPixelTests`). A
    /// later PR that actually mounts the held-weapon sprite should
    /// re-derive these per tier from the shipped art, the same way
    /// `RaccoonNode.shadowWidth(forTier:)` was measured off the raccoon art
    /// rather than guessed.
    ///
    /// Named/tunable initial values: a held-at-chest-height offset, scaled
    /// to `AtlasSheet.playerWeapons`'s own measured 36x40 cell
    /// half-dimensions (18x20).
    static func barrelTipOffset(forDirection direction: Direction8) -> CGVector {
        switch direction {
        case .south: return CGVector(dx: 0, dy: -12)
        case .southeast: return CGVector(dx: 10, dy: -8)
        case .east: return CGVector(dx: 14, dy: 2)
        case .northeast: return CGVector(dx: 10, dy: 10)
        case .north: return CGVector(dx: 0, dy: 14)
        case .northwest: return CGVector(dx: -10, dy: 10)
        case .west: return CGVector(dx: -14, dy: 2)
        case .southwest: return CGVector(dx: -10, dy: -8)
        }
    }
}
