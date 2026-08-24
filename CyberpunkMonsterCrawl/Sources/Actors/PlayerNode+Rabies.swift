import SpriteKit

/// The player's rabies-infection/HP **behaviour** (`CYBERPUN-17-8` PR 3):
/// direct damage, starting an infection, the per-frame DoT tick and the
/// per-run reset. The state these operate on (`maxHP`, `hp`, `isInfected`,
/// `rabiesDamageAccumulator`) is declared as ordinary stored properties on
/// `PlayerNode` itself -- see that file's "Combat state" section. This file
/// used to hold that state in Objective-C associated objects; review
/// (PR #34) called that out and it was replaced with stored properties,
/// which restores the reset seam below, keeps the `0...maxHP` invariant
/// visible from `PlayerNode.swift`, and takes the `objc_*` lookup plus
/// `as?` unbox off the per-frame `tickRabies` path.
///
/// **Scope of this file.** HP plus the rabies DoT/infection status only --
/// no death handling: the code below clamps `hp` at zero and stops there.
/// What *happens* at zero HP is owned elsewhere, and as of
/// `CYBERPUN-17-13-t5` it is wired up:
/// `GameScene.advanceMovementAndCamera(currentTime:)` transitions the state
/// machine to `.death` once per `.gameplay` frame when `player.hp <= 0`,
/// after every HP-affecting update that frame (this file's `takeDamage`/
/// `tickRabies` included) has already applied -- pinned by
/// `PlayerDeathTriggerTests`. The earlier, recorded consequence of that
/// trigger not existing yet (a player who ran out of HP kept playing at
/// 0 HP, biteable and still ticking) no longer holds; the
/// `CYBERPUN-17-13` entry in AGENT.md/CLAUDE.md records where the trigger
/// now lives. `PlayerNode` still deliberately does not conform to
/// `Damageable` -- see that protocol's own doc comment.
extension PlayerNode {

    /// Applies `amount` direct damage, clamped at zero via `hp`'s own
    /// `didSet`. `BiteComponent`'s direct bite damage and
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
    /// frame, from the scene's own per-frame player update.
    func tickRabies(deltaTime: TimeInterval) {
        guard isInfected, deltaTime > 0 else { return }
        rabiesDamageAccumulator += deltaTime * RabiesStatusEffect.damagePerSecond
        let wholeDamage = Int(rabiesDamageAccumulator)
        guard wholeDamage > 0 else { return }
        rabiesDamageAccumulator -= Double(wholeDamage)
        takeDamage(wholeDamage)
    }

    /// Returns the player's combat state to a fresh run's starting point:
    /// full HP, uninfected, no carried DoT remainder.
    ///
    /// `GameScene.startPlayer(at:)` calls this on every `.gameplay` entry,
    /// alongside the reposition. A restart deliberately **reuses** the
    /// existing `PlayerNode` (that method's own doc comment explains why),
    /// so without this a RUN AGAIN would start on the HP the previous run
    /// ended with and -- because `infect(stats:)` is one-way -- permanently
    /// infected, ticking 1 HP/s from frame one. That is the same class of
    /// leak `RaccoonSpawnDirector.reset()` exists to prevent for the swarm.
    func resetCombatState() {
        maxHP = Self.baseMaxHP
        hp = maxHP
        isInfected = false
        rabiesDamageAccumulator = 0
    }
}
