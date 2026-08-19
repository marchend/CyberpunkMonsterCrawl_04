import Foundation

/// The three auto-fire weapon tiers the player's gun auto-progresses
/// through (`docs/bootstrap.md`'s "weapons auto-progress" note,
/// `CYBERPUN-17-9`).
///
/// **Scope of this PR (`CYBERPUN-17-9` PR 1).** This type only carries the
/// per-tier tunable constants \u2014 fire rate, range, damage \u2014 plus the two
/// atlas-index seams (`weaponSheetRow`, `bulletSheetColumn`) a later
/// rendering/bullet-spawning PR reads from. Nothing here fires a shot,
/// spawns a bullet, or renders anything: that is `WeaponFiringController`
/// (the decision layer, this same PR) and later PRs (the actual
/// spawn/rendering), matching the convention `RaccoonTier` set for the
/// raccoon swarm's own per-tier constants.
///
/// **No barrel-tip/muzzle offset table here, deliberately.** An earlier
/// revision of this file carried a per-direction `barrelTipOffset` table
/// whose values were derived from the 36x40 cell's *centre*
/// (half-dimensions 18x20), but the anchor every actor in this codebase
/// actually draws against is bottom-centre \u2014 the feet
/// (`PlayerSpriteSheet.anchorPixel` is `(18, 40)`, so
/// `anchorPointNormalized == (0.5, 0.0)`; `RaccoonAnimationController`
/// follows the same convention). Against the real anchor those numbers put
/// the south/south-diagonal barrel tips *below* the ground plane, which
/// would have spawned bullet origins and `sprite_hit_puff` frame-0 muzzle
/// flashes at the player's shoes. Rather than re-guess the table in the
/// right coordinate frame, it was left unwritten until someone measures the
/// muzzle pixel off the shipped art \u2014 the same way
/// `RaccoonNode.shadowWidth(forTier:)` was measured rather than guessed.
/// `CYBERPUN-17-9` PR 3 (`Player`) mounted `sprite_player_weapons` on
/// screen but made no such measurement, so the table still does not exist
/// and the muzzle flash is spawned at the actor anchor; that open AC6 gap
/// is recorded in `Player`'s "Known gap" doc section and at its
/// `handleFire(target:origin:tier:)` call site. Shipping unmeasured art constants that
/// read as authoritative is precisely what `AtlasContractConventionTests`
/// and `RaccoonSpriteSheetPixelTests` exist to prevent.
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
    /// `BiteComponent.biteDamage`'s shape. `Player`'s bullet-hit
    /// resolution (`CYBERPUN-17-9` PR 3) is what calls `takeDamage(_:)`
    /// with this value, once a shot's flight timer elapses. An initial
    /// tuning constant.
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
}
