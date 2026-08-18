import Foundation

/// The rabies infection roll (`CYBERPUN-17-8` PR 3): "a bite may infect
/// (d20 vs tier threshold)". This type owns the pure roll rule and the
/// DoT rate constant; the actual infection *state* (`isInfected`) and its
/// per-second tick live on `PlayerNode` (`PlayerNode+Rabies.swift`), since
/// that is the state a bite mutates, not a fact about the roll itself.
enum RabiesStatusEffect {

    /// HP lost per second while infected, per the story ("1 HP/s").
    static let damagePerSecond: Double = 1.0

    /// Rolls a d20 (`1...20`, inclusive both ends) against `tier
    /// .rabiesThreshold` using `rng`, and reports whether that roll
    /// infects.
    ///
    /// **The rule: infects iff the roll is `<= threshold`.**
    /// `RaccoonTier.rabiesThreshold` documents "elites carry a higher
    /// rabies threshold" as part of being the tougher, more dangerous
    /// tier, and `<=` is the comparison direction under which a *higher*
    /// threshold makes infection *more* likely (`.elite`'s 15 covers 15 of
    /// 20 faces vs `.base`'s 10 covering 10). The opposite comparison
    /// would make the elite -- despite being framed as more dangerous --
    /// infect *less* often, which contradicts the story's own framing of
    /// that tier.
    ///
    /// Exposed as a `static` pure function taking `rng` generically by
    /// `inout` (mirroring `RaccoonSpawnDirector.selectTier(rng:)`'s own
    /// shape), so tests can pin the roll-vs-threshold boundary exactly
    /// with a scripted deterministic generator, without a live
    /// `RaccoonNode`/`PlayerNode`.
    ///
    /// The roll is derived from `rng.next()` via a plain modulo mapping
    /// (`% 20` -> `0...19`, then `+1` -> `1...20`) rather than the standard
    /// library's higher-level `Int.random(in:using:)` -- that call's exact
    /// output for a given raw generator value is an unexposed
    /// implementation detail of the stdlib's rejection-sampling algorithm,
    /// which would make "inject a scripted RNG and assert the resulting
    /// roll" impossible to pin precisely in a test. The modulo mapping's
    /// tiny bias (some faces are one in 2^64 / 20 draws more likely than
    /// others) is irrelevant at 20 buckets against a 64-bit input, and
    /// exact, hand-computable determinism is exactly the seam this PR's
    /// tests need.
    static func rollInfects<R: RandomNumberGenerator>(tier: RaccoonTier, rng: inout R) -> Bool {
        let roll = Int(rng.next() % 20) + 1
        return roll <= tier.rabiesThreshold
    }
}
