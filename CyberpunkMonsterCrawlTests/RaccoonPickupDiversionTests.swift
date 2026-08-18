import CoreGraphics
import XCTest
@testable import CyberpunkMonsterCrawl

/// `CYBERPUN-17-11` PR 2: `RaccoonSeekBehavior.updateWithDiversion(...)` --
/// wounded-raccoon garbage-can diversion (divert while in range, consume
/// on arrival for 1d6, resume seeking the player once the caller stops
/// passing a garbage-can position), proven entirely independent of
/// GameScene/PickupManager per this PR's acceptance criteria.
final class RaccoonPickupDiversionTests: XCTestCase {

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
}
