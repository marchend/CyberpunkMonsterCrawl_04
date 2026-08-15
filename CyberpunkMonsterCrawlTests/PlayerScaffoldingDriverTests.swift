import CoreGraphics
import XCTest
@testable import CyberpunkMonsterCrawl

/// CYBERPUN-17-6-t3: `PlayerScaffoldingDriver` is a `// SCAFFOLDING:`
/// temporary generator that cycles the mounted player through all 8
/// `Direction8` facings (plus a trailing idle beat) so `PlayerNode` is
/// demonstrably animating in a running build ahead of `CYBERPUN-17-7`'s
/// real floating thumbstick.
///
/// Every test here drives a bare `PlayerNode()` -- no `GameScene`, no
/// `SKView` -- which is itself part of what is pinned: the driver's only
/// production coupling is `PlayerNode`'s own public
/// `update(deltaTime:movementVector:)` API.
final class PlayerScaffoldingDriverTests: XCTestCase {

    // MARK: - Starts idle (matches PlayerNode's own idle-at-spawn default)

    func test_driver_startsIdle_untilTheFirstFullStepElapses() {
        let player = PlayerNode()
        let driver = PlayerScaffoldingDriver(player: player)

        // A delta far short of a full step must not move the player --
        // this is what keeps a freshly-spawned player standing still,
        // matching `PlayerMountTests`' "idle at frame zero" expectations,
        // rather than snapping into motion the instant the scene starts
        // ticking.
        driver.advance(deltaTime: 0)
        XCTAssertFalse(player.isMoving)
        XCTAssertEqual(player.facing, .south, "A never-moved PlayerNode keeps its default facing.")

        driver.advance(deltaTime: PlayerScaffoldingDriver.secondsPerStep / 2)
        XCTAssertFalse(player.isMoving, "Half a step must not be enough to advance past the idle beat.")
    }

    // MARK: - Cycles through all 8 facings, in the story's specified order

    func test_driver_cyclesThroughAllEightFacings_inOrder_afterEachFullStep() {
        let player = PlayerNode()
        let driver = PlayerScaffoldingDriver(player: player)

        let expectedOrder: [Direction8] = [
            .south, .southeast, .east, .northeast, .north, .northwest, .west, .southwest,
        ]

        for direction in expectedOrder {
            driver.advance(deltaTime: PlayerScaffoldingDriver.secondsPerStep)
            XCTAssertTrue(player.isMoving, "\(direction): expected the driver to be mid-cycle, moving.")
            XCTAssertEqual(player.facing, direction, "Cycle order did not match S->SE->E->NE->N->NW->W->SW.")
        }

        // The cycle's final entry is the trailing idle beat, wrapping back
        // around after the 8th facing.
        driver.advance(deltaTime: PlayerScaffoldingDriver.secondsPerStep)
        XCTAssertFalse(player.isMoving, "The lap must wrap back around to an idle beat, per the story's cycle order.")

        // ...and a further full lap repeats identically.
        for direction in expectedOrder {
            driver.advance(deltaTime: PlayerScaffoldingDriver.secondsPerStep)
            XCTAssertTrue(player.isMoving)
            XCTAssertEqual(player.facing, direction, "The cycle must repeat identically on a second lap.")
        }
    }

    // MARK: - Every Direction8 case is reachable, even advancing in sub-step increments

    func test_driver_advancingInSubStepIncrements_stillDemonstratesEveryDirection8Case() {
        let player = PlayerNode()
        let driver = PlayerScaffoldingDriver(player: player)

        var seenDirections: Set<Direction8> = []
        let increment = PlayerScaffoldingDriver.secondsPerStep / 4
        // 10 seconds' worth of quarter-step ticks: enough for a full lap
        // (9 steps) plus a little, at 4 ticks/step.
        for _ in 0..<(9 * 4 + 4) {
            driver.advance(deltaTime: increment)
            if player.isMoving {
                seenDirections.insert(player.facing)
            }
        }

        XCTAssertEqual(
            seenDirections, Set(Direction8.allCases),
            "Every Direction8 case must be demonstrated somewhere across the cycle."
        )
    }

    // MARK: - A long delta (crossing several step boundaries) still lands correctly

    func test_driver_aLongSingleDelta_stillAdvancesToTheCorrectStep() {
        let player = PlayerNode()
        let driver = PlayerScaffoldingDriver(player: player)

        // 3 full steps in one call: idle -> south -> southeast -> east.
        driver.advance(deltaTime: PlayerScaffoldingDriver.secondsPerStep * 3)

        XCTAssertTrue(player.isMoving)
        XCTAssertEqual(player.facing, .east)
    }

    // MARK: - Zero production coupling beyond PlayerNode's public update API

    func test_driver_neverTouchesAnythingButPlayerNodesPublicUpdateAPI() {
        // Constructed and driven against a bare, unmounted PlayerNode -- no
        // GameScene, no worldLayer, no SKView -- and driving it must not
        // require or cause any of that to exist.
        let player = PlayerNode()
        XCTAssertNil(player.parent)

        let driver = PlayerScaffoldingDriver(player: player)
        for _ in 0..<20 {
            driver.advance(deltaTime: PlayerScaffoldingDriver.secondsPerStep)
        }

        XCTAssertNil(player.parent, "The driver must never mount, unmount or reparent the player itself.")
    }
}
