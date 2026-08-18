import CoreGraphics
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-11` PR 2: `RaccoonSeekBehavior.updateWithDiversion(...)` --
/// wounded-raccoon garbage-can diversion (divert while in range, consume
/// on arrival for 1d6, resume seeking the player once the caller stops
/// passing a garbage-can position), proven entirely independent of
/// GameScene/PickupManager per this PR's acceptance criteria.
final class RaccoonPickupDiversionTests: XCTestCase {

    /// A scripted `RandomNumberGenerator` that replays one fixed raw
    /// `UInt64` value forever, so a consume roll is an exact, known number
    /// (`rawValue % 6 + 1` for the garbage can's 1d6) rather than a range.
    /// `0` therefore rolls a `1` -- the smallest heal there is, which is
    /// what makes "the HP did not move" a real assertion rather than one
    /// that a big roll could mask by hitting `maxHP`.
    private struct ScriptedRandomNumberGenerator: RandomNumberGenerator {
        private let value: UInt64
        init(_ value: UInt64) { self.value = value }
        func next() -> UInt64 { value }
    }

    // MARK: - A wounded raccoon within range diverts, consumes, and resumes seeking the player

    func test_woundedRaccoonWithinRange_divertsToTheGarbageCan_consumesIt_andResumesSeekingThePlayerAfterward() {
        let raccoon = RaccoonNode(tier: .base, hp: RaccoonNode.baseMaxHP - 5) // wounded
        let playerPosition = TilePoint(x: 500, y: 0) // far away, opposite direction of travel
        let garbageCanPosition = TilePoint(x: 2, y: 0) // well within diversion range
        var position = TilePoint(x: 0, y: 0)
        var rng = SplitMix64RandomNumberGenerator(seed: 7)

        var consumed = false
        for tick in 0..<400 {
            let result = RaccoonSeekBehavior.updateWithDiversion(
                raccoon: raccoon,
                currentPosition: position,
                playerPosition: playerPosition,
                garbageCanPosition: garbageCanPosition,
                obstructions: [],
                deltaTime: 1.0 / 10.0,
                rng: &rng
            )
            position = result.position

            // Diverting: while not yet consumed, the raccoon must be
            // walking toward the garbage can, never toward the (far away,
            // opposite-direction) player.
            XCTAssertLessThan(
                position.x, playerPosition.x / 2,
                "tick \(tick): a diverting raccoon must never close on the player"
            )

            if result.consumedGarbageCan {
                consumed = true
                break
            }
        }

        XCTAssertTrue(consumed, "a wounded raccoon within range must eventually consume the garbage can")
        XCTAssertGreaterThan(raccoon.hp, RaccoonNode.baseMaxHP - 5, "consuming the garbage can must heal the raccoon")
        XCTAssertLessThanOrEqual(raccoon.hp, raccoon.maxHP, "healing must never exceed maxHP")

        // Resume seeking the player: once the garbage can is treated as
        // consumed the caller stops passing a position for it, and the
        // very next call must move the raccoon toward the player again.
        let beforeResume = position
        let resumed = RaccoonSeekBehavior.updateWithDiversion(
            raccoon: raccoon,
            currentPosition: position,
            playerPosition: playerPosition,
            garbageCanPosition: nil,
            obstructions: [],
            deltaTime: 1.0 / 10.0,
            rng: &rng
        )

        XCTAssertGreaterThan(
            resumed.position.x, beforeResume.x,
            "must resume closing on the player once the garbage can is gone"
        )
        XCTAssertFalse(resumed.consumedGarbageCan)
    }

    // MARK: - An unwounded raccoon ignores the garbage can and keeps seeking the player

    func test_unwoundedRaccoon_ignoresTheGarbageCan_andContinuesSeekingThePlayer() {
        let raccoon = RaccoonNode(tier: .base) // spawns at full HP -- unwounded
        XCTAssertFalse(raccoon.isWounded)

        let playerPosition = TilePoint(x: 5, y: 0)
        let garbageCanPosition = TilePoint(x: 0.5, y: 0) // well within diversion range
        var position = TilePoint(x: 0, y: 0)
        var rng = SplitMix64RandomNumberGenerator(seed: 3)

        for tick in 0..<50 {
            let result = RaccoonSeekBehavior.updateWithDiversion(
                raccoon: raccoon,
                currentPosition: position,
                playerPosition: playerPosition,
                garbageCanPosition: garbageCanPosition,
                obstructions: [],
                deltaTime: 1.0 / 10.0,
                rng: &rng
            )
            position = result.position
            XCTAssertFalse(
                result.consumedGarbageCan,
                "tick \(tick): an unwounded raccoon must never consume a garbage can"
            )
        }

        XCTAssertEqual(
            raccoon.hp, raccoon.maxHP,
            "an unwounded raccoon's HP must be untouched by a garbage can it never diverted to"
        )
        XCTAssertGreaterThan(position.x, 0, "must still have made real progress toward the player")
    }

    // MARK: - seekTarget(...): the pure targeting decision, in isolation

    func test_seekTarget_isTheGarbageCan_whenWoundedAndWithinRange() {
        let raccoon = RaccoonNode(tier: .base, hp: RaccoonNode.baseMaxHP - 1)
        let garbageCanPosition = TilePoint(x: 1, y: 0)

        let target = RaccoonSeekBehavior.seekTarget(
            raccoon: raccoon,
            currentPosition: TilePoint(x: 0, y: 0),
            playerPosition: TilePoint(x: 50, y: 50),
            garbageCanPosition: garbageCanPosition
        )

        XCTAssertEqual(target, garbageCanPosition)
    }

    func test_seekTarget_isThePlayer_whenWoundedButOutOfRange() {
        let raccoon = RaccoonNode(tier: .base, hp: RaccoonNode.baseMaxHP - 1)
        let playerPosition = TilePoint(x: 50, y: 50)
        let farGarbageCanPosition = TilePoint(
            x: RaccoonSeekBehavior.garbageCanDiversionRangeTiles + 1,
            y: 0
        )

        let target = RaccoonSeekBehavior.seekTarget(
            raccoon: raccoon,
            currentPosition: TilePoint(x: 0, y: 0),
            playerPosition: playerPosition,
            garbageCanPosition: farGarbageCanPosition
        )

        XCTAssertEqual(target, playerPosition)
    }

    func test_seekTarget_isThePlayer_whenNotWounded_regardlessOfRange() {
        let raccoon = RaccoonNode(tier: .base) // full HP -- unwounded
        let playerPosition = TilePoint(x: 50, y: 50)
        let nearGarbageCanPosition = TilePoint(x: 0.1, y: 0)

        let target = RaccoonSeekBehavior.seekTarget(
            raccoon: raccoon,
            currentPosition: TilePoint(x: 0, y: 0),
            playerPosition: playerPosition,
            garbageCanPosition: nearGarbageCanPosition
        )

        XCTAssertEqual(
            target, playerPosition,
            "an unwounded raccoon's targeting logic must be untouched by the diversion branch"
        )
    }

    func test_seekTarget_isThePlayer_whenNoGarbageCanExists() {
        let raccoon = RaccoonNode(tier: .base, hp: RaccoonNode.baseMaxHP - 1)
        let playerPosition = TilePoint(x: 50, y: 50)

        let target = RaccoonSeekBehavior.seekTarget(
            raccoon: raccoon,
            currentPosition: TilePoint(x: 0, y: 0),
            playerPosition: playerPosition,
            garbageCanPosition: nil
        )

        XCTAssertEqual(target, playerPosition)
    }

    // MARK: - Consuming is one-shot, even if the caller never stops passing the can (PR #37 review)

    /// The failure mode this pins: `updateWithDiversion` is
    /// `@discardableResult`, so a wiring PR that ticks a swarm and ignores
    /// the return value would keep handing over the same
    /// `garbageCanPosition` forever. Before the raccoon started recording
    /// the can it consumed, that re-rolled and re-applied 1d6 *every
    /// frame* -- roughly 60 HP/s against a `baseMaxHP` of 20 -- with
    /// nothing red in the suite, because the test above `break`s out of its
    /// loop the frame `consumedGarbageCan` first comes back `true`.
    func test_consumedGarbageCan_neverRefires_whenTheCallerKeepsPassingTheSamePosition() {
        let raccoon = RaccoonNode(tier: .base, hp: RaccoonNode.baseMaxHP - 5)
        let playerPosition = TilePoint(x: 500, y: 0)
        let garbageCanPosition = TilePoint(x: 2, y: 0)
        var position = TilePoint(x: 0, y: 0)
        var rng = ScriptedRandomNumberGenerator(0) // every 1d6 rolls exactly 1

        var consumed = false
        for _ in 0..<400 {
            let result = RaccoonSeekBehavior.updateWithDiversion(
                raccoon: raccoon,
                currentPosition: position,
                playerPosition: playerPosition,
                garbageCanPosition: garbageCanPosition,
                obstructions: [],
                deltaTime: 1.0 / 10.0,
                rng: &rng
            )
            position = result.position
            if result.consumedGarbageCan {
                consumed = true
                break
            }
        }

        XCTAssertTrue(consumed, "sanity: the raccoon must reach and consume the garbage can first")
        let hpAfterConsuming = raccoon.hp
        XCTAssertEqual(hpAfterConsuming, RaccoonNode.baseMaxHP - 4, "sanity: exactly one scripted 1d6 (=1) was applied")
        XCTAssertTrue(
            raccoon.isWounded,
            "anti-vacuity: the raccoon must still be wounded, so it is the consumed-can record -- not isWounded -- that stops the re-fire below"
        )

        let positionAtConsumption = position
        for tick in 0..<10 {
            let result = RaccoonSeekBehavior.updateWithDiversion(
                raccoon: raccoon,
                currentPosition: position,
                playerPosition: playerPosition,
                garbageCanPosition: garbageCanPosition, // the caller never stopped passing it
                obstructions: [],
                deltaTime: 1.0 / 10.0,
                rng: &rng
            )
            position = result.position
            XCTAssertFalse(result.consumedGarbageCan, "tick \(tick): the same garbage can must never be consumed twice")
            XCTAssertEqual(raccoon.hp, hpAfterConsuming, "tick \(tick): a consumed garbage can must never heal again")
        }

        XCTAssertGreaterThan(
            position.x, positionAtConsumption.x,
            "having consumed the can, the raccoon must resume seeking the player rather than sitting on it"
        )

        // The record is scoped to that one can: the first frame the caller
        // passes anything else (here `nil`), it is cleared.
        _ = RaccoonSeekBehavior.updateWithDiversion(
            raccoon: raccoon,
            currentPosition: position,
            playerPosition: playerPosition,
            garbageCanPosition: nil,
            obstructions: [],
            deltaTime: 1.0 / 10.0,
            rng: &rng
        )
        XCTAssertNil(raccoon.consumedGarbageCanPosition)
    }

    // MARK: - A dead raccoon is never healed or steered (PR #37 review)

    func test_deadRaccoon_isNeverHealedOrSteeredByAGarbageCan() {
        let raccoon = RaccoonNode(tier: .base, hp: 0)
        XCTAssertTrue(raccoon.isDead)
        XCTAssertTrue(
            raccoon.isWounded,
            "sanity: isWounded is true at hp == 0 -- exactly why the diversion path needs its own isDead guard"
        )

        let startPosition = TilePoint(x: 0, y: 0)
        var position = startPosition
        var rng = ScriptedRandomNumberGenerator(0)

        for tick in 0..<20 {
            let result = RaccoonSeekBehavior.updateWithDiversion(
                raccoon: raccoon,
                currentPosition: position,
                playerPosition: TilePoint(x: 10, y: 0),
                garbageCanPosition: TilePoint(x: 0.2, y: 0), // already inside the arrival radius
                obstructions: [],
                deltaTime: 1.0 / 10.0,
                rng: &rng
            )
            position = result.position
            XCTAssertFalse(result.consumedGarbageCan, "tick \(tick): a dead raccoon must never consume a garbage can")
            XCTAssertEqual(raccoon.hp, 0, "tick \(tick): a garbage can must never resurrect an already-counted raccoon")
        }

        XCTAssertTrue(raccoon.isDead, "isDead must not flip back to false on a node whose kill has already been recorded")
        XCTAssertEqual(position, startPosition, "a dead raccoon must not steer either")
    }

    // MARK: - Diverting is its own decision, not "the target isn't the player" (PR #37 review)

    func test_garbageCanOnThePlayersExactTile_isStillConsumed() {
        let raccoon = RaccoonNode(tier: .base, hp: RaccoonNode.baseMaxHP - 5)
        // The pathological case for a `target != playerPosition` proxy: a
        // garbage can that happens to sit on the player's exact tile.
        let sharedPosition = TilePoint(x: 2, y: 0)
        var position = TilePoint(x: 0, y: 0)
        var rng = ScriptedRandomNumberGenerator(0) // every 1d6 rolls exactly 1

        var consumed = false
        for _ in 0..<400 {
            let result = RaccoonSeekBehavior.updateWithDiversion(
                raccoon: raccoon,
                currentPosition: position,
                playerPosition: sharedPosition,
                garbageCanPosition: sharedPosition,
                obstructions: [],
                deltaTime: 1.0 / 10.0,
                rng: &rng
            )
            position = result.position
            if result.consumedGarbageCan {
                consumed = true
                break
            }
        }

        XCTAssertTrue(
            consumed,
            "whether a raccoon is diverting must come from the wounded/range decision itself, not from comparing the resolved target against the player's position"
        )
        XCTAssertEqual(raccoon.hp, RaccoonNode.baseMaxHP - 4)
    }

    // MARK: - divertTarget(...): the diversion decision, in isolation

    func test_divertTarget_isNil_onceThatCanHasBeenConsumed_butNotForADifferentCan() {
        let raccoon = RaccoonNode(tier: .base, hp: RaccoonNode.baseMaxHP - 1)
        let currentPosition = TilePoint(x: 0, y: 0)
        let garbageCanPosition = TilePoint(x: 1, y: 0)

        XCTAssertEqual(
            RaccoonSeekBehavior.divertTarget(
                raccoon: raccoon,
                currentPosition: currentPosition,
                garbageCanPosition: garbageCanPosition
            ),
            garbageCanPosition
        )

        raccoon.consumedGarbageCanPosition = garbageCanPosition
        XCTAssertNil(
            RaccoonSeekBehavior.divertTarget(
                raccoon: raccoon,
                currentPosition: currentPosition,
                garbageCanPosition: garbageCanPosition
            ),
            "a can this raccoon has already consumed must never be a diversion target again"
        )

        let otherGarbageCanPosition = TilePoint(x: -1, y: 0)
        XCTAssertEqual(
            RaccoonSeekBehavior.divertTarget(
                raccoon: raccoon,
                currentPosition: currentPosition,
                garbageCanPosition: otherGarbageCanPosition
            ),
            otherGarbageCanPosition,
            "a different garbage can is still a legal diversion target"
        )
    }

    func test_divertTarget_isNil_forADeadRaccoon() {
        let raccoon = RaccoonNode(tier: .base, hp: 0)

        XCTAssertNil(
            RaccoonSeekBehavior.divertTarget(
                raccoon: raccoon,
                currentPosition: TilePoint(x: 0, y: 0),
                garbageCanPosition: TilePoint(x: 0.2, y: 0)
            )
        )
    }
}
