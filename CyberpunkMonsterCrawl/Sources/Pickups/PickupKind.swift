import Foundation

/// A simple `NdM` dice specification: `count` dice of `sides` faces each,
/// summed. Carries no dependency on any particular random source -- every
/// caller rolls it against its own injected generator, the same separation
/// `RaccoonSpawnDirector`'s pure `selectTier`/`selectSpawnTile` helpers
/// keep from that type's RNG.
struct DiceSpec: Equatable {
    /// Number of dice rolled.
    let count: Int
    /// Faces per die.
    let sides: Int

    /// The inclusive range every roll of this spec can produce:
    /// `count...(count * sides)`.
    var range: ClosedRange<Int> { count...(count * sides) }

    /// Rolls this spec against `rng`: the sum of `count` dice of `sides`
    /// faces each, always inside `range`.
    ///
    /// **The one roller for a `DiceSpec` in this codebase** (PR #37
    /// review). Three separate copies existed before: `PickupManager.roll`
    /// via `Int.random(in:using:)`, plus a private `rollDice` in each of
    /// the two consume-effect files -- one spec, three mappings, so the
    /// same dice could produce different distributions depending on which
    /// call site rolled them. `DiceSpec` already owns the roll's contract
    /// (`range`), so it owns the roll.
    ///
    /// The raw `next() % sides + 1` mapping is the one
    /// `RabiesStatusEffect.rollInfects(tier:rng:)` documents choosing over
    /// `Int.random(in:using:)`: an exact, hand-computable result from a
    /// known raw generator value, rather than the stdlib's unexposed
    /// rejection-sampling internals, so a test can pin a scripted roll
    /// precisely. The mapping's tiny modulo bias is irrelevant at 6/10
    /// buckets against a 64-bit input.
    func roll<R: RandomNumberGenerator>(using rng: inout R) -> Int {
        var total = 0
        for _ in 0..<count {
            total += Int(rng.next() % UInt64(sides)) + 1
        }
        return total
    }
}

/// The two ground-pickup kinds a run spawns: a med kit (heals the player)
/// and a garbage can (a distraction/consume item -- `RaccoonNode.isWounded`'s
/// own doc comment names the intended later consumer: diverting a wounded
/// raccoon toward one).
///
/// **Scope of `CYBERPUN-17-11` PR 1.** The frozen tuned constants and the
/// per-kind dice spec live here; nothing in this PR applies a rolled value
/// to a player's HP or a raccoon's behaviour yet -- `PickupManager
/// .attemptCollectMedKit`/`attemptCollectGarbageCan` merely report the roll,
/// exactly the query-API shape a later wiring PR needs.
enum PickupKind: CaseIterable, Equatable, Hashable {
    case medKit
    case garbageCan

    /// One kind's frozen tuning: spawn cadence, concurrency cap, on-ground
    /// lifetime and roll dice. **Frozen, not a placeholder** -- unlike
    /// `RaccoonSpawnDirector`'s own tunables (explicitly expected to move in
    /// a later playtesting pass), the story hands these numbers over as
    /// exact values to ship.
    struct Tuning: Equatable {
        /// Seconds into a run before this kind's very first spawn attempt.
        let firstSpawnDelay: TimeInterval
        /// Seconds between spawn attempts once this kind's cadence is
        /// running (after the first spawn, and after every subsequent one).
        let spawnCadence: TimeInterval
        /// Hard cap on concurrently-alive, uncollected pickups of this kind.
        ///
        /// **Unreachable at the frozen numbers below -- the effective
        /// ceiling is 1, not 2.** `spawnCadence` (25s) is longer than
        /// `lifetime` (20s), and a kind's cadence only re-arms *after* a
        /// successful spawn, so a pickup always expires (spawn + 20s)
        /// before its kind's next spawn attempt (spawn + 25s); a failed
        /// placement search holds the timer at `0` but still only ever
        /// produces one pickup at a time. `PickupManager.update`'s
        /// `aliveCount < maxAlive` branch therefore never fires under these
        /// values, and this cap stands as a safety net rather than an
        /// exercised path.
        ///
        /// Recorded here rather than left for a reader to infer, because
        /// `PickupManagerTests`'
        /// `test_maxAlivePerKind_isNeverExceeded_andTheObservedCeilingIsPinned`
        /// would otherwise read as coverage of a cap it never reaches. That test
        /// carries an anti-vacuity guard (the shape
        /// `ChunkStreamingManagerTests`' viewport coverage uses) pinning the
        /// observed ceiling at exactly 1, so a future retune that makes the
        /// cap reachable turns the suite red and whoever retunes adds a test
        /// that exercises the cap branch itself. Whether "max 2 alive per
        /// kind" was *meant* to be reachable is a question for whoever
        /// tuned these values; this PR does not change frozen numbers.
        let maxAlive: Int
        /// Seconds an uncollected pickup of this kind survives on the
        /// ground before `PickupManager` expires it, aged strictly by real
        /// `deltaTime` (see `PickupManager.update(deltaTime:visibleRect:)`).
        let lifetime: TimeInterval
        /// The dice rolled for the value a successful collection reports.
        let dice: DiceSpec
    }

    /// One small static table, per this story's plan: both kinds share
    /// every timing number (8s first spawn, 25s cadence, 2 max alive, 20s
    /// lifetime); only the dice differ -- 1d10 healing for a med kit, 1d6
    /// for a garbage can's consume value.
    private static let tuningTable: [PickupKind: Tuning] = [
        .medKit: Tuning(
            firstSpawnDelay: 8,
            spawnCadence: 25,
            maxAlive: 2,
            lifetime: 20,
            dice: DiceSpec(count: 1, sides: 10)
        ),
        .garbageCan: Tuning(
            firstSpawnDelay: 8,
            spawnCadence: 25,
            maxAlive: 2,
            lifetime: 20,
            dice: DiceSpec(count: 1, sides: 6)
        ),
    ]

    /// This kind's frozen tuning. A missing table entry is a programmer
    /// error (a case added to `PickupKind` without a matching row above),
    /// not a recoverable runtime condition -- the same "precondition, never
    /// silently pass" discipline `SpriteSheet.init`'s measurement check
    /// applies.
    var tuning: Tuning {
        guard let value = Self.tuningTable[self] else {
            preconditionFailure("PickupKind.tuningTable is missing an entry for \(self).")
        }
        return value
    }

    /// Column index into `AtlasSheet.pickups`' single-row grid
    /// (`AtlasCellIndex.pickups`): med kit at cell 0, garbage can at cell 1,
    /// per the measured 48x24px sheet / 24x24px cells.
    var atlasColumn: Int {
        switch self {
        case .medKit: return 0
        case .garbageCan: return 1
        }
    }
}
