import ObjectiveC
import SpriteKit

/// Conforms `RaccoonNode` (`CYBERPUN-17-8-t1`) to `Damageable`
/// (`CYBERPUN-17-8` PR 3): contact damage, death/removal from the scene,
/// and the kill-award callback the weapons/XP story (`CYBERPUN-17-9`)
/// consumes -- kept as an extension file rather than a change to
/// `RaccoonNode.swift` itself, so PR 1's file stays untouched.
///
/// `onDeath` and `runStats` are stored via Objective-C associated objects
/// rather than stored properties directly on `RaccoonNode` -- an extension
/// cannot add stored properties to an existing class, and `RaccoonNode` (a
/// SpriteKit `SKNode`, an `NSObject` subclass) supports the associated-object
/// pattern the same way `PlayerNode+Rabies.swift` uses it for the player's
/// own combat state.
extension RaccoonNode: Damageable {

    private static var onDeathKey: UInt8 = 0
    private static var runStatsKey: UInt8 = 0

    /// Invoked exactly once, the instant this raccoon dies -- the
    /// kill-award seam `CYBERPUN-17-9`'s XP/kill system consumes. `nil` by
    /// default (nothing awarded), so this PR does not have to invent that
    /// system's own bookkeeping; a raccoon constructed directly in a unit
    /// test needs no callback at all.
    var onDeath: (() -> Void)? {
        get { objc_getAssociatedObject(self, &Self.onDeathKey) as? (() -> Void) }
        set { objc_setAssociatedObject(self, &Self.onDeathKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    /// The run's counters this raccoon's death increments (`killCount`).
    /// `nil` by default; the production spawn path (a later PR) sets this
    /// on every raccoon it mounts.
    var runStats: RunSummaryStats? {
        get { objc_getAssociatedObject(self, &Self.runStatsKey) as? RunSummaryStats }
        set { objc_setAssociatedObject(self, &Self.runStatsKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    var isDead: Bool { hp <= 0 }

    /// Applies `amount` damage, clamped so `hp` never drops below zero,
    /// and triggers `die()` the instant it first reaches zero. Guarded on
    /// `!isDead` so a hit landing on an already-dead (but not yet removed)
    /// raccoon within the same frame can't double-fire `die()`.
    func takeDamage(_ amount: Int) {
        guard !isDead, amount > 0 else { return }
        hp = max(0, hp - amount)
        if isDead {
            die()
        }
    }

    /// Records the kill into `runStats`, fires `onDeath`, and removes this
    /// raccoon from the scene -- the "death removal" this story calls for
    /// (nothing removed a raccoon from `worldLayer` before this PR; see
    /// `RaccoonSpawnDirector`'s own doc comment on that gap).
    func die() {
        runStats?.recordKill()
        onDeath?()
        removeFromParent()
    }
}
