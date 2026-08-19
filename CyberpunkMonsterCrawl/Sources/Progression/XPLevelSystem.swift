import Foundation

/// The player's XP/level curve and the pure level-to-weapon-tier mapping
/// (`CYBERPUN-17-9` PR 3).
///
/// **Scope of this PR.** State (`xp`, `level`) plus the two pure rules that
/// derive from it: `awardXP(_:)` (the only way `xp`/`level` ever change) and
/// the `static` `tier(forLevel:)` function `Player` (this same PR) uses to
/// keep `WeaponFiringController`'s tier and `WeaponOverlayRenderer`'s drawn
/// row in lock-step with the level that produced them.
///
/// **No manual tier-set API exists anywhere on this type, deliberately.**
/// `tier` is not stored here at all -- it is *derived*, on demand, from
/// `level` via the pure `tier(forLevel:)` function, so there is no setter a
/// caller could use to jump tiers independent of level. `WeaponFiringController
/// .setTier(_:)` still exists (it is what actually swaps the live cooldown
/// config), but its only production caller is `Player`'s `onLevelChange`
/// hook, driven by a genuine level-up -- never a direct assignment.
///
/// **XP curve.** A flat `xpPerLevel` requirement per level, chosen (like
/// every other tuning constant in this codebase -- `WeaponTier`'s own
/// fire-rate/range/damage table, `RaccoonSpawnDirector`'s spawn ramp) as an
/// initial value expected to move in a later playtesting pass, not as a
/// measured design target. Only `level(forXP:)`'s formula would need to
/// change for a future escalating curve; no call site (`Player`,
/// `XPLevelSystemTests`) depends on the curve being flat.
///
/// **Notification only on a genuine level change.** `awardXP(_:)` is the
/// *only* place `level` is ever written, and it compares the freshly
/// derived level against the current one before writing or notifying --
/// deliberately not a `didSet` observer on `level` itself, since Swift's
/// two-phase-init rules make "did this fire during construction" a subtler
/// question than the explicit guard below needs to be. A `XPLevelSystem`
/// that has never had `awardXP(_:)` called therefore never fires
/// `onLevelChange`, including at construction.
final class XPLevelSystem {

    /// Cumulative XP required to advance one level -- an initial tuning
    /// constant. Level `n` requires `(n - 1) * xpPerLevel` cumulative XP,
    /// so with the default `100`: level 1 spans `0..<100`, level 2
    /// `100..<200`, level 3 `200..<300`, ... level 6 `500..<600`.
    static let xpPerLevel: Int = 100

    /// Current cumulative XP this run. Only ever increased, by `awardXP(_:)`.
    private(set) var xp: Int = 0

    /// Current level, starting at `1`. Only ever changed by `awardXP(_:)`,
    /// and only when the newly-derived level actually differs from this
    /// one.
    private(set) var level: Int = 1

    /// Invoked exactly once per genuine level change, with the new level --
    /// never at construction, never for an `awardXP(_:)` call that does not
    /// cross a level boundary. `Player` subscribes to this to keep
    /// `WeaponFiringController.setTier(_:)` and
    /// `WeaponOverlayRenderer.update(tier:direction:)` atomic with the level
    /// that produced the new tier.
    var onLevelChange: ((Int) -> Void)?

    /// Adds `amount` XP and recomputes `level` from the new cumulative
    /// total, firing `onLevelChange` if (and only if) that recomputation
    /// actually changed `level`. A non-positive `amount` is a no-op, the
    /// same "guard before mutating" shape `PlayerNode+Pickups.heal(_:)` and
    /// `RunStats.recordDamage(_:)` (this same PR) use.
    func awardXP(_ amount: Int) {
        guard amount > 0 else { return }
        xp += amount

        let newLevel = Self.level(forXP: xp)
        guard newLevel != level else { return }
        level = newLevel
        onLevelChange?(level)
    }

    /// Returns `xp`/`level` to a fresh run's starting state (`0`, `1`).
    /// `Player.reset()` calls this on every fresh `.gameplay` entry, the
    /// same "RUN AGAIN must not inherit the previous run's state" reason
    /// `RunStats.reset()`/`RaccoonSpawnDirector.reset()` exist.
    ///
    /// Deliberately does **not** invoke `onLevelChange` -- that hook fires
    /// on a genuine *level up*, not a reset back down; `Player.reset()`
    /// re-syncs the decision layer/overlay to the initial tier itself.
    func reset() {
        xp = 0
        level = 1
    }

    /// The level `xp` cumulative XP corresponds to, under the flat
    /// `xpPerLevel` curve documented on that constant. Never returns below
    /// `1` -- a fresh run's `0` XP is level 1, not level 0.
    static func level(forXP xp: Int) -> Int {
        max(1, xp / xpPerLevel + 1)
    }

    /// The weapon tier a player at `level` should be firing -- a pure
    /// function of `level` alone, with no stored tier anywhere on this
    /// type. Matches the story's tier bands exactly: handgun below level 3,
    /// SMG for levels 3 through 5 inclusive, assault rifle from level 6
    /// upward.
    static func tier(forLevel level: Int) -> WeaponTier {
        switch level {
        case ..<3:
            return .handgun
        case 3...5:
            return .smg
        default:
            return .assaultRifle
        }
    }
}
