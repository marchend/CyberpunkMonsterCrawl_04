import ObjectiveC
import SpriteKit

/// Adds the player's HP and rabies-infection status-effect state to
/// `PlayerNode` (`CYBERPUN-17-8` PR 3), via Objective-C associated objects
/// rather than stored properties on `PlayerNode` itself. `PlayerNode`
/// (SpriteKit's `SKNode`, an `NSObject` subclass) supports this the same
/// way `RaccoonNode+Combat.swift` adds its own kill-award hook to
/// `RaccoonNode` -- and it is what keeps `PlayerNode.swift`'s own diff to
/// the single per-frame `tickRabies(deltaTime:)` call its existing
/// `update(deltaTime:movementVector:)` adds (see that file).
///
/// **Scope of this PR.** HP plus the rabies DoT/infection status only --
/// no death handling. What happens when the player's HP reaches zero is
/// the death screen, `CYBERPUN-17-13`, a later PR in this story; this PR
/// only clamps `hp` at zero and leaves it there. `PlayerNode` deliberately
/// does not conform to `Damageable` for that reason -- see that
/// protocol's own doc comment.
extension PlayerNode {

    private static var maxHPKey: UInt8 = 0
    private static var hpKey: UInt8 = 0
    private static var isInfectedKey: UInt8 = 0
    private static var rabiesAccumulatorKey: UInt8 = 0

    /// The player's baseline max HP. `PlayerNode` carried no HP concept
    /// before this PR (movement/rendering only); introduced here because
    /// the rabies DoT tick and the bite's direct damage are the first
    /// things that need one. An initial tuning constant, expected to move
    /// in a later playtesting pass, like `RaccoonNode.baseMaxHP`.
    static let baseMaxHP: Int = 100

    var maxHP: Int {
        get { (objc_getAssociatedObject(self, &Self.maxHPKey) as? Int) ?? Self.baseMaxHP }
        set { objc_setAssociatedObject(self, &Self.maxHPKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    /// The player's current HP, clamped to `0...maxHP` by this property's
    /// own setter. Defaults to a full `maxHP` on first read -- the same
    /// "spawns at full HP" convention `RaccoonNode.init(hp:)` documents.
    var hp: Int {
        get { (objc_getAssociatedObject(self, &Self.hpKey) as? Int) ?? maxHP }
        set { objc_setAssociatedObject(self, &Self.hpKey, min(max(0, newValue), maxHP), .OBJC_ASSOCIATION_RETAIN) }
    }

    /// Whether the player currently carries the rabies infection.
    var isInfected: Bool {
        get { (objc_getAssociatedObject(self, &Self.isInfectedKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &Self.isInfectedKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    /// Seconds' worth of rabies damage accumulated but not yet applied as
    /// a whole HP -- see `tickRabies(deltaTime:)`.
    private var rabiesDamageAccumulator: Double {
        get { (objc_getAssociatedObject(self, &Self.rabiesAccumulatorKey) as? Double) ?? 0 }
        set { objc_setAssociatedObject(self, &Self.rabiesAccumulatorKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    /// Applies `amount` direct damage, clamped at zero via `hp`'s own
    /// setter. `BiteComponent`'s direct bite damage and
    /// `tickRabies(deltaTime:)`'s DoT both funnel through this one entry
    /// point.
    func takeDamage(_ amount: Int) {
        guard amount > 0 else { return }
        hp -= amount
    }

    /// Starts the rabies infection, recording a **new** infection
    /// occurrence into `stats` -- but only the first time. A raccoon
    /// biting an already-infected player may still roll a success (nothing
    /// stops that roll from happening again), but
    /// `RunSummaryStats.timesInfected` must count distinct infection
    /// *occurrences*, not every successful roll landing on an
    /// already-infected player. `BiteComponent` calls this on every
    /// successful `RabiesStatusEffect` roll; the guard below is what makes
    /// a repeat roll while already infected a no-op on the counter.
    func infect(stats: RunSummaryStats) {
        guard !isInfected else { return }
        isInfected = true
        rabiesDamageAccumulator = 0
        stats.recordInfection()
    }

    /// Advances the rabies DoT clock by `deltaTime`: while infected,
    /// accumulates `deltaTime * RabiesStatusEffect.damagePerSecond` and
    /// applies whichever whole HP that accumulation has reached via
    /// `takeDamage(_:)`, carrying the fractional remainder forward -- so
    /// the loss is exactly 1 HP per second of infected time, sampled over
    /// any duration, independent of the frame rate driving the calls (the
    /// same accumulate-then-floor shape `RaccoonAnimationController
    /// .frameIndex(elapsedTime:framesPerSecond:)` uses for frame timing,
    /// rather than assuming a fixed per-call amount that would drift with
    /// `deltaTime`).
    ///
    /// A no-op while not infected, or for a non-positive `deltaTime`.
    ///
    /// `PlayerNode.update(deltaTime:movementVector:)` calls this once per
    /// frame -- the single line this PR adds to `PlayerNode.swift`'s
    /// existing per-frame update.
    func tickRabies(deltaTime: TimeInterval) {
        guard isInfected, deltaTime > 0 else { return }
        rabiesDamageAccumulator += deltaTime * RabiesStatusEffect.damagePerSecond
        let wholeDamage = Int(rabiesDamageAccumulator)
        guard wholeDamage > 0 else { return }
        rabiesDamageAccumulator -= Double(wholeDamage)
        takeDamage(wholeDamage)
    }
}
