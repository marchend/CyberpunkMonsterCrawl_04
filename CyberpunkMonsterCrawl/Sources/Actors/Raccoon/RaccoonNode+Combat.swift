import SpriteKit

/// Conforms `RaccoonNode` (`CYBERPUN-17-8-t1`) to `Damageable`
/// (`CYBERPUN-17-8` PR 3): contact damage, death/removal from the scene,
/// and the kill-award callback the weapons/XP story (`CYBERPUN-17-9`)
/// consumes.
///
/// This file holds the *behaviour* only. `onDeath` and `runStats` are
/// ordinary stored properties on `RaccoonNode` itself, declared beside
/// `hp`/`tier`/`facing` like every other piece of that actor's state; they
/// were Objective-C associated objects here until review (PR #34) called
/// that out -- "keeping PR 1's file untouched" was a process preference,
/// not an engineering constraint, and it cost the reader the visibility of
/// the state the death path mutates.
extension RaccoonNode: Damageable {

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
