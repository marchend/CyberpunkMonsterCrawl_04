import Foundation

/// A common "can take damage, and knows when it has died" surface for
/// combat targets (`CYBERPUN-17-8` PR 3).
///
/// `RaccoonNode` is the first conformer (`RaccoonNode+Combat.swift`, this
/// PR). `PlayerNode` deliberately does **not** conform here: its
/// damage/death shape is different from a raccoon's -- there is no
/// scene-removal/despawn to perform, and "what happens when the player
/// dies" is the death screen, `CYBERPUN-17-13`, a later PR in this story.
/// Forcing a shared `die()` contract onto a type whose death behaviour
/// isn't defined yet would just mean an empty/placeholder implementation,
/// so `PlayerNode` instead exposes its own `takeDamage(_:)` directly
/// (`PlayerNode+Rabies.swift`) without conforming to `Damageable`.
protocol Damageable: AnyObject {

    /// Current HP. A conformer's own `takeDamage(_:)` must clamp this at
    /// zero -- it never goes negative.
    var hp: Int { get set }

    /// Whether this target has died. Conventionally `hp <= 0`.
    var isDead: Bool { get }

    /// Applies `amount` damage. A conformer must clamp `hp` at zero and
    /// invoke `die()` the instant `hp` first reaches zero -- and must not
    /// invoke it again on a subsequent call once already dead, so a hit
    /// landing on an already-dead target can't double-fire the death/kill
    /// signal.
    func takeDamage(_ amount: Int)

    /// This conformer's death/kill-signaling hook -- called exactly once,
    /// the instant `hp` first reaches zero. `RaccoonNode+Combat.swift`
    /// implements this as removal from the scene plus a kill-award
    /// callback the weapons/XP story (`CYBERPUN-17-9`) consumes.
    func die()
}
